import ComposableArchitecture
import Foundation

nonisolated struct BookHoldingsClient: Sendable {
    var fetch: @Sendable (_ recordID: String) async throws -> [BookHolding]

    static func recordID(for book: Book) -> String? {
        for value in [book.controlNumber, book.id].compactMap({ $0 }) {
            let recordID = value.hasPrefix("primo:") ? String(value.dropFirst(6)) : value
            if PrimoBookHoldingsService.isValid(recordID: recordID) { return recordID }
        }
        return nil
    }
}

extension BookHoldingsClient: DependencyKey {
    private static let cache = BookHoldingsCache()

    static let liveValue = Self(fetch: { recordID in
        @Dependency(\.httpClient) var httpClient
        let configuration = try await AppConfiguration.relayConfiguration()
        let service = PrimoBookHoldingsService(relay: .init(httpClient: httpClient, configuration: { configuration }))
        let cacheKey = configuration.environment.baseURL.absoluteString + "|" + recordID
        if let holdings = await cache.value(for: cacheKey) { return holdings }
        let holdings = try await service.fetch(recordID: recordID)
        try Task.checkCancellation()
        await cache.insert(holdings, for: cacheKey)
        return holdings
    })

    static let testValue = Self(fetch: { _ in [] })
}

extension DependencyValues {
    var bookHoldingsClient: BookHoldingsClient {
        get { self[BookHoldingsClient.self] }
        set { self[BookHoldingsClient.self] = newValue }
    }
}

private actor BookHoldingsCache {
    private var entries: [String: (expires: Date, holdings: [BookHolding])] = [:]

    func value(for key: String) -> [BookHolding]? {
        guard let entry = entries[key], entry.expires > Date() else {
            entries[key] = nil
            return nil
        }
        return entry.holdings
    }

    func insert(_ holdings: [BookHolding], for key: String) {
        entries = entries.filter { $0.value.expires > Date() }
        if entries.count >= 200, let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key {
            entries[oldest] = nil
        }
        // 카드의 이용 가능 상태를 하루 전 응답으로 표시하지 않도록 짧게 재사용한다.
        entries[key] = (Date().addingTimeInterval(60), holdings)
    }
}
