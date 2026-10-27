import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct HomeRecommendationCacheTests {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!

    @Test("저장된 추천은 네트워크 응답을 기다리지 않고 로컬 표지로 표시한다")
    func restoresBeforeNetwork() async {
        let book = RecommendationCacheFixture.book("cached")
        let local = URL(fileURLWithPath: "/cached/cover.png")
        let snapshot = CachedRecommendations(books: [book], savedAt: .distantPast, coverFiles: [book.imageURL!: local])
        let sessionID = sessionID
        let store = TestStore(initialState: HomeFeature.State()) { HomeFeature() } withDependencies: {
            $0.uuid = .constant(sessionID)
            $0.recommendationCacheClient.restore = { snapshot }
            $0.bookRecommendationClient.fetch = { _ in [book] }
            $0.recommendationCacheClient.prepare = { _ in snapshot }
        }
        await store.send(.recommendationSessionStarted) {
            $0.recommendationSessionID = sessionID
            $0.isLoadingRecommendations = true
            $0.isPreparingRecommendations = true
        }
        await store.receive(\.recommendationsRestored) {
            $0.recommendedBooks = snapshot.displayBooks
            $0.isLoadingRecommendations = false
        }
        await store.receive(\.recommendationsLoaded) {
            $0.isPreparingRecommendations = false
            $0.nextRecommendationsSavedAt = .distantPast
        }
        await store.finish()
    }

    @Test("캐시가 없거나 복원에 실패하면 기존 추천 조회로 진입한다", arguments: [false, true])
    func fallsBackToInitialFetch(restoreFails: Bool) async {
        let sessionID = sessionID
        let book = RecommendationCacheFixture.book("first")
        let store = TestStore(initialState: HomeFeature.State()) { HomeFeature() } withDependencies: {
            $0.uuid = .constant(sessionID)
            $0.recommendationCacheClient.restore = {
                if restoreFails { throw URLError(.cannotDecodeContentData) }
                return nil
            }
            $0.bookRecommendationClient.fetch = { _ in [book] }
        }
        await store.send(.recommendationSessionStarted) {
            $0.recommendationSessionID = sessionID
            $0.isLoadingRecommendations = true
            $0.isPreparingRecommendations = true
        }
        await store.receive(\.recommendationsRestored)
        await store.receive(\.recommendationsLoaded) {
            $0.recommendedBooks = [book]
            $0.isLoadingRecommendations = false
            $0.isPreparingRecommendations = false
            $0.nextRecommendationsSavedAt = .distantPast
        }
        await store.finish()
    }

    @Test("새 추천 준비가 끝나도 이번 접속에서 표시 중인 목록은 유지한다")
    func keepsCurrentListUntilNextSession() async {
        let sessionID = sessionID
        let a = RecommendationCacheFixture.book("a", hasCover: false)
        let b = RecommendationCacheFixture.book("b", hasCover: false)
        let saved = CachedRecommendations(books: [a], savedAt: .distantPast, coverFiles: [:])
        let next = CachedRecommendations(books: [b], savedAt: .now, coverFiles: [:])
        let store = TestStore(initialState: HomeFeature.State()) { HomeFeature() } withDependencies: {
            $0.uuid = .constant(sessionID)
            $0.recommendationCacheClient.restore = { saved }
            $0.bookRecommendationClient.fetch = { _ in [b] }
            $0.recommendationCacheClient.prepare = { _ in next }
        }
        await store.send(.recommendationSessionStarted) {
            $0.recommendationSessionID = sessionID
            $0.isLoadingRecommendations = true
            $0.isPreparingRecommendations = true
        }
        await store.receive(\.recommendationsRestored) {
            $0.recommendedBooks = [a]
            $0.isLoadingRecommendations = false
        }
        await store.receive(\.recommendationsLoaded) {
            $0.isPreparingRecommendations = false
            $0.nextRecommendationsSavedAt = next.savedAt
        }
        #expect(store.state.recommendedBooks == [a])
        await store.finish()
    }
}
