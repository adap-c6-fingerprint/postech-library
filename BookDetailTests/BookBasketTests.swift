import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookBasketTests {
    private func book(id: String, controlNumber: String? = nil) -> Book {
        Book(
            id: id, isbn: nil, controlNumber: controlNumber ?? "record-\(id)",
            title: "도서 \(id)", author: "저자", publisher: nil,
            publicationYear: "2026", description: nil, imageURL: nil
        )
    }

    private func item(_ id: String, addedAt: Date = Date(timeIntervalSince1970: 0)) -> BookBasketItem {
        BookBasketItem(book: book(id: id), addedAt: addedAt)
    }

    @Test("새 클라이언트에서 장바구니와 담은 시각을 복원한다")
    func storageRoundTrip() {
        let suiteName = "BookBasketTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let client = BookBasketClient.userDefaults(suiteName: suiteName)
        let items = [item("a"), item("b", addedAt: Date(timeIntervalSince1970: 100))]
        #expect(client.load().isEmpty)
        client.save(items)
        #expect(BookBasketClient.userDefaults(suiteName: suiteName).load() == items)
    }

    @Test("검색 화면에서 담은 책을 담은 시각과 함께 저장하고 중복 저장하지 않는다")
    func addPersistsOnce() async {
        let suiteName = "BookBasketTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let client = BookBasketClient.userDefaults(suiteName: suiteName)
        let now = Date(timeIntervalSince1970: 1_000)
        let selected = book(id: "a")
        let store = TestStore(initialState: BookSearchFeature.State()) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookBasketClient = client
            $0.date.now = now
        }

        await store.send(.addToBasket(selected)) { $0.basketBooks = [selected] }
        await store.send(.addToBasket(selected))
        #expect(client.load() == [BookBasketItem(book: selected, addedAt: now)])
    }

    @Test("검색 화면을 다시 열면 저장된 장바구니를 복원한다")
    func restoreOnTask() async {
        let saved = item("a")
        let store = TestStore(initialState: BookSearchFeature.State()) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookBasketClient.load = { [saved] }
        }

        await store.send(.task) { $0.basketBooks = [saved.book] }
    }

    @Test("장바구니 화면은 저장된 목록을 불러오고 닫힐 때 검색 화면 권수를 갱신한다")
    func openAndDismissBasket() async {
        let saved = [item("a"), item("b")]
        let store = TestStore(initialState: BookSearchFeature.State()) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookBasketClient.load = { saved }
        }

        await store.send(.basketButtonTapped) { $0.basket = BookBasketFeature.State() }
        await store.send(.basket(.presented(.task))) { $0.basket?.items = saved }
        await store.send(.basket(.dismiss)) {
            $0.basket = nil
            $0.basketBooks = saved.map(\.book)
        }
    }

    @Test("도서 상세에서 담은 책을 담은 시각과 함께 한 번만 저장한다")
    func addFromDetailPersistsOnce() async {
        let suiteName = "BookBasketTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let client = BookBasketClient.userDefaults(suiteName: suiteName)
        let now = Date(timeIntervalSince1970: 2_000)
        let selected = book(id: "a")
        let store = TestStore(initialState: BookDetailFeature.State(book: selected)) {
            BookDetailFeature()
        } withDependencies: {
            $0.bookBasketClient = client
            $0.date.now = now
        }

        await store.send(.addToBasketButtonTapped)
        await store.send(.addToBasketButtonTapped)
        #expect(client.load() == [BookBasketItem(book: selected, addedAt: now)])
    }

    @Test("도서 상세를 닫으면 검색 화면의 장바구니 권수를 저장소 기준으로 갱신한다")
    func refreshBasketAfterDetail() async {
        let selected = book(id: "a")
        let saved = [item("a")]
        var initialState = BookSearchFeature.State()
        initialState.detail = BookDetailFeature.State(book: selected)
        let store = TestStore(initialState: initialState) {
            BookSearchFeature()
        } withDependencies: {
            $0.bookBasketClient.load = { saved }
        }

        await store.send(.detail(.dismiss)) {
            $0.detail = nil
            $0.basketBooks = saved.map(\.book)
        }
    }

    @Test("추천 탭에서도 저장된 장바구니 화면을 열고 닫는다")
    func openBasketFromHome() async {
        let saved = [item("a")]
        let store = TestStore(initialState: HomeFeature.State()) {
            HomeFeature()
        } withDependencies: {
            $0.bookBasketClient.load = { saved }
        }

        await store.send(.basketButtonTapped) { $0.basket = BookBasketFeature.State() }
        await store.send(.basket(.presented(.task))) { $0.basket?.items = saved }
        await store.send(.basket(.dismiss)) { $0.basket = nil }
    }

    @Test("보관 목록을 보관한 날짜별로 최근 날짜부터 묶고 권수를 유지한다")
    func groupByAddedDay() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        let day1 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 9))!
        let day1Later = calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 21))!
        let day2 = calendar.date(from: DateComponents(year: 2026, month: 10, day: 12, hour: 12))!
        let items = [item("a", addedAt: day1), item("b", addedAt: day2), item("c", addedAt: day1Later)]

        let sections = BookBasketSection.grouped(items, calendar: calendar)

        #expect(sections.map(\.day) == [calendar.startOfDay(for: day2), calendar.startOfDay(for: day1)])
        #expect(sections.map { $0.items.map(\.id) } == [["b"], ["c", "a"]])
        #expect(sections.flatMap(\.items).count == items.count)
    }

    @Test("선택 모드에서 길안내할 책을 선택·해제하고 완료하면 선택을 비운다")
    func toggleGuidanceSelection() async {
        let store = TestStore(initialState: BookBasketFeature.State(items: [item("a"), item("b")])) {
            BookBasketFeature()
        }

        await store.send(.selectionToggled("a"))
        await store.send(.selectButtonTapped) { $0.isSelectingForGuidance = true }
        await store.send(.selectionToggled("a")) { $0.selectedIDs = ["a"] }
        await store.send(.selectionToggled("b")) { $0.selectedIDs = ["a", "b"] }
        #expect(store.state.selectedCount == 2)
        await store.send(.selectionToggled("a")) { $0.selectedIDs = ["b"] }
        #expect(store.state.selectedCount == 1)
        await store.send(.selectionToggled("missing"))
        await store.send(.doneButtonTapped) {
            $0.isSelectingForGuidance = false
            $0.selectedIDs = []
        }
    }

    @Test("네 번째 책 선택은 막고 기존 세 권을 유지하며 한도 팝업을 띄운다")
    func blockFourthSelection() async {
        let store = TestStore(initialState: BookBasketFeature.State(
            items: ["a", "b", "c", "d"].map { item($0) },
            isSelectingForGuidance: true,
            selectedIDs: ["a", "b", "c"]
        )) {
            BookBasketFeature()
        }

        await store.send(.selectionToggled("d")) { $0.isSelectionLimitAlertPresented = true }
        #expect(store.state.selectedIDs == ["a", "b", "c"])
        await store.send(.selectionLimitAlertDismissed) { $0.isSelectionLimitAlertPresented = false }
        await store.send(.selectionToggled("b")) { $0.selectedIDs = ["a", "c"] }
        await store.send(.selectionToggled("d")) { $0.selectedIDs = ["a", "c", "d"] }
    }

    @Test("길안내 시작 시 장바구니에 남은 선택 책만 고른 순서대로 전달한다")
    func startGuidanceWithSelectedBooks() async {
        let items = ["a", "b", "c"].map { item($0) }
        let store = TestStore(initialState: BookBasketFeature.State(
            items: items,
            isSelectingForGuidance: true,
            selectedIDs: ["c", "missing", "a"]
        )) {
            BookBasketFeature()
        }

        await store.send(.startGuidanceButtonTapped)
        await store.receive(\.delegate.startGuidance, [items[2].book, items[0].book])
    }

    @Test("선택한 책이 0권이면 길안내를 시작하지 않는다")
    func noGuidanceWithoutSelection() async {
        let store = TestStore(initialState: BookBasketFeature.State(
            items: [item("a")],
            isSelectingForGuidance: true
        )) {
            BookBasketFeature()
        }

        await store.send(.startGuidanceButtonTapped)
    }

    @Test("선택했던 책이 모두 장바구니에서 빠졌으면 0권으로 보고 길안내를 시작하지 않는다")
    func noGuidanceWithStaleSelection() async {
        let store = TestStore(initialState: BookBasketFeature.State(
            items: [item("a")],
            isSelectingForGuidance: true,
            selectedIDs: ["missing"]
        )) {
            BookBasketFeature()
        }

        #expect(store.state.selectedBooks.isEmpty)
        await store.send(.startGuidanceButtonTapped)
    }

    @Test("선택한 책을 확인 후 장바구니에서 제거하고 목록·권수·저장소를 갱신한다")
    func removeSelectedBooks() async {
        let suiteName = "BookBasketTests.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let client = BookBasketClient.userDefaults(suiteName: suiteName)
        let items = ["a", "b", "c"].map { item($0) }
        client.save(items)
        let store = TestStore(initialState: BookBasketFeature.State(
            items: items,
            isSelectingForGuidance: true,
            selectedIDs: ["a", "c"]
        )) {
            BookBasketFeature()
        } withDependencies: {
            $0.bookBasketClient = client
        }

        await store.send(.removeButtonTapped) { $0.isRemoveAlertPresented = true }
        await store.send(.removeAlertDismissed) { $0.isRemoveAlertPresented = false }
        #expect(client.load() == items)
        await store.send(.removeButtonTapped) { $0.isRemoveAlertPresented = true }
        await store.send(.removeConfirmed) {
            $0.isRemoveAlertPresented = false
            $0.items = [items[1]]
            $0.selectedIDs = []
        }
        #expect(client.load() == [items[1]])
        await store.send(.removeButtonTapped)
    }
}
