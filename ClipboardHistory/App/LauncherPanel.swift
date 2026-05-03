import AppKit
import SwiftUI

final class LauncherPanel: NSPanel {
    var onMoveSelection: ((Int) -> Void)?
    var onMoveFilter: ((Int) -> Void)?
    var onCommit: (() -> Void)?
    var onClosePanel: (() -> Void)?

    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = .floating
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        hidesOnDeactivate = true
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126:
            onMoveSelection?(-1)
        case 125:
            onMoveSelection?(1)
        case 123:
            onMoveFilter?(-1)
        case 124:
            onMoveFilter?(1)
        case 36, 76:
            onCommit?()
        case 53:
            onClosePanel?()
        default:
            super.keyDown(with: event)
        }
    }
}

@MainActor
final class LauncherWindowController {
    private let panel: LauncherPanel
    private var keyMonitor: Any?
    private var observers: [NSObjectProtocol] = []
    private let onHide: () -> Void

    init(appState: AppState, onHide: @escaping () -> Void) {
        self.onHide = onHide
        let width: CGFloat = 760
        let height: CGFloat = 560
        panel = LauncherPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height))
        panel.contentView = NSHostingView(rootView: LauncherView(appState: appState))
        panel.onMoveSelection = { [weak appState] delta in
            appState?.moveSelection(delta)
        }
        panel.onMoveFilter = { [weak appState] delta in
            appState?.moveFilter(delta)
        }
        panel.onCommit = { [weak appState] in
            appState?.restoreSelectedAndPaste()
        }
        panel.onClosePanel = { [weak self] in
            self?.hide()
        }
    }

    func show() {
        center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        installKeyMonitorIfNeeded()
        installObserversIfNeeded()
    }

    func hide() {
        panel.orderOut(nil)
        removeKeyMonitor()
        removeObservers()
        onHide()
    }

    private func center() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.maxY - size.height - 96
        )
        panel.setFrameOrigin(origin)
    }

    private func installKeyMonitorIfNeeded() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            switch event.keyCode {
            case 53:
                self.hide()
                return nil
            case 123:
                self.panel.onMoveFilter?(-1)
                return nil
            case 124:
                self.panel.onMoveFilter?(1)
                return nil
            case 126:
                self.panel.onMoveSelection?(-1)
                return nil
            case 125:
                self.panel.onMoveSelection?(1)
                return nil
            case 36, 76:
                self.panel.onCommit?()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func installObserversIfNeeded() {
        guard observers.isEmpty else { return }

        let notificationCenter = NotificationCenter.default
        observers.append(
            notificationCenter.addObserver(
                forName: NSWindow.didResignKeyNotification,
                object: panel,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.hide()
                }
            }
        )

        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.activeSpaceDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    self?.hide()
                }
            }
        )

        observers.append(
            NSWorkspace.shared.notificationCenter.addObserver(
                forName: NSWorkspace.didActivateApplicationNotification,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self else { return }
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                if app?.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                    Task { @MainActor in
                        self.hide()
                    }
                }
            }
        )
    }

    private func removeObservers() {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }
}
