import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct HomeRecommendationCacheTests {
    private let sessionID = UUID(uuidString: "00000000-0000-0000-0000-000000000071")!

    @Test("새 추천 알고리즘의 도서를 캐시에 저장하고 이번 접속의 저장본은 유지한다", arguments: [false, true])
    func connectsAlgorithmToHomeAndCache(hasCached: Bool) async {
        let sessionID = sessionID
        let previous = RecommendationCacheFixture.book("previous", hasCover: false)
        let cover = URL(string: "https://covers.example.com/1.png")!
        let localCover = URL(fileURLWithPath: "/cached/1.png")
        let next = Book(
            id: "primo:alma1", isbn: nil, controlNumber: "primo:alma1", title: "맞춤 추천",
            author: "저자", publisher: nil, publicationYear: nil, description: nil, imageURL: cover
        )
        let cached = CachedRecommendations(books: [previous], savedAt: .distantPast, coverFiles: [:])
        let prepared = CachedRecommendations(books: [next], savedAt: .distantFuture, coverFiles: [cover: localCover])
        let store = TestStore(initialState: HomeFeature.State()) { HomeFeature() } withDependencies: {
            $0.uuid = .constant(sessionID)
            $0.bookRecommendationClient = .liveValue
            $0.searchHistoryClient.load = { ["스위프트"] }
            $0.personalizedRecommendationClient.fetch = { _ in
                [RecommendedBook(recordID: "alma1", coverImageURL: cover)]
            }
            $0.bookClient.search = { request in
                let query = request.query
                #expect(request.category == .monograph)
                #expect(query == "1")
                return [next]
            }
            $0.recommendationCacheClient.restore = { hasCached ? cached : nil }
            $0.recommendationCacheClient.prepare = { books in
                await MainActor.run { #expect(books == [next]) }
                return prepared
            }
        }
        await store.send(.recommendationSessionStarted) {
            $0.recommendationSessionID = sessionID
            $0.isLoadingRecommendations = true
            $0.isPreparingRecommendations = true
        }
        if hasCached {
            await store.receive(\.recommendationsRestored) {
                $0.recommendedBooks = [previous]
                $0.isLoadingRecommendations = false
            }
        } else {
            await store.receive(\.recommendationsRestored)
        }
        await store.receive(\.recommendationsLoaded) {
            if !hasCached { $0.recommendedBooks = prepared.displayBooks }
            $0.isLoadingRecommendations = false
            $0.isPreparingRecommendations = false
            $0.nextRecommendationsSavedAt = .distantFuture
        }
        #expect(store.state.recommendedBooks == (hasCached ? [previous] : prepared.displayBooks))
        await store.finish()
    }

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

    @Test("첫 조회와 배경 갱신 실패를 표시하고 기존 추천은 보존한다", arguments: [false, true])
    func preservesDisplayOnFailure(hasCached: Bool) async {
        let sessionID = sessionID
        let a = RecommendationCacheFixture.book("a", hasCover: false)
        let snapshot = CachedRecommendations(books: [a], savedAt: .distantPast, coverFiles: [:])
        let store = TestStore(initialState: HomeFeature.State()) { HomeFeature() } withDependencies: {
            $0.uuid = .constant(sessionID)
            $0.recommendationCacheClient.restore = { hasCached ? snapshot : nil }
            $0.bookRecommendationClient.fetch = { _ in throw URLError(.notConnectedToInternet) }
        }
        await store.send(.recommendationSessionStarted) {
            $0.recommendationSessionID = sessionID
            $0.isLoadingRecommendations = true
            $0.isPreparingRecommendations = true
        }
        if hasCached {
            await store.receive(\.recommendationsRestored) {
                $0.recommendedBooks = [a]
                $0.isLoadingRecommendations = false
            }
        } else {
            await store.receive(\.recommendationsRestored)
        }
        await store.receive(\.recommendationsFailed) {
            $0.isLoadingRecommendations = false
            $0.isPreparingRecommendations = false
            $0.recommendationErrorMessage = "추천 도서를 준비하지 못했어요. 다시 시도해 주세요."
        }
        #expect(store.state.recommendedBooks == (hasCached ? [a] : []))
        await store.finish()
    }

    @Test("최초 조회 실패 후 재시도하면 준비한 로컬 목록을 표시한다")
    func retriesInitialFailure() async {
        let sessionID = sessionID
        let a = RecommendationCacheFixture.book("a", hasCover: false)
        var state = HomeFeature.State()
        state.recommendationSessionID = sessionID
        state.recommendationErrorMessage = "이전 오류"
        let store = TestStore(initialState: state) { HomeFeature() } withDependencies: {
            $0.uuid = .constant(sessionID)
            $0.bookRecommendationClient.fetch = { _ in [a] }
        }
        await store.send(.retryRecommendationsButtonTapped)
        await store.receive(\.recommendationSessionStarted) {
            $0.isLoadingRecommendations = true
            $0.isPreparingRecommendations = true
            $0.recommendationErrorMessage = nil
        }
        await store.receive(\.recommendationsRestored)
        await store.receive(\.recommendationsLoaded) {
            $0.recommendedBooks = [a]
            $0.isLoadingRecommendations = false
            $0.isPreparingRecommendations = false
            $0.nextRecommendationsSavedAt = .distantPast
        }
        await store.finish()
    }

    @Test("이전 접속에서 늦게 도착한 성공·실패·복원 액션은 무시한다")
    func ignoresPreviousSessionActions() async {
        let a = RecommendationCacheFixture.book("a", hasCover: false)
        let b = RecommendationCacheFixture.book("b", hasCover: false)
        var state = HomeFeature.State()
        state.recommendationSessionID = sessionID
        state.recommendedBooks = [a]
        let oldID = UUID()
        let old = CachedRecommendations(books: [b], savedAt: .distantPast, coverFiles: [:])
        let store = TestStore(initialState: state) { HomeFeature() }
        await store.send(.recommendationsLoaded(oldID, old))
        await store.send(.recommendationsFailed(oldID, "늦은 오류"))
        await store.send(.recommendationsRestored(oldID, old))
        #expect(store.state.recommendedBooks == [a])
    }

    @Test("빈 추천 응답은 저장하지 않고 재시도 가능한 오류로 표시한다")
    func handlesEmptyResults() async {
        let sessionID = sessionID
        let store = TestStore(initialState: HomeFeature.State()) { HomeFeature() } withDependencies: {
            $0.uuid = .constant(sessionID)
            $0.bookRecommendationClient.fetch = { _ in [] }
            $0.recommendationCacheClient.prepare = { _ in
                Issue.record("빈 추천은 저장하면 안 된다")
                throw URLError(.badServerResponse)
            }
        }
        await store.send(.recommendationSessionStarted) {
            $0.recommendationSessionID = sessionID
            $0.isLoadingRecommendations = true
            $0.isPreparingRecommendations = true
        }
        await store.receive(\.recommendationsRestored)
        await store.receive(\.recommendationsFailed) {
            $0.isLoadingRecommendations = false
            $0.isPreparingRecommendations = false
            $0.recommendationErrorMessage = "추천 도서를 찾지 못했어요. 다시 시도해 주세요."
        }
        await store.finish()
    }
}
