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
        var relay = BookAPIClient(httpClient: httpClient)
        let configuration = try await AppConfiguration.relayConfiguration()
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
