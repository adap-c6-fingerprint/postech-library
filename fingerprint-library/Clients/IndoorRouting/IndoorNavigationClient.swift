import ComposableArchitecture

nonisolated struct IndoorNavigationClient: Sendable {
    var load: @Sendable (IndoorMap) async throws -> IndoorNavigationData
}

extension IndoorNavigationClient: DependencyKey {
    static let liveValue = Self(load: { try await BundledIndoorNavigationLoader().loadC5(on: $0) })
    static let testValue = Self(load: { _ in throw IndoorMapLoadError.missingResource("test routing") })
}

extension DependencyValues {
    var indoorNavigationClient: IndoorNavigationClient {
        get { self[IndoorNavigationClient.self] }
        set { self[IndoorNavigationClient.self] = newValue }
    }
}
