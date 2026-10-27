import ComposableArchitecture

/// 화면 지도에 맞는 길찾기 자료를 공급하는 TCA 의존성 경계.
///
/// 파일 해석은 로더가 맡고, Feature는 성공 결과와 준비 전·실패 상태만 처리한다.
nonisolated struct IndoorNavigationClient: Sendable {
    /// 전달한 지도와 일치하는 navigation 자료를 반환한다. 준비되지 않았거나 검증에 실패하면 오류를 전달한다.
    var load: @Sendable (IndoorMap) async throws -> IndoorNavigationData
}

extension IndoorNavigationClient: DependencyKey {
    /// 도서관 자료만 읽으며 기존 개발 건물의 자료로 자동 대체하지 않는다.
    static let liveValue = Self(load: { try await BundledIndoorNavigationLoader().loadLibrary(on: $0) })
    /// 테스트에서 실제 파일 대신 필요한 결과·실패를 명시적으로 공급할 수 있게 한다.
    static let testValue = Self(load: { _ in throw IndoorMapLoadError.missingResource("test routing") })
}

extension DependencyValues {
    var indoorNavigationClient: IndoorNavigationClient {
        get { self[IndoorNavigationClient.self] }
        set { self[IndoorNavigationClient.self] = newValue }
    }
}
