import ComposableArchitecture

nonisolated struct IndoorShelfLabelClient: Sendable {
    var supports: @Sendable (IndoorMap) -> Bool
    var load: @Sendable (IndoorMap) async throws -> [IndoorShelfLabel]
}

extension IndoorShelfLabelClient: DependencyKey {
    static let liveValue = Self(
        supports: { $0.venue.sourceID == BundledShelfLabelLoader.libraryVenueID },
        load: { try await BundledShelfLabelLoader().loadLibrary(on: $0) }
    )
    static let testValue = Self(supports: { _ in false }, load: { _ in [] })
}

nonisolated extension DependencyValues {
    var indoorShelfLabelClient: IndoorShelfLabelClient {
        get { self[IndoorShelfLabelClient.self] }
        set { self[IndoorShelfLabelClient.self] = newValue }
    }
}
