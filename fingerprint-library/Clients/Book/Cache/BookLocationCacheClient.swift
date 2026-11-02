import ComposableArchitecture
import Foundation

/// 일반 검색·상세에서 이미 받은 소장 정보의 로컬 사본. 네트워크 의존성은 없다.
nonisolated struct BookLocationCacheClient: Sendable {
    var load: @Sendable (_ keys: Set<[String?]>) -> [[String?]: [BookHolding]]
    var record: @Sendable (_ book: Book, _ holdings: [BookHolding]) -> Void
    var updates: @Sendable () -> AsyncStream<Void>
    var prepare: @Sendable () async -> Void = {}
    var recordBatch: (@Sendable ([(Book, [BookHolding])]) -> Void)? = nil

    static func userDefaults(suiteName: String? = nil) -> Self {
        let store = LocalBookLocationStore(suiteName: suiteName)
        let bundled = BundledBookLocationLoader()
        return Self(load: { store.load($0) }, record: { store.record($0, holdings: $1) }, updates: { store.updates() }, prepare: {
            guard let entries = try? await bundled.load(), !Task.isCancelled else { return }
            store.seed(entries)
        }, recordBatch: { store.recordBatch($0) })
    }

    func recordSearchResponse(_ data: Data, books: [Book]) {
        guard let decoded = try? PrimoHoldingsMapper.decodeAll(data) else { return }
        let entries = books.compactMap { book -> (Book, [BookHolding])? in
            guard let id = BookHoldingsClient.recordID(for: book), let holdings = decoded[id] else { return nil }
            return (book, holdings)
        }
        guard !entries.isEmpty else { return }
        if let recordBatch {
            recordBatch(entries)
        } else {
            for (book, holdings) in entries { record(book, holdings) }
        }
    }
}

extension BookLocationCacheClient: DependencyKey {
    static let liveValue = Self.userDefaults()
    static let testValue = Self(load: { _ in [:] }, record: { _, _ in }, updates: {
        AsyncStream { $0.yield(()); $0.finish() }
    })
}

extension DependencyValues {
    var bookLocationCacheClient: BookLocationCacheClient {
        get { self[BookLocationCacheClient.self] }
        set { self[BookLocationCacheClient.self] = newValue }
    }
}

/// 저장과 구독 목록은 같은 lock으로 보호하며, 변경 알림은 lock 밖에서 전달한다.
private nonisolated final class LocalBookLocationStore: @unchecked Sendable {
    private struct Entry: Codable, Equatable {
        let key: [String?]
        let isbn: String?
        let holdings: [BookHolding]
    }

    private static let storageKey = "bookLocationSnapshots.v1"
    private let lock = NSLock()
    private let defaults: UserDefaults
    private var entries: [[String?]: Entry] = [:]
    private var observers: [UUID: AsyncStream<Void>.Continuation] = [:]
    private var hasSeededBundle = false

    init(suiteName: String?) {
        defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        if let data = defaults.data(forKey: Self.storageKey),
           let saved = try? JSONDecoder().decode([Entry].self, from: data) {
            for entry in saved { entries[entry.key] = entry }
        }
    }

    func load(_ keys: Set<[String?]>) -> [[String?]: [BookHolding]] {
        lock.withLock {
            var result: [[String?]: [BookHolding]] = [:]
            for key in keys {
                if let exact = entries[Self.normalized(key)] {
                    result[key] = exact.holdings
                } else if key.count > 1, key[0] == "metadata", let isbn = BookISBN.isbn13(from: key[1]) {
                    // 이미 로컬에 있는 같은 ISBN의 자료만 연결한다. 검색 API로 보충하지 않는다.
                    let matches = entries.values.filter { $0.isbn == isbn }
                    if !matches.isEmpty {
                        var seen = Set<String>()
                        result[key] = matches.flatMap(\.holdings).filter { seen.insert($0.id).inserted }
                    }
                }
            }
            return result
        }
    }

    func record(_ book: Book, holdings: [BookHolding]) {
        recordBatch([(book, holdings)])
    }

    /// 검색 한 번의 변경을 모두 반영한 뒤 전체 저장과 변경 알림을 한 번만 수행한다.
    func recordBatch(_ books: [(Book, [BookHolding])]) {
        let updates = books.map { book, holdings in
            Entry(key: Self.normalized(book.recordKey), isbn: BookISBN.isbn13(from: book.isbn), holdings: holdings)
        }
        let listeners = lock.withLock { () -> [AsyncStream<Void>.Continuation] in
            var changed = false
            for entry in updates where entries[entry.key] != entry {
                entries[entry.key] = entry
                changed = true
            }
            guard changed else { return [] }
            if let data = try? JSONEncoder().encode(Array(entries.values)) { defaults.set(data, forKey: Self.storageKey) }
            return Array(observers.values)
        }
        for listener in listeners { listener.yield(()) }
    }

    /// 번들 자료는 기본값이다. 일반 조회로 저장한 최신 사본은 덮어쓰지 않는다.
    func seed(_ books: [(Book, [BookHolding])]) {
        let listeners = lock.withLock { () -> [AsyncStream<Void>.Continuation] in
            guard !hasSeededBundle else { return [] }
            hasSeededBundle = true
            var changed = false
            for (book, holdings) in books {
                let key = Self.normalized(book.recordKey)
                guard entries[key] == nil else { continue }
                entries[key] = Entry(key: key, isbn: BookISBN.isbn13(from: book.isbn), holdings: holdings)
                changed = true
            }
            guard changed else { return [] }
            if let data = try? JSONEncoder().encode(Array(entries.values)) { defaults.set(data, forKey: Self.storageKey) }
            return Array(observers.values)
        }
        for listener in listeners { listener.yield(()) }
    }

    func updates() -> AsyncStream<Void> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let id = UUID()
            lock.withLock { observers[id] = continuation }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                _ = self.lock.withLock { self.observers.removeValue(forKey: id) }
            }
            continuation.yield(())
        }
    }

    private static func normalized(_ key: [String?]) -> [String?] {
        guard key.count == 2, key[0] == "control", let value = key[1] else { return key }
        return ["control", value.hasPrefix("primo:") ? String(value.dropFirst(6)) : value]
    }
}

/// 추천 JSON의 이미 포함된 소장 필드만 읽는다. 파일 읽기·해석은 메인 스레드에서 하지 않는다.
private actor BundledBookLocationLoader {
    private nonisolated struct Dataset: Decodable {
        let books: [Entry]
        nonisolated struct Entry: Decodable {
            let book: RecommendationDatasetDTO.BookDTO
            let holdings: [BookHolding]?
        }
    }
    private var cached: [(Book, [BookHolding])]?

    func load() throws -> [(Book, [BookHolding])] {
        if let cached { return cached }
        guard let url = Bundle.main.url(forResource: "RecommendationDataset", withExtension: "json") else { return [] }
        let data = try JSONDecoder().decode(Dataset.self, from: Data(contentsOf: url))
        let result = data.books.compactMap { entry in entry.holdings.map { (entry.book.book, $0) } }
        cached = result
        return result
    }
}
