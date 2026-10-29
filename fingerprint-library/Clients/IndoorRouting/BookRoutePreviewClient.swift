import ComposableArchitecture

nonisolated struct BookRoutePreviewClient: Sendable {
    var load: @Sendable (IndoorMap, [IndoorShelfLabel], [BookNavigationStop]) async throws -> BookNavigationSession
}

extension BookRoutePreviewClient: DependencyKey {
    static let liveValue = Self(load: { map, labels, stops in
        try await BookRoutePreviewTestRouteLoader().load(on: map, labels: labels, stops: stops)
    })
    static let testValue = Self(load: { _, _, _ in throw IndoorRoutingError.noRoute })
}

extension DependencyValues {
    var bookRoutePreviewClient: BookRoutePreviewClient {
        get { self[BookRoutePreviewClient.self] }
        set { self[BookRoutePreviewClient.self] = newValue }
    }
}
