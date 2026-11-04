import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct RecommendationEasterEggTests {
    @Test("/ver1·/ver2는 현재 크기와 관계없이 해당 화면을 열고 같은 명령을 반복해도 유지한다",
          arguments: ["/ver1", "  /ver1\n", "/ver2", "  /ver2\n"], [false, true])
    func selectsRecommendationLayout(command: String, initiallyExpanded: Bool) async {
        let expectedExpanded = command.trimmingCharacters(in: .whitespacesAndNewlines) == "/ver2"
        var initial = AppFeature.State()
        initial.selectedTab = .search
        initial.home.isRecommendationExpanded = initiallyExpanded
        initial.bookSearch.query = command
        initial.bookSearch.recentQueries = ["디자인"]
        initial.bookSearch.errorMessage = "이전 검색 오류"
        initial.bookSearch.hasSearched = true
        let store = TestStore(initialState: initial) { AppFeature() } withDependencies: {
            $0.bookSearchClient.cached = { _ in
                Issue.record("이스터에그 명령은 검색 캐시를 조회하면 안 됩니다")
                return nil
            }
            $0.bookSearchClient.search = { _, _ in
                Issue.record("이스터에그 명령은 검색 API를 호출하면 안 됩니다")
                return []
            }
            $0.searchHistoryClient.save = { _ in
                Issue.record("이스터에그 명령은 검색 기록에 저장하면 안 됩니다")
            }
        }

        await store.send(.bookSearch(.searchButtonTapped)) {
            $0.bookSearch.searchGeneration = 1
            $0.bookSearch.query = ""
            $0.bookSearch.errorMessage = nil
            $0.bookSearch.hasSearched = false
        }
        await store.receive(\.bookSearch.delegate) {
            $0.home.isRecommendationExpanded = expectedExpanded
            $0.selectedTab = .recommendations
        }
        #expect(store.state.bookSearch.recentQueries == ["디자인"])

        await store.send(.tabSelected(.search)) { $0.selectedTab = .search }
        await store.send(.bookSearch(.queryChanged(command))) { $0.bookSearch.query = command }
        await store.send(.bookSearch(.searchButtonTapped)) {
            $0.bookSearch.searchGeneration = 2
            $0.bookSearch.query = ""
        }
        await store.receive(\.bookSearch.delegate) {
            $0.home.isRecommendationExpanded = expectedExpanded
            $0.selectedTab = .recommendations
        }
        await store.finish()
    }

    @Test("/kulumi는 검색을 정리하고 추천 탭의 사진 표지를 켠다")
    func showsKulumiCovers() async {
        var initial = AppFeature.State()
        initial.selectedTab = .search
        initial.home.isRecommendationExpanded = true
        initial.bookSearch.query = "  /kulumi\n"
        initial.bookSearch.recentQueries = ["디자인"]
        initial.bookSearch.isLoading = true
        initial.bookSearch.hasSearched = true
        let store = TestStore(initialState: initial) { AppFeature() } withDependencies: {
            $0.bookSearchClient.cached = { _ in
                Issue.record("이스터에그 명령은 검색 캐시를 조회하면 안 됩니다")
                return nil
            }
            $0.bookSearchClient.search = { _, _ in
                Issue.record("이스터에그 명령은 검색 API를 호출하면 안 됩니다")
                return []
            }
            $0.searchHistoryClient.save = { _ in
                Issue.record("이스터에그 명령은 검색 기록에 저장하면 안 됩니다")
            }
        }

        await store.send(.bookSearch(.searchButtonTapped)) {
            $0.bookSearch.searchGeneration = 1
            $0.bookSearch.query = ""
            $0.bookSearch.isLoading = false
            $0.bookSearch.hasSearched = false
        }
        await store.receive(\.bookSearch.delegate) {
            $0.home.showsKulumiCovers = true
            $0.selectedTab = .recommendations
        }
    }

    @Test("명령과 정확히 일치하지 않는 입력은 일반 검색과 기록을 유지한다",
          arguments: ["ver1", "ver2", "/ver1 책", "/ver2 책", "kulumi", "/kulumi 책"])
    func preservesNormalSearch(query: String) async {
        let store = TestStore(initialState: BookSearchFeature.State(query: query)) {
            BookSearchFeature()
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.hasSearched = true
            $0.isLoading = true
            $0.recentQueries = [query]
        }
        await store.receive(\.searchSucceeded) { $0.isLoading = false }
        await store.finish()
    }

    @Test("진행 중 검색에서 명령으로 전환한 뒤 도착한 응답은 무시한다")
    func ignoresStaleSearchResponse() async {
        let store = TestStore(initialState: BookSearchFeature.State(query: "디자인")) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookSearchClient.search = { _, _ in
                try await Task.sleep(for: .seconds(60))
                return []
            }
        }
        await store.send(.searchButtonTapped) {
            $0.searchGeneration = 1
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = ["디자인"]
        }
        await store.send(.queryChanged("/ver2")) {
            $0.query = "/ver2"
            $0.searchGeneration = 2
            $0.isLoading = false
            $0.hasSearched = false
        }
        await store.send(.searchButtonTapped) {
            $0.query = ""
            $0.searchGeneration = 3
        }
        await store.receive(\.delegate)
        await store.finish()
        await store.send(.searchSucceeded(generation: 1, books: []))
        await store.send(.searchFailed(generation: 1, message: "이전 검색 오류"))
    }
}
