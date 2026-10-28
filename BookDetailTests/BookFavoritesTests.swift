import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookFavoritesTests {
    private func book(id: String, controlNumber: String? = "record-1") -> Book {
        Book(
            id: id, isbn: "9788966260959", controlNumber: controlNumber,
            title: "테스트 도서", author: "저자", publisher: nil,
            publicationYear: "2026", description: nil, imageURL: nil
        )
    }

    @Test("새 클라이언트에서 찜 목록을 복원하고 해제도 저장한다")
    func storageRoundTrip() {
        let suiteName = "BookFavoritesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let client = BookFavoritesClient.userDefaults(suiteName: suiteName)
        let keys: Set<[String?]> = [
            book(id: "first").recordKey,
            book(id: "metadata", controlNumber: nil).recordKey,
        ]
        #expect(client.load().isEmpty)
        client.save(keys)
        let restored = BookFavoritesClient.userDefaults(suiteName: suiteName)
        #expect(restored.load() == keys)

        restored.save([])
        #expect(client.load().isEmpty)
    }

    @Test("재검색으로 화면 ID가 달라져도 같은 도서의 찜을 복원하고 해제한다")
    func restoreAndToggleSameRecord() async {
        let suiteName = "BookFavoritesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let client = BookFavoritesClient.userDefaults(suiteName: suiteName)
        let previousBook = book(id: "previous-result")
        let currentBook = book(id: "new-result")
        let keys: Set<[String?]> = [previousBook.recordKey]
        client.save(keys)
        let store = TestStore(initialState: BookSearchFeature.State(
            query: "테스트", books: [currentBook], basketBooks: [currentBook]
        )) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookFavoritesClient = client
            $0.bookBasketClient.load = { [BookBasketItem(book: currentBook, addedAt: .distantPast)] }
        }

        await store.send(.task) { $0.favoriteBookKeys = keys }
        #expect(store.state.favoriteBookKeys.contains(currentBook.recordKey))
        await store.send(.favoriteButtonTapped(currentBook)) { $0.favoriteBookKeys = [] }
        #expect(client.load().isEmpty)
        await store.send(.favoriteButtonTapped(currentBook)) { $0.favoriteBookKeys = keys }
        #expect(client.load() == keys)
        #expect(store.state.books == [currentBook])
        #expect(store.state.basketBooks == [currentBook])
        #expect(store.state.query == "테스트")
    }

    @Test("ISBN이 같아도 도서관 자료 번호가 다르면 찜 상태를 따로 관리한다")
    func separateLibraryRecords() async {
        let suiteName = "BookFavoritesTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let client = BookFavoritesClient.userDefaults(suiteName: suiteName)
        let first = book(id: "first", controlNumber: "record-1")
        let second = book(id: "second", controlNumber: "record-2")
        let store = TestStore(initialState: BookSearchFeature.State(books: [first, second])) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookFavoritesClient = client
        }

        await store.send(.favoriteButtonTapped(first)) {
            $0.favoriteBookKeys = [first.recordKey]
        }
        #expect(store.state.favoriteBookKeys.contains(first.recordKey))
        #expect(!store.state.favoriteBookKeys.contains(second.recordKey))
        await store.send(.favoriteButtonTapped(second)) {
            $0.favoriteBookKeys = [first.recordKey, second.recordKey]
        }
        await store.send(.favoriteButtonTapped(first)) {
            $0.favoriteBookKeys = [second.recordKey]
        }
        #expect(!store.state.favoriteBookKeys.contains(first.recordKey))
        #expect(store.state.favoriteBookKeys.contains(second.recordKey))
    }
}
