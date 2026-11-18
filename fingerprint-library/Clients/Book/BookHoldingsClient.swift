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

    #if DEMO
    static let liveValue = Self.demoFallback(recorded: networkValue)
    #else
    static let liveValue = networkValue
    #endif

    /// 오프라인 시연: 녹화한 소장 응답(대출 상태 포함)을 우선하고, 없으면 번들 데이터셋의 소장처·청구기호를 쓴다.
    static func demoFallback(
        recorded: BookHoldingsClient,
        catalog: @escaping @Sendable () async throws -> DemoCatalog = { try await DemoCatalogLoader.shared.load() }
    ) -> Self {
        Self(fetch: { recordID in
            do {
                return try await recorded.fetch(recordID)
            } catch is DemoFixtureMissError {
                guard let holdings = try await catalog().holdings(recordID: recordID) else {
                    throw DemoFixtureMissError()
                }
                return holdings
            }
        })
    }

    private static let networkValue = Self(fetch: { recordID in
        @Dependency(\.httpClient) var httpClient
        var relay = BookAPIClient(httpClient: httpClient)
        let configuration = try AppConfiguration.relayConfiguration()
        relay.configuration = { configuration }
        let namespace = configuration.environment.baseURL.absoluteString
        let service = PrimoBookHoldingsService(relay: relay)
        let holdings = try await cache.holdings(for: namespace + "|" + recordID) {
            try await service.fetch(recordID: recordID)
        }
        try Task.checkCancellation()
        return holdings
    })

    static let testValue = Self(fetch: { _ in [] })
}

nonisolated extension DependencyValues {
    var bookHoldingsClient: BookHoldingsClient {
        get { self[BookHoldingsClient.self] }
        set { self[BookHoldingsClient.self] = newValue }
    }
}
