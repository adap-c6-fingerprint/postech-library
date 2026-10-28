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
}
