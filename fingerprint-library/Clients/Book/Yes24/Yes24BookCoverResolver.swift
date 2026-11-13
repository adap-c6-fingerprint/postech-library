import Foundation

actor Yes24BookCoverResolver {
    private struct Cached {
        let url: URL?
        let expiresAt: Date
    }
    private struct Request {
        let id: UUID
        let task: Task<URL?, Error>
    }

    private let fetch: @Sendable (String) async throws -> URL?
    private let now: @Sendable () -> Date
    private let lifetime: TimeInterval
    private var cache: [String: Cached] = [:]
    private var requests: [String: Request] = [:]

    init(lifetime: TimeInterval = 900, now: @escaping @Sendable () -> Date = { Date() },
         fetch: @escaping @Sendable (String) async throws -> URL?) {
        self.fetch = fetch
        self.now = now
        self.lifetime = lifetime
    }

    func url(for isbn: String) async throws -> URL? {
        try Task.checkCancellation()
        guard let isbn13 = BookISBN.isbn13(from: isbn) else { return nil }
        if let cached = cache[isbn13], cached.expiresAt > now() { return cached.url }
        if let request = requests[isbn13] {
            let value = try await request.task.value
            try Task.checkCancellation()
            return value
        }
        let id = UUID()
        let task = Task { try await fetch(isbn13) }
        requests[isbn13] = Request(id: id, task: task)
        do {
            let url = try await task.value
            if requests[isbn13]?.id == id {
                requests[isbn13] = nil
                cache = cache.filter { $0.value.expiresAt > now() }
                if cache.count >= 100, let oldest = cache.min(by: { $0.value.expiresAt < $1.value.expiresAt })?.key {
                    cache[oldest] = nil
                }
                cache[isbn13] = Cached(url: url, expiresAt: now().addingTimeInterval(lifetime))
            }
            try Task.checkCancellation()
            return url
        } catch {
            if requests[isbn13]?.id == id { requests[isbn13] = nil }
            throw error
        }
    }
}
