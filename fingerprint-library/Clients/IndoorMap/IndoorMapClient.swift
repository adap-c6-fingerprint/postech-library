import ComposableArchitecture

nonisolated struct IndoorMapClient: Sendable {
    var load: @Sendable () async throws -> IndoorMap
}

extension IndoorMapClient: DependencyKey {
    static let liveValue = Self(load: { try await BundledIndoorMapLoader().loadC5() })
    static let testValue = Self(load: { throw IndoorMapLoadError.missingResource("test map") })
}

extension DependencyValues {
    var indoorMapClient: IndoorMapClient {
        get { self[IndoorMapClient.self] }
        set { self[IndoorMapClient.self] = newValue }
    }
}
