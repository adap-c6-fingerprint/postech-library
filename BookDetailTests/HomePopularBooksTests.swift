import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct HomePopularBooksTests {
    @Test("추천 목록이 이미 있어도 하단 도서를 조회하고 학과명을 전달한다")
    func loadsPopularBooksWithRecommendationsCached() async {
        let recommended = Self.book("recommended")
        let popular = Self.book("popular")
        var initialState = HomeFeature.State()
        initialState.recommendedBooks = [recommended]
        initialState.departmentName = "컴퓨터공학과"
        let store = TestStore(initialState: initialState) { HomeFeature() }
            withDependencies: {
                $0.bookRecommendationClient.fetch = { _ in
                    Issue.record("이미 있는 추천 목록을 다시 조회하면 안 됩니다.")
                    return []
                }
                $0.departmentPopularBooksClient.fetch = { department, count in
                    #expect(department == "컴퓨터공학과")
                    #expect(count == 6)
                    return [popular]
                }
            }

        await store.send(.task)
        await store.receive(\.popularBooksLoaded) { $0.popularBooks = [popular] }
        #expect(store.state.recommendedBooks == [recommended])
        await store.finish()
    }

    @Test("하단 목록이 이미 있으면 위쪽 추천만 조회한다")
    func loadsRecommendationsWithPopularBooksCached() async {
        let recommended = Self.book("recommended")
        let popular = Self.book("popular")
        var initialState = HomeFeature.State()
        initialState.popularBooks = [popular]
        let store = TestStore(initialState: initialState) { HomeFeature() }
            withDependencies: {
                $0.bookRecommendationClient.fetch = { count in
                    #expect(count == 6)
                    return [recommended]
                }
                $0.departmentPopularBooksClient.fetch = { _, _ in
                    Issue.record("이미 있는 하단 목록을 다시 조회하면 안 됩니다.")
                    return []
                }
            }

        await store.send(.task)
        await store.receive(\.recommendationsLoaded) { $0.recommendedBooks = [recommended] }
        #expect(store.state.popularBooks == [popular])
        await store.finish()
    }

    @Test("하단 조회 실패를 분리해 보존하고 다음 진입에서 다시 조회한다")
    func retriesPopularBooksWithoutReplacingRecommendations() async {
        let recommended = Self.book("recommended")
        let popular = Self.book("popular")
        let stub = PopularBooksStub(book: popular)
        var initialState = HomeFeature.State()
        initialState.recommendedBooks = [recommended]
        let store = TestStore(initialState: initialState) { HomeFeature() }
            withDependencies: {
                $0.bookRecommendationClient.fetch = { _ in
                    Issue.record("추천 목록은 보존해야 합니다.")
                    return []
                }
                $0.departmentPopularBooksClient.fetch = { _, _ in try await stub.fetch() }
            }

        await store.send(.task)
        await store.receive(\.popularBooksFailed) {
            $0.popularBooksErrorMessage = URLError(.notConnectedToInternet).localizedDescription
        }
        #expect(store.state.recommendedBooks == [recommended])
        #expect(store.state.recommendationErrorMessage == nil)

        await store.send(.task) { $0.popularBooksErrorMessage = nil }
        await store.receive(\.popularBooksLoaded) { $0.popularBooks = [popular] }
        await store.finish()

        // 두 목록이 채워진 후에는 다시 요청하지 않는다.
        await store.send(.task)
        #expect(await stub.requestCount == 2)
        #expect(store.state.recommendedBooks == [recommended])
        await store.finish()
    }

    private static func book(_ id: String) -> Book {
        Book(
            id: id, isbn: nil, controlNumber: id, title: id,
            author: "저자", publisher: nil, publicationYear: nil,
            description: nil, imageURL: nil
        )
    }
}

private actor PopularBooksStub {
    private(set) var requestCount = 0
    let book: Book

    init(book: Book) { self.book = book }

    func fetch() throws -> [Book] {
        requestCount += 1
        if requestCount == 1 { throw URLError(.notConnectedToInternet) }
        return [book]
    }
}
