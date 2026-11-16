import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct HomeRecommendationStreamingTests {
    private let sessionID = UUID(0)

    private func coveredBook(_ number: Int) -> Book {
        makeBook(number).replacingImageURL(URL(string: "https://example.com/cover/\(number).jpg"))
    }

    private func coverFile(_ number: Int) -> URL {
        URL(fileURLWithPath: "/tmp/covers/\(number).image")
    }

    private func preparingState(showing books: [Book] = [], mode: HomeFeature.RecommendationLoadMode) -> HomeFeature.State {
        var state = HomeFeature.State()
        state.recommendedBooks = books
        state.recommendationSessionID = sessionID
        state.recommendationLoadMode = mode
        state.isLoadingRecommendations = books.isEmpty
        state.isPreparingRecommendations = true
        return state
    }

    @Test func 빈_캐러셀에는_준비된_책부터_왼쪽부터_붙는다() async {
        let store = TestStore(initialState: preparingState(mode: .profileChanged)) { HomeFeature() }
        let first = coveredBook(3)
        let second = coveredBook(1)

        await store.send(.recommendationBookPrepared(sessionID, first, coverFile: coverFile(3))) {
            $0.isStreamingRecommendations = true
            $0.isLoadingRecommendations = false
            $0.recommendedBooks = [first]
            $0.recommendationCoverFiles = [first.id: self.coverFile(3)]
        }
        #expect(store.state.recommendationCount == DatasetRecommendation.displayCount)

        await store.send(.recommendationBookPrepared(sessionID, second, coverFile: coverFile(1))) {
            $0.recommendedBooks = [first, second]
            $0.recommendationCoverFiles[second.id] = self.coverFile(1)
        }

        let all = [first, second] + [4, 5, 6, 7].map(coveredBook)
        let saved = CachedRecommendations(books: all, savedAt: Date(timeIntervalSince1970: 0), coverFiles: [:])
        await store.send(.recommendationsLoaded(sessionID, saved)) {
            $0.isStreamingRecommendations = false
            $0.isPreparingRecommendations = false
            $0.nextRecommendationsSavedAt = Date(timeIntervalSince1970: 0)
            $0.recommendedBooks = all
            $0.recommendationCoverFiles = [:]
        }
    }

    @Test func 이미_보이는_추천이_있으면_한_권씩_섞지_않는다() async {
        let shown = [1, 2, 3, 4, 5, 6].map(coveredBook)
        let store = TestStore(initialState: preparingState(showing: shown, mode: .restore)) { HomeFeature() }

        await store.send(.recommendationBookPrepared(sessionID, coveredBook(9), coverFile: coverFile(9)))
    }

    @Test func 이전_세션의_늦은_책은_무시한다() async {
        let store = TestStore(initialState: preparingState(mode: .profileChanged)) { HomeFeature() }

        await store.send(.recommendationBookPrepared(UUID(1), coveredBook(1), coverFile: coverFile(1)))
    }

    @Test func 오프라인이면_빈_칸만_하드데이터로_채우고_오류를_띄우지_않는다() async {
        let first = coveredBook(1)
        var state = preparingState(mode: .profileChanged)
        state.recommendedBooks = [first]
        state.recommendationCoverFiles = [first.id: coverFile(1)]
        state.isStreamingRecommendations = true
        state.isLoadingRecommendations = false
        let store = TestStore(initialState: state) { HomeFeature() }
        let fallback = [1, 2, 3, 4, 5, 6, 7].map(coveredBook)

        await store.send(.recommendationsOfflineFallback(sessionID, fallback)) {
            $0.isStreamingRecommendations = false
            $0.isPreparingRecommendations = false
            $0.recommendedBooks = [1, 2, 3, 4, 5, 6].map(self.coveredBook)
        }
    }

    @Test func 오프라인이어도_스냅샷이_보이면_그대로_두고_오류를_띄우지_않는다() async {
        let shown = [1, 2, 3, 4, 5, 6].map(coveredBook)
        let store = TestStore(initialState: preparingState(showing: shown, mode: .restore)) { HomeFeature() }

        await store.send(.recommendationsOfflineFallback(sessionID, [7, 8].map(coveredBook))) {
            $0.isPreparingRecommendations = false
        }
    }

    @Test func 하드데이터도_없으면_오류를_띄운다() async {
        let store = TestStore(initialState: preparingState(mode: .profileChanged)) { HomeFeature() }

        await store.send(.recommendationsOfflineFallback(sessionID, [])) {
            $0.isLoadingRecommendations = false
            $0.isPreparingRecommendations = false
            $0.recommendationErrorMessage = "추천 도서를 준비하지 못했어요. 다시 시도해 주세요."
        }
    }

    private func profile(interests: [String]) throws -> UserProfile {
        try UserProfile(
            affiliationKey: ["POSTECH 학부", "학과 및 학부", "무은재학부"],
            departmentName: "무은재학부", interests: interests
        )
    }

    @Test func 관심사를_바꾸면_보이는_6권은_두고_다음_묶음을_준비한다() async throws {
        let before = try profile(interests: ["수학"])
        let after = try profile(interests: ["물리"])
        let shown = (1...6).map(coveredBook)
        let next = (7...12).map(coveredBook)
        @Shared(.userProfile) var userProfile: UserProfile?
        $userProfile.withLock { $0 = after }
        var state = HomeFeature.State()
        state.hasSyncedProfile = true
        state.displayedProfile = before
        state.recommendedBooks = shown
        state.recommendationSessionID = sessionID
        let store = TestStore(initialState: state) { HomeFeature() } withDependencies: {
            $0.uuid = .incrementing
            $0.homeRecommendationForYouClient.prepareReplacement = { _, _ in next }
        }

        await store.send(.userProfileChanged) {
            $0.displayedProfile = after
            $0.carouselPreparation = .loading(UUID(0))
        }
        await store.receive(\.carouselPreparationFinished) {
            $0.carouselPreparation = .finished(.success(next))
        }
        #expect(store.state.recommendedBooks == shown)
    }

    @Test func 관심사를_처음_정하면_바로_새_6권을_준비한다() async throws {
        @Shared(.userProfile) var userProfile: UserProfile?
        $userProfile.withLock { $0 = try? self.profile(interests: ["수학"]) }
        var state = HomeFeature.State()
        state.hasSyncedProfile = true
        state.recommendedBooks = (1...6).map(coveredBook)
        let store = TestStore(initialState: state) { HomeFeature() } withDependencies: {
            $0.uuid = .incrementing
        }
        store.exhaustivity = .off

        await store.send(.userProfileChanged) {
            $0.recommendedBooks = []
            $0.recommendationLoadMode = .profileChanged
            $0.carouselPreparation = .idle
        }
        await store.skipReceivedActions()
    }
}
