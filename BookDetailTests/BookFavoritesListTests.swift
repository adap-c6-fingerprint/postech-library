import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookFavoritesListTests {
    private let day1 = Date(timeIntervalSince1970: 1_790_000_000)
    private let day2 = Date(timeIntervalSince1970: 1_790_000_000 + 86_400 * 3)

    private func book(_ id: String) -> Book {
        Book(
            id: id, isbn: "9788966260959", controlNumber: "record-\(id)",
            title: "도서 \(id)", author: "저자", publisher: nil,
            publicationYear: "2026", description: nil, imageURL: nil
        )
    }

    @Test("찜한 책 정보와 시각을 기록하고, 찜 해제하면 함께 지운다")
    func recordsItemsAndPrunesOnSave() {
        let suite = "BookFavoritesListTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookFavoritesClient.userDefaults(suiteName: suite)
        let first = book("1"), second = book("2")

        client.record(first, day1)
        client.record(second, day2)
        #expect(client.loadItems().isEmpty)
        // 찜 키에 없는 책은 목록에 나오지 않는다.

        client.save([first.recordKey, second.recordKey])
        let restored = BookFavoritesClient.userDefaults(suiteName: suite)
        #expect(Set(restored.loadItems().map(\.book.id)) == ["1", "2"])
        #expect(restored.loadItems().first { $0.book.id == "1" }?.favoritedAt == day1)

        client.save([second.recordKey])
        client.save([first.recordKey, second.recordKey])
        #expect(client.loadItems().map(\.book.id) == ["2"])
        // 해제할 때 지운 책 정보는 키만 다시 넣어도 되살아나지 않는다.
    }

    @Test("찜한 날짜별로 최근 날짜부터 묶는다")
    func groupsByDay() {
        let calendar = Calendar(identifier: .gregorian)
        let items = [
            BookFavoriteItem(book: book("old"), favoritedAt: day1),
            BookFavoriteItem(book: book("new-1"), favoritedAt: day2),
            BookFavoriteItem(book: book("new-2"), favoritedAt: day2.addingTimeInterval(60)),
        ]
        let sections = BookFavoriteSection.grouped(items, calendar: calendar)
        #expect(sections.map { $0.items.map(\.book.id) } == [["new-2", "new-1"], ["old"]])
    }

    @Test("상세에서 찜하면 목록 화면용 정보가 기록된다")
    func detailFavoriteRecordsItem() async {
        let suite = "BookFavoritesListTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookFavoritesClient.userDefaults(suiteName: suite)
        let selected = book("1")
        let store = TestStore(initialState: BookDetailFeature.State(book: selected, isFavorite: false)) {
            BookDetailFeature()
        } withDependencies: {
            $0.bookFavoritesClient = client
            $0.date.now = day1
        }
        store.exhaustivity = .off

        await store.send(.favoriteButtonTapped) { $0.isFavorite = true }
        #expect(client.loadItems() == [BookFavoriteItem(book: selected, favoritedAt: day1)])
    }

    @Test("선택한 책을 찜 목록에서 삭제하고 바뀐 찜 키를 알린다")
    func removeSelected() async {
        let suite = "BookFavoritesListTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookFavoritesClient.userDefaults(suiteName: suite)
        let first = book("1"), second = book("2")
        client.record(first, day1)
        client.record(second, day2)
        client.save([first.recordKey, second.recordKey])

        let store = TestStore(initialState: BookFavoritesFeature.State()) {
            BookFavoritesFeature()
        } withDependencies: {
            $0.bookFavoritesClient = client
        }

        await store.send(.task) { $0.items = client.loadItems() }
        await store.send(.removeButtonTapped)
        // 선택한 책이 없으면 아무것도 지우지 않는다.
        await store.send(.selectionToggled(first.id)) { $0.selectedIDs = [first.id] }
        await store.send(.removeButtonTapped) {
            $0.items = [BookFavoriteItem(book: second, favoritedAt: day2)]
            $0.selectedIDs = []
        }
        await store.receive(\.delegate.favoritesChanged, [second.recordKey])
        #expect(client.load() == [second.recordKey])
    }

    @Test("선택한 책을 장바구니에 담아도 찜 목록에는 남고 선택만 풀린다")
    func addSelectedToBasket() async {
        let favoritesSuite = "BookFavoritesListTests.\(UUID().uuidString)"
        let basketSuite = "BookFavoritesListTests.basket.\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: favoritesSuite)
            UserDefaults.standard.removePersistentDomain(forName: basketSuite)
        }
        let favorites = BookFavoritesClient.userDefaults(suiteName: favoritesSuite)
        let basket = BookBasketClient.userDefaults(suiteName: basketSuite)
        let first = book("1"), second = book("2")
        favorites.record(first, day1)
        favorites.record(second, day2)
        favorites.save([first.recordKey, second.recordKey])

        let store = TestStore(initialState: BookFavoritesFeature.State()) {
            BookFavoritesFeature()
        } withDependencies: {
            $0.bookFavoritesClient = favorites
            $0.bookBasketClient = basket
            $0.date.now = day2
        }

        await store.send(.task) { $0.items = favorites.loadItems() }
        await store.send(.selectionToggled(second.id)) { $0.selectedIDs = [second.id] }
        await store.send(.addToBasketButtonTapped) {
            $0.selectedIDs = []
            $0.isAddedToBasketAlertPresented = true
        }
        await store.receive(\.delegate.basketChanged)
        #expect(basket.load().map(\.book.id) == [second.id])
        #expect(favorites.load() == [first.recordKey, second.recordKey])

        await store.send(.goToBasketButtonTapped) {
            $0.isAddedToBasketAlertPresented = false
            $0.basket = BookBasketFeature.State()
        }
    }

    @Test("장바구니 한도를 넘기면 한 권도 담지 않고 한도 팝업을 띄운다")
    func basketLimitBlocksAll() async {
        let favoritesSuite = "BookFavoritesListTests.\(UUID().uuidString)"
        let basketSuite = "BookFavoritesListTests.basket.\(UUID().uuidString)"
        defer {
            UserDefaults.standard.removePersistentDomain(forName: favoritesSuite)
            UserDefaults.standard.removePersistentDomain(forName: basketSuite)
        }
        let favorites = BookFavoritesClient.userDefaults(suiteName: favoritesSuite)
        let basket = BookBasketClient.userDefaults(suiteName: basketSuite)
        basket.save((0..<BookBasketItem.maxStoredCount).map {
            BookBasketItem(book: book("stored-\($0)"), addedAt: day1)
        })
        let selected = book("new")
        favorites.record(selected, day1)
        favorites.save([selected.recordKey])

        let store = TestStore(initialState: BookFavoritesFeature.State()) {
            BookFavoritesFeature()
        } withDependencies: {
            $0.bookFavoritesClient = favorites
            $0.bookBasketClient = basket
            $0.date.now = day2
        }

        await store.send(.task) { $0.items = favorites.loadItems() }
        await store.send(.selectionToggled(selected.id)) { $0.selectedIDs = [selected.id] }
        await store.send(.addToBasketButtonTapped) { $0.isBasketLimitAlertPresented = true }
        #expect(basket.load().count == BookBasketItem.maxStoredCount)
        #expect(!basket.load().contains { $0.book.id == selected.id })
    }

    @Test("홈(지도)·검색 탭의 하트 버튼으로 찜 목록을 열고, 지운 찜을 검색 상태에 반영한다")
    func searchPathOpensFavorites() async {
        let suite = "BookFavoritesListTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suite) }
        let client = BookFavoritesClient.userDefaults(suiteName: suite)
        let first = book("1"), second = book("2")
        client.record(first, day1)
        client.record(second, day2)
        client.save([first.recordKey, second.recordKey])

        let store = TestStore(initialState: BookSearchFeature.State(
            favoriteBookKeys: [first.recordKey, second.recordKey]
        )) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookFavoritesClient = client
        }

        await store.send(.favoritesButtonTapped) { $0.favorites = BookFavoritesFeature.State() }
        await store.send(\.favorites.task) { $0.favorites?.items = client.loadItems() }
        await store.send(\.favorites.selectionToggled, first.id) { $0.favorites?.selectedIDs = [first.id] }
        await store.send(\.favorites.removeButtonTapped) {
            $0.favorites?.items = [BookFavoriteItem(book: second, favoritedAt: day2)]
            $0.favorites?.selectedIDs = []
        }
        await store.receive(\.favorites.delegate.favoritesChanged, [second.recordKey]) {
            $0.favoriteBookKeys = [second.recordKey]
        }
    }
}
