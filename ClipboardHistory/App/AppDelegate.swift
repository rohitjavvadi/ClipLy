import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem?
    private var launcher: LauncherWindowController?
    private var settingsWindow: SettingsWindowController?
    private var monitor: ClipboardMonitor?
    private var hotKeyService: HotKeyService?

    func applicationDidFinishLaunching(_ notification: Notification) {
        appState.bootstrap()
        applyDockIconPreference(appState.settings.showDockIcon)

        launcher = LauncherWindowController(appState: appState) { [weak self] in
            self?.appState.isLauncherVisible = false
            self?.appState.exitMultiSelectMode()
        }
        settingsWindow = SettingsWindowController(appState: appState)
        monitor = ClipboardMonitor(storage: appState.storage, settings: appState.settings) { [weak self] in
            self?.appState.refreshRecords()
        }
        monitor?.start()

        appState.pasteService.onBeforePaste = { [weak self] in
            self?.hideLauncher()
        }
        appState.pasteService.onWillWritePasteboard = { [weak self] in
            self?.monitor?.ignoreNextPasteboardChange()
        }

        hotKeyService = HotKeyService { [weak self] in
            self?.toggleLauncher()
        }
        appState.onShortcutChanged = { [weak self] keyCode, modifiers in
            self?.hotKeyService?.registerShortcut(keyCode: keyCode, modifiers: modifiers)
        }
        appState.onDockIconPreferenceChanged = { [weak self] showDockIcon in
            self?.applyDockIconPreference(showDockIcon)
        }
        hotKeyService?.registerShortcut(
            keyCode: appState.settings.shortcutKeyCode,
            modifiers: appState.settings.shortcutModifiers
        )
        buildStatusItem()
    }

    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "ClipLy")
        image?.isTemplate = true
        item.button?.image = image
        item.button?.imagePosition = .imageOnly
        item.menu = makeMenu()
        statusItem = item
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open ClipLy", action: #selector(openFromMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let pauseItem = NSMenuItem(title: appState.settings.capturePaused ? "Resume Capture" : "Pause Capture", action: #selector(togglePause), keyEquivalent: "")
        menu.addItem(pauseItem)

        let retentionMenu = NSMenu()
        for period in RetentionPeriod.allCases {
            let item = NSMenuItem(title: period.title, action: #selector(setRetentionPeriod(_:)), keyEquivalent: "")
            item.representedObject = period.rawValue
            item.state = period == appState.settings.retentionPeriod ? .on : .off
            retentionMenu.addItem(item)
        }
        let retentionItem = NSMenuItem(title: "Keep History", action: nil, keyEquivalent: "")
        retentionItem.submenu = retentionMenu
        menu.addItem(retentionItem)

        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        return menu
    }

    private func rebuildMenu() {
        statusItem?.menu = makeMenu()
    }

    private func applyDockIconPreference(_ showDockIcon: Bool) {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        if showDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    @objc private func openFromMenu() {
        showLauncher()
    }

    @objc private func togglePause() {
        appState.settings.capturePaused.toggle()
        rebuildMenu()
    }

    @objc private func setRetentionPeriod(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? Int,
              let period = RetentionPeriod(rawValue: raw) else { return }
        appState.settings.retentionPeriod = period
        appState.bootstrap()
        rebuildMenu()
    }

    @objc private func clearHistory() {
        appState.clearHistory()
    }

    @objc private func openSettings() {
        settingsWindow?.show()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func toggleLauncher() {
        if appState.isLauncherVisible {
            hideLauncher()
        } else {
            showLauncher()
        }
    }

    private func showLauncher() {
        appState.pasteService.rememberFrontmostApplication()
        appState.prepareForLauncherOpen()
        appState.isLauncherVisible = true
        launcher?.show()
    }

    private func hideLauncher() {
        appState.isLauncherVisible = false
        launcher?.hide()
    }
}
