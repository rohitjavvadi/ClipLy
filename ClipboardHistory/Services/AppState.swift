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

    var settings = AppSettings()
    let storage: StorageService
    let pasteService: PasteService

    var onShortcutChanged: ((UInt32, UInt32) -> Void)?
    var onDockIconPreferenceChanged: ((Bool) -> Void)?

    private let retentionService: RetentionService

    init() {
        storage = StorageService()
        pasteService = PasteService()
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
        selectedFilter = filters[nextIndex]
        refreshRecords()
    }

    func selectedRecord() -> ClipboardRecord? {
        guard let selectedRecordID else { return records.first }
        return records.first { $0.id == selectedRecordID }
    }

    func restoreSelectedAndPaste() {
        guard let record = selectedRecord() else { return }
        pasteService.restoreAndPaste(record)
    }

    func clearHistory() {
        storage.clearAll()
        refreshRecords()
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
