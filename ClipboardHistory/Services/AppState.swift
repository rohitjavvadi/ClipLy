import AppKit
import Foundation
import Observation

@MainActor
@Observable
final class AppState {
    var records: [ClipboardRecord] = []
    var query = ""
    var selectedFilter: HistoryFilter = .all
    var selectedRecordID: UUID?
    var isLauncherVisible = false
    var launchAtLoginEnabled = false
    var launchAtLoginError: String?
    var isMultiSelectMode = false
    var multiSelectedRecordIDs: Set<UUID> = []
    var shareErrorMessage: String?

    var settings = AppSettings()
    let storage: StorageService
    let pasteService: PasteService
    let shareService: ShareService

    var onShortcutChanged: ((UInt32, UInt32) -> Void)?
    var onDockIconPreferenceChanged: ((Bool) -> Void)?

    private let retentionService: RetentionService

    init() {
        storage = StorageService()
        pasteService = PasteService()
        shareService = ShareService()
        retentionService = RetentionService(storage: storage)
    }

    func bootstrap() {
        refreshLaunchAtLoginState()
        retentionService.cleanup(olderThanDays: settings.retentionPeriod.rawValue)
        refreshRecords()
    }

    func refreshRecords() {
        records = storage.search(query: query, filter: selectedFilter, limit: 250)
        if selectedRecordID == nil || !records.contains(where: { $0.id == selectedRecordID }) {
            selectedRecordID = records.first?.id
        }
        pruneMultiSelection()
        if !canUseMultiSelect {
            exitMultiSelectMode()
        }
    }

    func prepareForLauncherOpen() {
        query = ""
        selectedRecordID = nil
        shareErrorMessage = nil
        exitMultiSelectMode()
        refreshRecords()
    }

    func moveSelection(_ delta: Int) {
        guard !records.isEmpty else {
            selectedRecordID = nil
            return
        }
        let currentIndex = selectedRecordID.flatMap { id in records.firstIndex { $0.id == id } } ?? 0
        let nextIndex = min(max(currentIndex + delta, 0), records.count - 1)
        selectedRecordID = records[nextIndex].id
    }

    func moveFilter(_ delta: Int) {
        let filters = HistoryFilter.allCases
        guard let currentIndex = filters.firstIndex(of: selectedFilter) else { return }
        let nextIndex = min(max(currentIndex + delta, 0), filters.count - 1)
        selectFilter(filters[nextIndex])
    }

    func selectFilter(_ filter: HistoryFilter) {
        guard filter != selectedFilter else { return }
        exitMultiSelectMode()
        selectedFilter = filter
        refreshRecords()
    }

    func selectedRecord() -> ClipboardRecord? {
        guard let selectedRecordID else { return records.first }
        return records.first { $0.id == selectedRecordID }
    }

    func restoreSelectedAndPaste() {
        guard !isMultiSelectMode else { return }
        guard let record = selectedRecord() else { return }
        pasteService.restoreAndPaste(record)
    }

    func clearHistory() {
        exitMultiSelectMode()
        storage.clearAll()
        refreshRecords()
    }

    var canUseMultiSelect: Bool {
        selectedFilter == .images || selectedFilter == .files
    }

    var multiSelectedCount: Int {
        records.filter { multiSelectedRecordIDs.contains($0.id) }.count
    }

    var canShareMultiSelection: Bool {
        isMultiSelectMode && multiSelectedCount > 0
    }

    func toggleMultiSelectMode() {
        if isMultiSelectMode {
            exitMultiSelectMode()
        } else {
            enterMultiSelectMode()
        }
    }

    func enterMultiSelectMode() {
        guard canUseMultiSelect else { return }
        isMultiSelectMode = true
        shareErrorMessage = nil
        pruneMultiSelection()
    }

    func exitMultiSelectMode() {
        isMultiSelectMode = false
        multiSelectedRecordIDs.removeAll()
        shareErrorMessage = nil
    }

    func toggleMultiSelection(for record: ClipboardRecord) {
        guard isMultiSelectMode && canUseMultiSelect else { return }
        selectedRecordID = record.id
        shareErrorMessage = nil
        if multiSelectedRecordIDs.contains(record.id) {
            multiSelectedRecordIDs.remove(record.id)
        } else {
            multiSelectedRecordIDs.insert(record.id)
        }
    }

    func toggleSelectedRecordForSharing() {
        guard let record = selectedRecord() else { return }
        toggleMultiSelection(for: record)
    }

    func handleEscapeInLauncher() -> Bool {
        guard isMultiSelectMode else { return false }
        exitMultiSelectMode()
        return true
    }

    func shareSelectedItems(relativeTo view: NSView?) {
        guard isMultiSelectMode && canUseMultiSelect else { return }
        pruneMultiSelection()
        guard multiSelectedCount > 0 else { return }

        let selectedRecords = records.filter { multiSelectedRecordIDs.contains($0.id) }
        let urls = shareService.shareableURLs(for: selectedRecords, filter: selectedFilter)
        guard !urls.isEmpty else {
            multiSelectedRecordIDs.removeAll()
            shareErrorMessage = "Selected items are no longer available on disk."
            return
        }
        guard let view else { return }
        shareErrorMessage = nil
        shareService.showSharePicker(with: urls, relativeTo: view)
    }

    func copyablePathText(for record: ClipboardRecord) -> String? {
        let paths: [String]
        switch selectedFilter {
        case .images:
            paths = record.imagePath.map { [$0] } ?? []
        case .files:
            paths = record.filePaths
        case .all, .text:
            paths = []
        }

        let existingPaths = paths.filter { FileManager.default.fileExists(atPath: $0) }
        guard !existingPaths.isEmpty else { return nil }
        return existingPaths.joined(separator: "\n")
    }

    func copyPathTitle(for record: ClipboardRecord) -> String {
        guard let pathText = copyablePathText(for: record) else { return "Copy Path" }
        return pathText.contains("\n") ? "Copy Paths" : "Copy Path"
    }

    func copyPath(for record: ClipboardRecord) {
        guard let pathText = copyablePathText(for: record) else { return }
        pasteService.copyStringToPasteboard(pathText)
    }

    private func pruneMultiSelection() {
        let visibleIDs = Set(records.map(\.id))
        multiSelectedRecordIDs = multiSelectedRecordIDs.intersection(visibleIDs)
    }

    func deleteAllDataAndQuit() {
        try? LoginItemService.setEnabled(false)
        if let bundleIdentifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        }
        UserDefaults.standard.synchronize()
        storage.deleteApplicationSupportData()
        NSApp.terminate(nil)
    }

    func updateShortcut(keyCode: UInt32, modifiers: UInt32) {
        settings.shortcutKeyCode = keyCode
        settings.shortcutModifiers = modifiers
        onShortcutChanged?(keyCode, modifiers)
    }

    func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = LoginItemService.isEnabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemService.setEnabled(enabled)
            launchAtLoginEnabled = LoginItemService.isEnabled
            launchAtLoginError = nil
        } catch {
            launchAtLoginEnabled = LoginItemService.isEnabled
            launchAtLoginError = error.localizedDescription
        }
    }

    func setShowDockIcon(_ enabled: Bool) {
        settings.showDockIcon = enabled
        onDockIconPreferenceChanged?(enabled)
    }
}
