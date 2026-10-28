import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookDetailFavoritesTests {
    private func book(_ record: String, id: String? = nil) -> Book {
        Book(id: id ?? record, isbn: "9788966260959", controlNumber: record,
             title: "테스트 도서", author: "저자", publisher: nil,
             publicationYear: "2026", description: nil, imageURL: nil)
    }

    @Test("상세에서 기존 찜을 복원하고 다른 책의 찜을 보존하며 해제·저장한다")
    func restoreAndToggleWithOtherFavorites() async {
        let suite = "BookDetailFavoritesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookFavoritesClient.userDefaults(suiteName: suite)
        let selected = book("selected")
        let other = book("other")
        let keys: Set<[String?]> = [selected.recordKey, other.recordKey]
        client.save(keys)
        var initial = BookDetailFeature.State(book: selected)
        initial.holdingsState = .failed
        let store = TestStore(initialState: initial) { BookDetailFeature() } withDependencies: {
            $0.bookFavoritesClient = client
        }

        await store.send(.loadFavorites) { $0.isFavorite = true }
        await store.send(.favoriteButtonTapped) { $0.isFavorite = false }
        await store.receive(\.delegate)
        #expect(client.load() == [other.recordKey])
        #expect(store.state.holdingsState == .failed)

        // 화면 밖에서 바뀐 저장 목록도 다음 토글 시 보존한다.
        let newlyAdded = book("newly-added")
        client.save([other.recordKey, newlyAdded.recordKey])
        await store.send(.favoriteButtonTapped) { $0.isFavorite = true }
        await store.receive(\.delegate)
        #expect(client.load() == [selected.recordKey, other.recordKey, newlyAdded.recordKey])
        await store.finish()
    }

    @Test("검색 상세의 찜 변경은 목록에도 반영되고 다시 열어도 유지된다")
    func searchDetailUpdatesListAndRestores() async {
        let suite = "BookDetailFavoritesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookFavoritesClient.userDefaults(suiteName: suite)
        let selected = book("selected")
        let store = TestStore(initialState: BookSearchFeature.State(books: [selected])) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookFavoritesClient = client
        }

        await store.send(.bookSelected(selected)) {
            $0.detail = BookDetailFeature.State(book: selected)
        }
        await store.send(.detail(.presented(.favoriteButtonTapped))) {
            $0.detail?.isFavorite = true
        }
        await store.receive(\.detail.presented.delegate) {
            $0.favoriteBookKeys = [selected.recordKey]
        }
        await store.send(.detail(.dismiss)) { $0.detail = nil }
        let sameRecord = book("selected", id: "new-search-result")
        await store.send(.bookSelected(sameRecord)) {
            $0.detail = BookDetailFeature.State(book: sameRecord, isFavorite: true)
        }
        #expect(client.load() == [selected.recordKey])
        await store.finish()
    }

    @Test("추천 상세와 검색의 기존 찜 버튼은 같은 목록과 상세 상태를 갱신한다")
    func favoritesStayInSyncAcrossHomeAndSearch() async {
        let suite = "BookDetailFavoritesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookFavoritesClient.userDefaults(suiteName: suite)
        let selected = book("selected")
        let other = book("other")
        var initial = AppFeature.State()
        initial.bookSearch.books = [selected, other]
        initial.home.detail = BookDetailFeature.State(book: selected)
        initial.bookSearch.detail = BookDetailFeature.State(book: selected)
        let store = TestStore(initialState: initial) { AppFeature() } withDependencies: {
            $0.bookFavoritesClient = client
        }

        await store.send(.home(.detail(.presented(.favoriteButtonTapped)))) {
            $0.home.detail?.isFavorite = true
        }
        await store.receive(\.home.detail.presented.delegate)
        await store.receive(\.home.delegate) {
            $0.bookSearch.favoriteBookKeys = [selected.recordKey]
            $0.bookSearch.detail?.isFavorite = true
        }
        await store.send(.bookSearch(.favoriteButtonTapped(other))) {
            $0.bookSearch.favoriteBookKeys = [selected.recordKey, other.recordKey]
        }
        await store.send(.bookSearch(.favoriteButtonTapped(selected))) {
            $0.bookSearch.favoriteBookKeys = [other.recordKey]
            $0.bookSearch.detail?.isFavorite = false
            $0.home.detail?.isFavorite = false
        }
        #expect(client.load() == [other.recordKey])

        // 검색 상세에서의 변경도 추천 상세로 되돌아간다.
        await store.send(.bookSearch(.detail(.presented(.favoriteButtonTapped)))) {
            $0.bookSearch.detail?.isFavorite = true
        }
        await store.receive(\.bookSearch.detail.presented.delegate) {
            $0.bookSearch.favoriteBookKeys = [selected.recordKey, other.recordKey]
            $0.home.detail?.isFavorite = true
        }
        #expect(client.load() == [selected.recordKey, other.recordKey])
        await store.finish()
    }

    @Test("기존 검색 찜 목록을 추천 상세 진입 시 즉시 복원한다")
    func homeDetailStartsWithStoredFavorite() async {
        let suite = "BookDetailFavoritesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookFavoritesClient.userDefaults(suiteName: suite)
        let selected = book("selected")
        client.save([selected.recordKey])
        let store = TestStore(initialState: HomeFeature.State()) { HomeFeature() } withDependencies: {
            $0.bookFavoritesClient = client
        }
        await store.send(.bookSelected(selected)) {
            $0.detail = BookDetailFeature.State(book: selected, isFavorite: true)
        }
        await store.finish()
    }
}
