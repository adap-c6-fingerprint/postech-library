import ComposableArchitecture

nonisolated struct DepartmentPopularBooksClient: Sendable {
    /// 번들 데이터셋에서 바로 고른 목록이다. 네트워크를 기다리지 않아 첫 화면에 즉시 표시할 수 있다.
    var fetch: @Sendable (_ affiliationKey: [String], _ count: Int) async throws -> [Book]

    /// 다음 묶음을 준비한다. 연관도서 조회·소장 확인을 거치므로 화면 표시 전 미리 호출한다.
    var prepareReplacement: @Sendable (
        _ affiliationKey: [String], _ count: Int, _ excludedKeys: Set<String>
    ) async throws -> [Book]

    var fetchAll: @Sendable (_ affiliationKey: [String]) async throws -> [Book]
}

extension DepartmentPopularBooksClient: DependencyKey {
    static let liveValue: Self = .dataset(dataset: .liveValue, related: .liveValue)

    static let testValue = Self(
        fetch: { _, _ in [] },
        prepareReplacement: { _, _, _ in [] },
        fetchAll: { _ in [] }
    )
}

nonisolated extension DependencyValues {
    var departmentPopularBooksClient: DepartmentPopularBooksClient {
        get { self[DepartmentPopularBooksClient.self] }
        set { self[DepartmentPopularBooksClient.self] = newValue }
    }
}
