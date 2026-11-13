import ComposableArchitecture

nonisolated struct DepartmentPopularBooksClient: Sendable {
    var fetch: @Sendable (_ affiliationKey: [String], _ count: Int, _ isInitial: Bool) async throws -> [Book]

    var fetchAll: @Sendable (_ affiliationKey: [String]) async throws -> [Book]
}

extension DepartmentPopularBooksClient: DependencyKey {
    static let liveValue: Self = .dataset(dataset: .liveValue, related: .liveValue)

    static let testValue = Self(fetch: { _, _, _ in [] }, fetchAll: { _ in [] })
}

nonisolated extension DependencyValues {
    var departmentPopularBooksClient: DepartmentPopularBooksClient {
        get { self[DepartmentPopularBooksClient.self] }
        set { self[DepartmentPopularBooksClient.self] = newValue }
    }
}
