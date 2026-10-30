import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct AppRecommendationSessionTests {
    @Test("앱 접속과 백그라운드 복귀 때 준비하고 중복 시작·단순 활성화는 건너뛴다")
    func startsOncePerSession() async {
        let id = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!
        let book = RecommendationCacheFixture.book("a", hasCover: false)
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() } withDependencies: {
            $0.uuid = .constant(id)
            $0.bookRecommendationClient.fetch = { _ in [book] }
            $0.homeRecommendationForYouClient = .live(
                recommendation: $0.bookRecommendationClient, cache: $0.recommendationCacheClient
            )
        }
        await store.send(.appStarted) { $0.hasStartedRecommendationSession = true }
        await store.receive(\.home.recommendationSessionStarted) {
            $0.home.recommendationSessionID = id
            $0.home.isLoadingRecommendations = true
            $0.home.isPreparingRecommendations = true
        }
        await store.receive(\.home.recommendationsRestored)
        await store.receive(\.home.recommendationsLoaded) {
            $0.home.recommendedBooks = [book]
            $0.home.isLoadingRecommendations = false
            $0.home.isPreparingRecommendations = false
            $0.home.nextRecommendationsSavedAt = .distantPast
        }
        await store.send(.appStarted)
        await store.send(.appBecameActive)
        await store.send(.appEnteredBackground) { $0.hasEnteredBackground = true }
        await store.send(.appBecameActive) { $0.hasEnteredBackground = false }
        await store.receive(\.home.recommendationSessionStarted) {
            $0.home.isLoadingRecommendations = true
            $0.home.isPreparingRecommendations = true
            $0.home.nextRecommendationsSavedAt = nil
        }
        await store.receive(\.home.recommendationsRestored)
        await store.receive(\.home.recommendationsLoaded) {
            $0.home.isLoadingRecommendations = false
            $0.home.isPreparingRecommendations = false
            $0.home.nextRecommendationsSavedAt = .distantPast
        }
        await store.finish()
    }
}
