import Foundation

final class RetentionService {
    private let storage: StorageService

    init(storage: StorageService) {
        self.storage = storage
    }

    func cleanup(olderThanDays days: Int) {
        storage.deleteOlderThan(days: days)
    }
}
