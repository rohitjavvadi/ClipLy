import Foundation

enum ClipboardKind: String, CaseIterable, Codable, Identifiable {
    case text
    case image
    case file
    case mixed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .text: "Text"
        case .image: "Image"
        case .file: "File"
        case .mixed: "Mixed"
        }
    }

    var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .image: "photo"
        case .file: "doc"
        case .mixed: "square.stack.3d.up"
        }
    }
}

enum HistoryFilter: String, CaseIterable, Identifiable {
    case all
    case text
    case images
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: "All"
        case .text: "Text"
        case .images: "Images"
        case .files: "Files"
        }
    }
}

enum RetentionPeriod: Int, CaseIterable, Identifiable {
    case oneDay = 1
    case threeDays = 3
    case sevenDays = 7
    case fourteenDays = 14
    case oneMonth = 30

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .oneDay: "1 day"
        case .threeDays: "3 days"
        case .sevenDays: "7 days"
        case .fourteenDays: "14 days"
        case .oneMonth: "1 month"
        }
    }
}

struct ClipboardRecord: Identifiable, Equatable {
    let id: UUID
    let kind: ClipboardKind
    let createdAt: Date
    let text: String?
    let imagePath: String?
    let thumbnailPath: String?
    let filePaths: [String]
    let fileNames: [String]
    let byteCount: Int64
    let hash: String

    var title: String {
        if let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.singleLineTrimmed(maxLength: 90)
        }
        if !fileNames.isEmpty {
            return fileNames.joined(separator: ", ")
        }
        if kind == .image {
            return "Image"
        }
        return kind.title
    }

    var subtitle: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        let age = formatter.localizedString(for: createdAt, relativeTo: Date())
        switch kind {
        case .text:
            return "\(age) · Text"
        case .image:
            return "\(age) · Image"
        case .file:
            return "\(age) · \(filePaths.count) file\(filePaths.count == 1 ? "" : "s")"
        case .mixed:
            return "\(age) · Mixed"
        }
    }

    var searchText: String {
        ([text, fileNames.joined(separator: " "), filePaths.joined(separator: " ")]
            .compactMap { $0 })
            .joined(separator: " ")
    }
}

extension String {
    func singleLineTrimmed(maxLength: Int) -> String {
        let collapsed = components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count <= maxLength {
            return collapsed
        }
        return String(collapsed.prefix(maxLength - 1)) + "…"
    }
}
