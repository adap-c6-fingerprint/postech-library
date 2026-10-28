import ComposableArchitecture

/// 서가 레이블은 길찾기 노드 로딩과 독립적으로 준비한다.
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

extension DependencyValues {
    var indoorShelfLabelClient: IndoorShelfLabelClient {
        get { self[IndoorShelfLabelClient.self] }
        set { self[IndoorShelfLabelClient.self] = newValue }
    }
}
