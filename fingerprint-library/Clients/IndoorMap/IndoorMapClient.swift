import ComposableArchitecture

/// 지도 파일을 읽는 외부 작업과 TCA 상태 처리를 분리하는 의존성 경계.
///
/// Feature는 구체적인 파일 경로를 알지 않고, 테스트에서는 `load`를 합성 지도 공급으로 교체한다.
nonisolated struct IndoorMapClient: Sendable {
    /// 표시 가능한 지도를 비동기로 반환한다. 파일 누락·잘못된 자료·취소는 오류로 전달한다.
    var load: @Sendable () async throws -> IndoorMap
}

extension IndoorMapClient: DependencyKey {
    /// 실제 앱은 도서관 번들 도면을 사용한다.
    static let liveValue = Self(load: { try await BundledIndoorMapLoader().loadLibrary() })
    /// 테스트가 실제 번들에 의존하지 않도록 지도 공급을 명시적으로 설정하게 한다.
    static let testValue = Self(load: { throw IndoorMapLoadError.missingResource("test map") })
}

extension DependencyValues {
    var indoorMapClient: IndoorMapClient {
        get { self[IndoorMapClient.self] }
        set { self[IndoorMapClient.self] = newValue }
    }
}
