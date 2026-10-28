import Foundation
import Synchronization

/// 현재 BookClient의 검색 조건은 검색어 외에 모두 고정되어 있다.
/// 범위·필터·정렬·페이지가 가변 값이 되면 캐시 키에도 반드시 포함한다.
nonisolated final class BookSearchResultCache: Sendable {
    private struct Entry: Sendable {
        let books: [Book]
        let expiresAt: Date
    }

    private struct Storage: Sendable {
        var entries: [String: Entry] = [:]
        var recentKeys: [String] = []

        mutating func remove(_ key: String) {
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

    func load(_ query: String) -> [Book]? {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let date = now()
        return storage.withLock { storage in
            storage.removeExpired(at: date)
            guard let entry = storage.entries[key] else { return nil }
            storage.recentKeys.removeAll { $0 == key }
            storage.recentKeys.append(key)
            return entry.books
        }
    }

    func save(_ books: [Book], for query: String) {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return }
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

    func remove(_ query: String) {
        let key = query.trimmingCharacters(in: .whitespacesAndNewlines)
        storage.withLock { $0.remove(key) }
    }
}
