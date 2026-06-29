import AppKit
import Foundation

@MainActor
final class ClipboardMonitor {
    private let pasteboard = NSPasteboard.general
    private let storage: StorageService
    private let settings: AppSettings
    private let onChange: () -> Void
    private var timer: Timer?
    private var lastChangeCount: Int
    private var ignoredChangeCount: Int?

    init(storage: StorageService, settings: AppSettings, onChange: @escaping () -> Void) {
        self.storage = storage
        self.settings = settings
        self.onChange = onChange
        lastChangeCount = pasteboard.changeCount
    }

    func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.75, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func ignoreNextPasteboardChange() {
        ignoredChangeCount = pasteboard.changeCount + 1
    }

    private func tick() {
        guard !settings.capturePaused else {
            lastChangeCount = pasteboard.changeCount
            return
        }

        let changeCount = pasteboard.changeCount
        guard changeCount != lastChangeCount else { return }
        lastChangeCount = changeCount

        if ignoredChangeCount == changeCount {
            ignoredChangeCount = nil
            return
        }

        guard let captured = captureCurrentPasteboard() else { return }
        storage.insert(captured)
        onChange()
    }

    private func captureCurrentPasteboard() -> CapturedClipboardItem? {
        let id = UUID()
        let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL] ?? []
        let cleanText = bestTextRepresentation()
        let image = NSImage(pasteboard: pasteboard)

        let filePaths = fileURLs.map(\.path)
        let fileNames = fileURLs.map(\.lastPathComponent)

        var imagePath: String?
        var thumbnailPath: String?
        var byteCount: Int64 = fileURLs.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
            return total + size
        }
        var imageDataForHash: Data?

        if let image {
            let stored = storage.storeImage(image, id: id)
            imagePath = stored.imagePath
            thumbnailPath = stored.thumbnailPath
            byteCount += stored.byteCount
            imageDataForHash = image.tiffRepresentation
        }

        guard cleanText != nil || imagePath != nil || !filePaths.isEmpty else {
            return nil
        }

        let kind: ClipboardKind
        let representedKinds = [cleanText != nil, imagePath != nil, !filePaths.isEmpty].filter { $0 }.count
        if representedKinds > 1 {
            kind = .mixed
        } else if cleanText != nil {
            kind = .text
        } else if imagePath != nil {
            kind = .image
        } else {
            kind = .file
        }

        let hash = clipboardHash(parts: [kind.rawValue, cleanText ?? "", filePaths.joined(separator: "|")], data: imageDataForHash)
        return CapturedClipboardItem(
            id: id,
            kind: kind,
            createdAt: Date(),
            text: cleanText,
            imagePath: imagePath,
            thumbnailPath: thumbnailPath,
            filePaths: filePaths,
            fileNames: fileNames,
            byteCount: byteCount,
            hash: hash
        )
    }

    private func bestTextRepresentation() -> String? {
        let providers: [() -> String?] = [
            { self.pasteboard.string(forType: .string) },
            { self.pasteboard.string(forType: .URL) },
            { self.pasteboard.string(forType: .init("org.chromium.source-url")) },
            { self.attributedText(for: .rtf) },
            { self.attributedText(for: .rtfd) },
            { self.htmlText() }
        ]

        for provider in providers {
            if let text = cleanedText(provider()) {
                return text
            }
        }
        return nil
    }

    private func attributedText(for type: NSPasteboard.PasteboardType) -> String? {
        guard let data = pasteboard.data(forType: type) else { return nil }
        let documentType: NSAttributedString.DocumentType = type == .rtfd ? .rtfd : .rtf
        let attributed = try? NSAttributedString(
            data: data,
            options: [.documentType: documentType],
            documentAttributes: nil
        )
        return attributed?.string
    }

    private func htmlText() -> String? {
        guard let html = pasteboard.string(forType: .html),
              let data = html.data(using: .utf8) else {
            return nil
        }

        if let attributed = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
        ) {
            return attributed.string
        }

        return html
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private func cleanedText(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: "\u{fffc}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}
