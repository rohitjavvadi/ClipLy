import AppKit
import Foundation

@MainActor
final class ShareService {
    private var sharingPicker: NSSharingServicePicker?

    func shareableURLs(for records: [ClipboardRecord], filter: HistoryFilter) -> [URL] {
        var seenPaths: Set<String> = []
        var urls: [URL] = []

        for record in records {
            let paths: [String]
            switch filter {
            case .images:
                paths = record.imagePath.map { [$0] } ?? []
            case .files:
                paths = record.filePaths
            case .all, .text:
                paths = []
            }

            for path in paths where !seenPaths.contains(path) {
                guard FileManager.default.fileExists(atPath: path) else { continue }
                seenPaths.insert(path)
                urls.append(URL(fileURLWithPath: path))
            }
        }

        return urls
    }

    func showSharePicker(with urls: [URL], relativeTo view: NSView) {
        guard !urls.isEmpty else { return }
        let picker = NSSharingServicePicker(items: urls)
        sharingPicker = picker
        picker.show(relativeTo: view.bounds, of: view, preferredEdge: .maxY)
    }
}
