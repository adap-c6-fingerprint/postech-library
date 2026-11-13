import Foundation
import Synchronization

nonisolated final class BookSearchResultCache: Sendable {
    private struct Entry: Sendable {
        let books: [Book]
        let expiresAt: Date
    }

    private struct Storage: Sendable {
        var entries: [BookSearchRequest: Entry] = [:]
        var recentKeys: [BookSearchRequest] = []

        mutating func remove(_ key: BookSearchRequest) {
            entries[key] = nil
            recentKeys.removeAll { $0 == key }
        }

        mutating func removeExpired(at now: Date) {
            for key in recentKeys where entries[key].map({ $0.expiresAt <= now }) == true {
                remove(key)
            }
        }
    }

    private let storage = Mutex(Storage())
    private let lifetime: TimeInterval
    private let capacity: Int
    private let now: @Sendable () -> Date

    init(
        lifetime: TimeInterval = 60,
        capacity: Int = 20,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        precondition(lifetime > 0 && capacity > 0)
        self.lifetime = lifetime
        self.capacity = capacity
        self.now = now
    }

    func load(_ key: BookSearchRequest) -> [Book]? {
        let date = now()
        return storage.withLock { storage in
            storage.removeExpired(at: date)
            guard let entry = storage.entries[key] else { return nil }
            storage.recentKeys.removeAll { $0 == key }
            storage.recentKeys.append(key)
            return entry.books
        }
    }

    func save(_ books: [Book], for key: BookSearchRequest) {
        guard !key.query.isEmpty else { return }
        let date = now()
        storage.withLock { storage in
            storage.removeExpired(at: date)
            storage.remove(key)
            while storage.entries.count >= capacity, let oldest = storage.recentKeys.first {
                storage.remove(oldest)
            }
            storage.entries[key] = Entry(books: books, expiresAt: date.addingTimeInterval(lifetime))
            storage.recentKeys.append(key)
        }
    }

    func remove(_ key: BookSearchRequest) {
        storage.withLock { $0.remove(key) }
    }
}
