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
            $0.bookRecommendationClient.fetch = { _ in
                Issue.record("저장본을 표시할 때 네트워크를 기다리지 않는다")
                return []
            }
        }
        await store.send(.recommendationSessionStarted) {
            $0.recommendationSessionID = sessionID
            $0.isLoadingRecommendations = true
        }
        await store.receive(\.recommendationsRestored) {
            $0.recommendedBooks = snapshot.displayBooks
            $0.isLoadingRecommendations = false
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
        }
        await store.receive(\.recommendationsRestored)
        await store.receive(\.recommendationsLoaded) {
            $0.recommendedBooks = [book]
            $0.isLoadingRecommendations = false
        }
        await store.finish()
    }
}
