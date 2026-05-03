import AppKit
import CryptoKit
import Foundation
import SQLite3

final class StorageService {
    private let queue = DispatchQueue(label: "ClipLy.Storage")
    private let appSupportURL: URL
    private let blobsURL: URL
    private let thumbnailsURL: URL
    private let databaseURL: URL
    private var db: OpaquePointer?

    init() {
        let appSupportRoot = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let base = appSupportRoot.appendingPathComponent("ClipLy", isDirectory: true)
        let legacyBase = appSupportRoot.appendingPathComponent("ClipboardHistory", isDirectory: true)
        if !FileManager.default.fileExists(atPath: base.path),
           FileManager.default.fileExists(atPath: legacyBase.path) {
            try? FileManager.default.moveItem(at: legacyBase, to: base)
        }
        appSupportURL = base
        blobsURL = base.appendingPathComponent("Blobs", isDirectory: true)
        thumbnailsURL = base.appendingPathComponent("Thumbnails", isDirectory: true)
        databaseURL = base.appendingPathComponent("history.sqlite")

        try? FileManager.default.createDirectory(at: blobsURL, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: thumbnailsURL, withIntermediateDirectories: true)
        openDatabase()
        migrate()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    func insert(_ captured: CapturedClipboardItem) {
        queue.async {
            let sql = """
            INSERT OR IGNORE INTO clips
            (id, kind, created_at, text, image_path, thumbnail_path, file_paths, file_names, byte_count, hash)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(self.db, sql, -1, &statement, nil) == SQLITE_OK else { return }
            defer { sqlite3_finalize(statement) }

            sqlite3_bind_text(statement, 1, captured.id.uuidString, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 2, captured.kind.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(statement, 3, captured.createdAt.timeIntervalSince1970)
            sqlite3_bind_optional_text(statement, 4, captured.text)
            sqlite3_bind_optional_text(statement, 5, captured.imagePath)
            sqlite3_bind_optional_text(statement, 6, captured.thumbnailPath)
            sqlite3_bind_text(statement, 7, captured.filePaths.joined(separator: "\n"), -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(statement, 8, captured.fileNames.joined(separator: "\n"), -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(statement, 9, captured.byteCount)
            sqlite3_bind_text(statement, 10, captured.hash, -1, SQLITE_TRANSIENT)
            sqlite3_step(statement)
        }
    }

    func search(query: String, filter: HistoryFilter, limit: Int) -> [ClipboardRecord] {
        queue.sync {
            let terms = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            var clauses: [String] = []
            var bindings: [String] = []

            switch filter {
            case .all:
                break
            case .text:
                clauses.append("kind IN ('text', 'mixed')")
            case .images:
                clauses.append("kind IN ('image', 'mixed')")
            case .files:
                clauses.append("kind IN ('file', 'mixed')")
            }

            if !terms.isEmpty {
                clauses.append("(lower(coalesce(text, '')) LIKE ? OR lower(file_names) LIKE ? OR lower(file_paths) LIKE ?)")
                let pattern = "%\(terms)%"
                bindings.append(contentsOf: [pattern, pattern, pattern])
            }

            let whereClause = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
            let sql = """
            SELECT id, kind, created_at, text, image_path, thumbnail_path, file_paths, file_names, byte_count, hash
            FROM clips
            \(whereClause)
            ORDER BY created_at DESC
            LIMIT \(max(1, limit));
            """

            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
            defer { sqlite3_finalize(statement) }

            for (index, binding) in bindings.enumerated() {
                sqlite3_bind_text(statement, Int32(index + 1), binding, -1, SQLITE_TRANSIENT)
            }

            var records: [ClipboardRecord] = []
            while sqlite3_step(statement) == SQLITE_ROW {
                if let record = ClipboardRecord(statement: statement) {
                    records.append(record)
                }
            }
            return records
        }
    }

    func deleteOlderThan(days: Int) {
        queue.sync {
            let cutoff = Date().addingTimeInterval(TimeInterval(-days * 24 * 60 * 60)).timeIntervalSince1970
            let expired = recordsOlderThan(cutoff: cutoff)

            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "DELETE FROM clips WHERE created_at < ?;", -1, &statement, nil)
            sqlite3_bind_double(statement, 1, cutoff)
            sqlite3_step(statement)
            sqlite3_finalize(statement)

            for record in expired {
                removeAssets(for: record)
            }
        }
    }

    func clearAll() {
        queue.sync {
            sqlite3_exec(db, "DELETE FROM clips;", nil, nil, nil)
            removeDirectoryContents(blobsURL)
            removeDirectoryContents(thumbnailsURL)
        }
    }

    func deleteApplicationSupportData() {
        queue.sync {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
            try? FileManager.default.removeItem(at: appSupportURL)
        }
    }

    func storeImage(_ image: NSImage, id: UUID) -> (imagePath: String?, thumbnailPath: String?, byteCount: Int64) {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            return (nil, nil, 0)
        }

        let imageURL = blobsURL.appendingPathComponent("\(id.uuidString).png")
        try? png.write(to: imageURL, options: .atomic)

        let thumbnail = image.resized(maxPixelSize: 256)
        let thumbnailData = thumbnail.pngData()
        let thumbnailURL = thumbnailsURL.appendingPathComponent("\(id.uuidString).png")
        try? thumbnailData?.write(to: thumbnailURL, options: .atomic)

        return (imageURL.path, thumbnailData == nil ? nil : thumbnailURL.path, Int64(png.count))
    }

    private func openDatabase() {
        sqlite3_open(databaseURL.path, &db)
    }

    private func migrate() {
        let sql = """
        PRAGMA journal_mode = WAL;
        CREATE TABLE IF NOT EXISTS clips (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            created_at REAL NOT NULL,
            text TEXT,
            image_path TEXT,
            thumbnail_path TEXT,
            file_paths TEXT NOT NULL DEFAULT '',
            file_names TEXT NOT NULL DEFAULT '',
            byte_count INTEGER NOT NULL DEFAULT 0,
            hash TEXT NOT NULL UNIQUE
        );
        CREATE INDEX IF NOT EXISTS clips_created_at_idx ON clips(created_at DESC);
        CREATE INDEX IF NOT EXISTS clips_kind_idx ON clips(kind);
        """
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    private func recordsOlderThan(cutoff: TimeInterval) -> [ClipboardRecord] {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, """
        SELECT id, kind, created_at, text, image_path, thumbnail_path, file_paths, file_names, byte_count, hash
        FROM clips WHERE created_at < ?;
        """, -1, &statement, nil)
        sqlite3_bind_double(statement, 1, cutoff)
        defer { sqlite3_finalize(statement) }

        var records: [ClipboardRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            if let record = ClipboardRecord(statement: statement) {
                records.append(record)
            }
        }
        return records
    }

    private func removeAssets(for record: ClipboardRecord) {
        [record.imagePath, record.thumbnailPath].compactMap { $0 }.forEach {
            try? FileManager.default.removeItem(atPath: $0)
        }
    }

    private func removeDirectoryContents(_ url: URL) {
        guard let contents = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else { return }
        for item in contents {
            try? FileManager.default.removeItem(at: item)
        }
    }
}

struct CapturedClipboardItem {
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
}

private extension ClipboardRecord {
    init?(statement: OpaquePointer?) {
        guard let idString = sqlite3_column_text(statement, 0).map({ String(cString: $0) }),
              let id = UUID(uuidString: idString),
              let kindString = sqlite3_column_text(statement, 1).map({ String(cString: $0) }),
              let kind = ClipboardKind(rawValue: kindString),
              let hash = sqlite3_column_text(statement, 9).map({ String(cString: $0) }) else {
            return nil
        }

        self.id = id
        self.kind = kind
        self.createdAt = Date(timeIntervalSince1970: sqlite3_column_double(statement, 2))
        self.text = sqlite3_optional_string(statement, 3)
        self.imagePath = sqlite3_optional_string(statement, 4)
        self.thumbnailPath = sqlite3_optional_string(statement, 5)
        self.filePaths = sqlite3_optional_string(statement, 6)?.split(separator: "\n").map(String.init) ?? []
        self.fileNames = sqlite3_optional_string(statement, 7)?.split(separator: "\n").map(String.init) ?? []
        self.byteCount = sqlite3_column_int64(statement, 8)
        self.hash = hash
    }
}

func clipboardHash(parts: [String], data: Data? = nil) -> String {
    var hasher = SHA256()
    for part in parts {
        hasher.update(data: Data(part.utf8))
    }
    if let data {
        hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func sqlite3_optional_string(_ statement: OpaquePointer?, _ index: Int32) -> String? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL,
          let value = sqlite3_column_text(statement, index) else {
        return nil
    }
    return String(cString: value)
}

private func sqlite3_bind_optional_text(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
    if let value {
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    } else {
        sqlite3_bind_null(statement, index)
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private extension NSImage {
    func resized(maxPixelSize: CGFloat) -> NSImage {
        let scale = min(maxPixelSize / max(size.width, size.height), 1)
        let targetSize = NSSize(width: size.width * scale, height: size.height * scale)
        let image = NSImage(size: targetSize)
        image.lockFocus()
        draw(in: NSRect(origin: .zero, size: targetSize), from: .zero, operation: .copy, fraction: 1)
        image.unlockFocus()
        return image
    }

    func pngData() -> Data? {
        guard let tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffRepresentation) else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
