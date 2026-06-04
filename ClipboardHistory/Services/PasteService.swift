import AppKit
import ApplicationServices
import Foundation

@MainActor
final class PasteService {
    var onBeforePaste: (() -> Void)?
    var onWillWritePasteboard: (() -> Void)?
    private var previousApplication: NSRunningApplication?

    func rememberFrontmostApplication() {
        previousApplication = NSWorkspace.shared.frontmostApplication
    }

    func copyStringToPasteboard(_ string: String) {
        guard !string.isEmpty else { return }
        onWillWritePasteboard?()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }

    func restoreAndPaste(_ record: ClipboardRecord) {
        onWillWritePasteboard?()
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        var wroteObject = false
        if let text = record.text {
            pasteboard.setString(text, forType: .string)
            wroteObject = true
        }

        if let imagePath = record.imagePath, let image = NSImage(contentsOfFile: imagePath) {
            pasteboard.writeObjects([image])
            wroteObject = true
        }

        let urls = record.filePaths.map { URL(fileURLWithPath: $0) }
        if !urls.isEmpty {
            pasteboard.writeObjects(urls as [NSURL])
            wroteObject = true
        }

        guard wroteObject else { return }

        onBeforePaste?()
        previousApplication?.activate(options: [])
        requestAccessibilityIfNeeded()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
            self.sendCommandV()
        }
    }

    private func requestAccessibilityIfNeeded() {
        let prompt = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        AXIsProcessTrustedWithOptions([prompt: true] as CFDictionary)
    }

    private func sendCommandV() {
        guard AXIsProcessTrusted() else { return }
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
