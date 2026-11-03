import ComposableArchitecture

struct DepartmentPopularBooksClient: Sendable {
    var fetch: @Sendable (_ affiliationKey: [String], _ count: Int, _ isInitial: Bool) async throws -> [Book]
    // ✅ 학과 이름 대신 소속 경로(상위·그룹·최종)를 받는다. 이름만으로는 학부·대학원의 같은 학과가 섞인다.
    // ✅ isInitial: 온보딩 직후 첫 표시이면 true. 하드데이터만 쓰고 네트워크를 거치지 않는다.

    /// 소속에 매핑된 전체 추천 도서를 원본 순서로 반환한다.
    var fetchAll: @Sendable (_ affiliationKey: [String]) async throws -> [Book]
}

extension DepartmentPopularBooksClient: DependencyKey {
    static let liveValue: Self = .dataset(dataset: .liveValue, related: .liveValue)
    // ✅ 키워드 검색 후 임시 랜덤(.random) 대신 소속별 하드데이터를 쓴다. (DatasetRecommendationClients.swift)

    static let testValue = Self(fetch: { _, _, _ in [] }, fetchAll: { _ in [] })
}

extension DependencyValues {
    var departmentPopularBooksClient: DepartmentPopularBooksClient {
        get { self[DepartmentPopularBooksClient.self] }
        set { self[DepartmentPopularBooksClient.self] = newValue }
    }
}
