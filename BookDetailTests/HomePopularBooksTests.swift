import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct HomePopularBooksTests {
    @Test("학과 전체 보기에서 소속 목록의 모든 도서를 불러오고 홈 미리보기는 유지한다")
    func loadsAllDepartmentBooksSeparatelyFromPreview() async {
        let affiliationKey = ["POSTECH 대학원", "일반대학원 학과", "수학과"]
        let departmentBooks = (0..<21).map { Self.book("department-\($0)") }
        let previewBooks = [departmentBooks[0], Self.book("related")]
        var initialState = HomeFeature.State()
        initialState.popularBooks = previewBooks
        let store = TestStore(initialState: initialState) { HomeFeature() } withDependencies: {
            $0.userProfileClient.load = {
                .init(departmentName: "수학과", interests: [], affiliationKey: affiliationKey)
            }
            $0.departmentPopularBooksClient.fetchAll = { key in
                #expect(key == affiliationKey)
                return departmentBooks
            }
        }

        await store.send(.departmentRecommendationsRequested)
        await store.receive(\.departmentRecommendationsLoaded) {
            $0.departmentRecommendations = .loaded(departmentName: "수학과", books: departmentBooks)
        }
        #expect(store.state.popularBooks == previewBooks)
        #expect(store.state.booksForLibraryInfo == previewBooks + departmentBooks.dropFirst())
        await store.finish()
    }

    @Test("추천 목록이 이미 있어도 하단 도서를 조회하고 프로필의 소속 경로를 전달한다")
    func loadsPopularBooksWithRecommendationsCached() async {
        let recommended = Self.book("recommended")
        let popular = Self.book("popular")
        var initialState = HomeFeature.State()
        initialState.recommendedBooks = [recommended]
        let store = TestStore(initialState: initialState) { HomeFeature() }
            withDependencies: {
                $0.userProfileClient.load = {
                    UserProfileSnapshot(
                        departmentName: "컴퓨터공학과", interests: [],
                        affiliationKey: ["POSTECH 학부", "학과 및 학부", "컴퓨터공학과"]
                    )
                    // ✅ 소속 경로를 함께 저장한다.
                }
                $0.bookRecommendationClient.fetch = { _ in
                    Issue.record("이미 있는 추천 목록을 다시 조회하면 안 됩니다.")
                    return []
                }
                $0.departmentPopularBooksClient.fetch = { key, count, isInitial in
                    #expect(key == ["POSTECH 학부", "학과 및 학부", "컴퓨터공학과"])
                    #expect(count == 6)
                    #expect(isInitial == false)
                    // ✅ 학과 이름 대신 소속 경로와 최초 표시 여부를 전달한다.
                    return [popular]
                }
                $0.homeRecommendationForYouClient = .live(
                    recommendation: $0.bookRecommendationClient, cache: $0.recommendationCacheClient
                )
            }

        await store.send(.task)
        await store.receive(\.departmentChanged) { $0.departmentName = "컴퓨터공학과" }
        await store.receive(\.popularBooksLoaded) { $0.popularBooks = [popular] }
        #expect(store.state.recommendedBooks == [recommended])
        await store.finish()
    }

    @Test("하단 목록이 이미 있으면 위쪽 추천만 조회한다")
    func loadsRecommendationsWithPopularBooksCached() async {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let recommended = Self.book("recommended")
        let popular = Self.book("popular")
        var initialState = HomeFeature.State()
        initialState.popularBooks = [popular]
        let store = TestStore(initialState: initialState) { HomeFeature() }
            withDependencies: {
                $0.uuid = .constant(sessionID)
                $0.bookRecommendationClient.fetch = { count in
                    #expect(count == 6)
                    return [recommended]
                }
                $0.departmentPopularBooksClient.fetch = { _, _, _ in
                    Issue.record("이미 있는 하단 목록을 다시 조회하면 안 됩니다.")
                    return []
                }
                $0.homeRecommendationForYouClient = .live(
                    recommendation: $0.bookRecommendationClient, cache: $0.recommendationCacheClient
                )
            }

        await store.send(.task)
        await store.receive(\.recommendationSessionStarted) {
            $0.recommendationSessionID = sessionID
            $0.isLoadingRecommendations = true
            $0.isPreparingRecommendations = true
        }
        await store.receive(\.recommendationsRestored)
        await store.receive(\.recommendationsLoaded) {
            $0.recommendedBooks = [recommended]
            $0.isLoadingRecommendations = false
            $0.isPreparingRecommendations = false
            $0.nextRecommendationsSavedAt = .distantPast
        }
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
                $0.departmentPopularBooksClient.fetch = { _, _, _ in try await stub.fetch() }
                $0.homeRecommendationForYouClient = .live(
                    recommendation: $0.bookRecommendationClient, cache: $0.recommendationCacheClient
                )
            }

        await store.send(.task)
        await store.receive(\.departmentChanged)
        await store.receive(\.popularBooksFailed) {
            $0.popularBooksErrorMessage = URLError(.notConnectedToInternet).localizedDescription
        }
        #expect(store.state.recommendedBooks == [recommended])
        #expect(store.state.recommendationErrorMessage == nil)

        await store.send(.task) { $0.popularBooksErrorMessage = nil }
        await store.receive(\.departmentChanged)
        await store.receive(\.popularBooksLoaded) { $0.popularBooks = [popular] }
        await store.finish()

        // 두 목록이 채워진 후에는 다시 요청하지 않는다.
        await store.send(.task)
        #expect(await stub.requestCount == 2)
        #expect(store.state.recommendedBooks == [recommended])
        await store.finish()
    }

    // ✅ 이슈 #237 (Q4)
    @Test("온보딩 직후 첫 표시에는 학과별 추천을 최초 접속으로 조회한다")
    func passesInitialFlagAfterOnboarding() async {
        let popular = Self.book("popular")
        var initialState = HomeFeature.State()
        initialState.recommendedBooks = [Self.book("recommended")]
        initialState.isFirstVisitAfterOnboarding = true
        let store = TestStore(initialState: initialState) { HomeFeature() }
            withDependencies: {
                $0.userProfileClient.load = {
                    UserProfileSnapshot(
                        departmentName: "수학과", interests: ["수학"],
                        affiliationKey: ["POSTECH 대학원", "일반대학원 학과", "수학과"]
                    )
                }
                $0.departmentPopularBooksClient.fetch = { key, _, isInitial in
                    #expect(key == ["POSTECH 대학원", "일반대학원 학과", "수학과"])
                    #expect(isInitial)
                    return [popular]
                }
            }

        await store.send(.task)
        await store.receive(\.departmentChanged) { $0.departmentName = "수학과" }
        await store.receive(\.popularBooksLoaded) { $0.popularBooks = [popular] }
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
