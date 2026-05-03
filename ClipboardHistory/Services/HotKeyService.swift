import Carbon
import Foundation

@MainActor
final class HotKeyService {
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private let onPressed: () -> Void

    init(onPressed: @escaping () -> Void) {
        self.onPressed = onPressed
    }

    deinit {
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
        }
    }

    func registerShortcut(keyCode: UInt32, modifiers: UInt32) {
        unregisterShortcut()

        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        if eventHandler == nil {
            var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(
                GetApplicationEventTarget(),
                { _, _, userData in
                    guard let userData else { return noErr }
                    let service = Unmanaged<HotKeyService>.fromOpaque(userData).takeUnretainedValue()
                    Task { @MainActor in
                        service.onPressed()
                    }
                    return noErr
                },
                1,
                &eventSpec,
                selfPointer,
                &eventHandler
            )
        }

        let hotKeyID = EventHotKeyID(signature: OSType("CLPH".fourCharCode), id: 1)
        RegisterEventHotKey(
            keyCode,
            modifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    private func unregisterShortcut() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }
}

private extension String {
    var fourCharCode: UInt32 {
        utf8.reduce(0) { ($0 << 8) + UInt32($1) }
    }
}
