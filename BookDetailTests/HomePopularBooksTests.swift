import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct HomePopularBooksTests {
    @Test("학과 전체 보기에서 소속 목록의 모든 도서를 불러오고 홈 미리보기는 유지한다")
    func loadsAllDepartmentBooksSeparatelyFromPreview() async throws {
        let affiliationKey = ["POSTECH 대학원", "일반대학원 학과", "수학과"]
        let departmentBooks = (0..<21).map { Self.book("department-\($0)") }
        let previewBooks = [departmentBooks[0], Self.book("related")]
        let profile = try UserProfile(affiliationKey: affiliationKey, departmentName: "수학과", interests: ["수학"])
        var initialState = HomeFeature.State()
        initialState.$userProfile.withLock { $0 = profile }
        initialState.displayedProfile = profile
        initialState.popularBooks = previewBooks
        let store = TestStore(initialState: initialState) { HomeFeature() } withDependencies: {
            $0.departmentPopularBooksClient.fetchAll = { key in
                #expect(key == affiliationKey)
                return departmentBooks
            }
        }

        await store.send(.departmentRecommendationsRequested)
        await store.receive(\.departmentRecommendationsLoaded) {
            $0.departmentRecommendations = .loaded(departmentBooks)
        }
        #expect(store.state.departmentName == "수학과")
        #expect(store.state.popularBooks == previewBooks)
        #expect(store.state.booksForLibraryInfo == previewBooks + departmentBooks.dropFirst())
        await store.finish()
    }

    @Test("추천 목록이 이미 있어도 하단 도서를 조회하고 프로필의 소속 경로를 전달한다")
    func loadsPopularBooksWithRecommendationsCached() async throws {
        let recommended = Self.book("recommended")
        let popular = Self.book("popular")
        let profile = try UserProfile(
            affiliationKey: ["POSTECH 학부", "학과 및 학부", "컴퓨터공학과"],
            departmentName: "컴퓨터공학과", interests: ["수학"]
        )
        var initialState = HomeFeature.State()
        initialState.$userProfile.withLock { $0 = profile }
        initialState.recommendedBooks = [recommended]
        let store = TestStore(initialState: initialState) { HomeFeature() }
            withDependencies: {
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

        await store.send(.task) { $0.displayedProfile = profile }
        await store.receive(\.popularBooksLoaded) { $0.popularBooks = [popular] }
        #expect(store.state.departmentName == "컴퓨터공학과")
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

    // ✅ 이슈 #237 (Q4)
    @Test("온보딩 직후 첫 표시에는 학과별 추천을 최초 접속으로 조회한다")
    func passesInitialFlagAfterOnboarding() async throws {
        let popular = Self.book("popular")
        let profile = try UserProfile(
            affiliationKey: ["POSTECH 대학원", "일반대학원 학과", "수학과"], departmentName: "수학과", interests: ["수학"]
        )
        var initialState = HomeFeature.State()
        initialState.$userProfile.withLock { $0 = profile }
        initialState.recommendedBooks = [Self.book("recommended")]
        initialState.isFirstVisitAfterOnboarding = true
        let store = TestStore(initialState: initialState) { HomeFeature() }
            withDependencies: {
                $0.departmentPopularBooksClient.fetch = { key, _, isInitial in
                    #expect(key == ["POSTECH 대학원", "일반대학원 학과", "수학과"])
                    #expect(isInitial)
                    return [popular]
                }
            }

        await store.send(.task) { $0.displayedProfile = profile }
        await store.receive(\.popularBooksLoaded) { $0.popularBooks = [popular] }
        await store.finish()
    }

    @Test("마이페이지에서 소속을 바꾸면 홈 제목이 바로 바뀌고, 다음 표시에서 학과 추천을 새 소속으로 다시 불러온다")
    func reloadsDepartmentBooksAfterAffiliationChange() async throws {
        let math = try UserProfile(
            affiliationKey: ["POSTECH 학부", "학과 및 학부", "수학과"], departmentName: "수학과", interests: ["수학"]
        )
        let ai = try math.updatingAffiliation(
            key: ["POSTECH 대학원", "독립 대학원 및 학부", "인공지능대학원"], departmentName: "인공지능대학원"
        )
        let oldBook = Self.book("math")
        let newBook = Self.book("ai")
        let recommended = Self.book("recommended")
        var initialState = HomeFeature.State()
        initialState.$userProfile.withLock { $0 = math }
        initialState.displayedProfile = math
        initialState.recommendedBooks = [recommended]
        initialState.popularBooks = [oldBook]
        initialState.departmentRecommendations = .loaded([oldBook])
        let store = TestStore(initialState: initialState) { HomeFeature() }
            withDependencies: {
                $0.departmentPopularBooksClient.fetch = { key, _, _ in
                    #expect(key == ai.affiliationKey)
                    return [newBook]
                }
                $0.departmentPopularBooksClient.fetchAll = { key in
                    #expect(key == ai.affiliationKey)
                    return [newBook]
                }
            }

        @Shared(.userProfile) var userProfile: UserProfile?
        $userProfile.withLock { $0 = ai }
        // 마이페이지(다른 화면)에서 같은 프로필을 바꾼 상황
        #expect(store.state.departmentName == "인공지능대학원")
        // 제목은 따로 복사해 두지 않으므로 바로 바뀐다.

        await store.send(.task) {
            $0.displayedProfile = ai
            $0.popularBooks = []
            $0.departmentRecommendations = .loading
        }
        await store.receive(\.popularBooksLoaded) { $0.popularBooks = [newBook] }
        await store.send(.departmentRecommendationsRequested)
        await store.receive(\.departmentRecommendationsLoaded) { $0.departmentRecommendations = .loaded([newBook]) }
        #expect(store.state.recommendedBooks == [recommended])
        // 관심 분야는 그대로이므로 '당신을 위한 추천'은 다시 받지 않는다.
        await store.finish()
    }

    @Test("마이페이지에서 관심 분야를 바꾸면 저장해 둔 추천을 꺼내지 않고 새 관심 분야로 다시 받는다")
    func refreshesRecommendationsAfterInterestsChange() async throws {
        let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000330")!
        let before = try UserProfile(
            affiliationKey: ["POSTECH 학부", "학과 및 학부", "수학과"], departmentName: "수학과", interests: ["수학"]
        )
        let after = try before.updatingInterests(["역사"])
        let oldRecommended = Self.book("math-pick")
        let newRecommended = Self.book("history-pick")
        let popular = Self.book("popular")
        var initialState = HomeFeature.State()
        initialState.$userProfile.withLock { $0 = before }
        initialState.displayedProfile = before
        initialState.recommendedBooks = [oldRecommended]
        initialState.popularBooks = [popular]
        let store = TestStore(initialState: initialState) { HomeFeature() }
            withDependencies: {
                $0.uuid = .constant(sessionID)
                $0.bookRecommendationClient.fetch = { _ in [newRecommended] }
                $0.homeRecommendationForYouClient = .live(
                    recommendation: $0.bookRecommendationClient, cache: $0.recommendationCacheClient
                )
                $0.departmentPopularBooksClient.fetch = { _, _, _ in
                    Issue.record("소속이 그대로면 학과 추천을 다시 받지 않습니다.")
                    return []
                }
            }

        @Shared(.userProfile) var userProfile: UserProfile?
        $userProfile.withLock { $0 = after }

        await store.send(.task) {
            $0.displayedProfile = after
            $0.recommendedBooks = []
            $0.recommendationSessionID = sessionID
            $0.isLoadingRecommendations = true
            $0.isPreparingRecommendations = true
        }
        await store.receive(\.recommendationsLoaded) {
            $0.recommendedBooks = [newRecommended]
            $0.isLoadingRecommendations = false
            $0.isPreparingRecommendations = false
            $0.nextRecommendationsSavedAt = .distantPast
        }
        // recommendationsRestored(저장본 꺼내기)를 거치지 않는다.
        #expect(store.state.popularBooks == [popular])
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
