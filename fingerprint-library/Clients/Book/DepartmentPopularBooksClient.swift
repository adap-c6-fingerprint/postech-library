import ComposableArchitecture

struct DepartmentPopularBooksClient: Sendable {
    var fetch: @Sendable (_ departmentName: String, _ count: Int) async throws -> [Book]
}

extension DepartmentPopularBooksClient: DependencyKey {
    static let liveValue: Self = .random

    // 학과별 대출 통계가 준비되기 전에는 검색 결과에서 임시 도서를 고른다.
    // 통계 조회를 구현하면 liveValue가 선택하는 구현을 교체한다.
    static let random = Self(
        fetch: { _, count in
            guard count > 0 else { return [] }

            let bookClient = await MainActor.run {
                @Dependency(\.bookClient) var bookClient
                return bookClient
            }

            let keywords = ["소설", "과학", "역사", "예술"]
            let keyword = keywords.randomElement() ?? "소설"
            let books = try await bookClient.search(keyword)

            return Array(books.shuffled().prefix(count))
        }
    )

    static let testValue = Self(fetch: { _, _ in [] })
}

extension DependencyValues {
    var departmentPopularBooksClient: DepartmentPopularBooksClient {
        get { self[DepartmentPopularBooksClient.self] }
        set { self[DepartmentPopularBooksClient.self] = newValue }
    }
}
