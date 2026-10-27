import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookSearchHistoryTests {
    @Test("새 저장 클라이언트에서도 이전 검색 기록을 불러온다")
    func restoreFromStorage() {
        let suiteName = "BookSearchHistoryTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let history = SearchHistoryClient.userDefaults(suiteName: suiteName)
        #expect(history.load().isEmpty)

        history.save(["사피엔스", "코스모스"])

        let restored = SearchHistoryClient.userDefaults(suiteName: suiteName)
        #expect(restored.load() == ["사피엔스", "코스모스"])
    }

    @Test("화면 진입 시 복원하고 새 검색 후 최근 20개를 저장한다")
    func restoreAndSaveLatestTwenty() async {
        let suiteName = "BookSearchHistoryTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let history = SearchHistoryClient.userDefaults(suiteName: suiteName)
        let previous = (0..<20).map { "검색어 \($0)" }
        history.save(previous)
        let expected = ["새 검색어"] + Array(previous.prefix(19))
        let store = TestStore(initialState: BookSearchFeature.State(query: " 새 검색어\n")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient = history
            $0.bookClient.search = { _ in [] }
        }

        await store.send(.task) { $0.recentQueries = previous }
        await store.send(.searchButtonTapped) {
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = expected
        }
        await store.receive(\.searchSucceeded) { $0.isLoading = false }
        #expect(SearchHistoryClient.userDefaults(suiteName: suiteName).load() == expected)
    }

    @Test("같은 검색어는 중복 없이 맨 앞으로 옮기고 빈 검색어는 저장하지 않는다")
    func duplicateAndEmptyQueries() async {
        let suiteName = "BookSearchHistoryTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let history = SearchHistoryClient.userDefaults(suiteName: suiteName)
        history.save(["코스모스", "사피엔스"])
        let store = TestStore(initialState: BookSearchFeature.State(query: " 사피엔스 ")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient = history
            $0.bookClient.search = { _ in [] }
        }

        await store.send(.task) { $0.recentQueries = ["코스모스", "사피엔스"] }
        await store.send(.searchButtonTapped) {
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = ["사피엔스", "코스모스"]
        }
        await store.receive(\.searchSucceeded) { $0.isLoading = false }
        #expect(history.load() == ["사피엔스", "코스모스"])

        await store.send(.queryChanged(" \n")) { $0.query = " \n" }
        await store.send(.searchButtonTapped) { $0.hasSearched = false }
        #expect(history.load() == ["사피엔스", "코스모스"])
    }

    @Test("도서 조회가 실패해도 시도한 검색어는 저장한다")
    func saveWhenSearchFails() async {
        let suiteName = "BookSearchHistoryTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let history = SearchHistoryClient.userDefaults(suiteName: suiteName)
        let error = URLError(.notConnectedToInternet)
        let message = error.localizedDescription
        let store = TestStore(initialState: BookSearchFeature.State(query: "사피엔스")) {
            BookSearchFeature()
        } withDependencies: {
            $0.searchHistoryClient = history
            $0.bookClient.search = { _ in throw error }
        }

        await store.send(.searchButtonTapped) {
            $0.isLoading = true
            $0.hasSearched = true
            $0.recentQueries = ["사피엔스"]
        }
        await store.receive(\.searchFailed) {
            $0.isLoading = false
            $0.errorMessage = message
        }
        #expect(history.load() == ["사피엔스"])
    }
}
