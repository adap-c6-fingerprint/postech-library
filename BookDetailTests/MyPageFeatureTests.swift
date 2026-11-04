import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct MyPageFeatureTests {
    typealias Path = RecommendationDataset.AffiliationPath

    private static let undergraduateMath = Path(parent: "POSTECH 학부", group: "학과 및 학부", name: "수학과")
    private static let graduateAI = Path(parent: "POSTECH 대학원", group: "독립 대학원 및 학부", name: "인공지능대학원")
    private static let dataset = RecommendationDataset(
        books: [:],
        affiliations: [(undergraduateMath, []), (graduateAI, [])],
        preferences: [("수학", [])]
    )

    private func book(_ id: String, isbn: String?) -> Book {
        Book(id: id, isbn: isbn, controlNumber: "record-\(id)", title: "도서 \(id)", author: "저자",
             publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
    }

    @Test("책장은 기록을 읽어 책등을 받고, ISBN이 없거나 받지 못한 책은 제목 막대로 둔다")
    func shelfLoadsSpines() async {
        let found = book("a", isbn: "9788966260959")
        let failing = book("b", isbn: "9788966260960")
        let noISBN = book("c", isbn: nil)
        let png = Data([0x89, 0x50])
        let store = TestStore(initialState: RecentlyFoundBookFeature.State()) {
            RecentlyFoundBookFeature()
        } withDependencies: {
            $0.recentlyFoundBooksClient.load = { [found, failing, noISBN] }
            $0.bookCoverClient.spinePngData = { isbn in
                guard isbn == found.isbn else { throw RecommendationCacheStore.CacheError.invalidImage }
                return png
            }
        }
        store.exhaustivity = .off

        await store.send(.task) {
            $0.books = [found, failing, noISBN]
            $0.spines = [found.id: .loading, failing.id: .loading, noISBN.id: .unavailable]
        }
        await store.skipReceivedActions()
        #expect(store.state.spines == [found.id: .loaded(png), failing.id: .unavailable, noISBN.id: .unavailable])
    }

    @Test("+ 버튼은 이미 받은 책등과 함께 최근 찾은 책 화면을 연다")
    func addButtonOpensRecentlyFound() async {
        var initial = MyPageFeature.State()
        initial.shelf.books = [book("a", isbn: nil)]
        initial.shelf.spines = ["a": .unavailable]
        let store = TestStore(initialState: initial) { MyPageFeature() }

        await store.send(.addButtonTapped) {
            $0.recentlyFound = initial.shelf
        }
    }

    @Test("최근 찾은 책 화면에서 책등을 누르면 그 책의 상세를 연다")
    func spineOpensDetail() async {
        let selected = book("a", isbn: nil)
        var initial = RecentlyFoundBookFeature.State()
        initial.books = [selected]
        let store = TestStore(initialState: initial) {
            RecentlyFoundBookFeature()
        } withDependencies: {
            $0.bookFavoritesClient.load = { [selected.recordKey] }
        }

        await store.send(.bookSelected(selected)) {
            $0.detail = BookDetailFeature.State(book: selected, isFavorite: true)
        }
    }

    @Test("장바구니 안내 시작하기를 누르면 고른 순서대로 최근 찾은 책에 기록한다")
    func basketGuidanceRecordsBooks() async {
        let recorded = LockIsolated<[Book]>([])
        let a = book("a", isbn: nil), b = book("b", isbn: nil)
        var initial = BookBasketFeature.State()
        initial.items = [BookBasketItem(book: a, addedAt: Date(timeIntervalSince1970: 0)),
                         BookBasketItem(book: b, addedAt: Date(timeIntervalSince1970: 0))]
        initial.selectedIDs = [b.id, a.id]
        let store = TestStore(initialState: initial) {
            BookBasketFeature()
        } withDependencies: {
            $0.recentlyFoundBooksClient.record = { books in recorded.setValue(books) }
        }

        await store.send(.guidanceLinkTapped)
        #expect(recorded.value == [b, a])
    }

    @Test("책 상세의 바로 안내 시작을 누르면 그 책 1권을 최근 찾은 책에 기록한다")
    func detailGuidanceRecordsBook() async {
        let recorded = LockIsolated<[Book]>([])
        let selected = book("a", isbn: nil)
        let store = TestStore(initialState: BookDetailFeature.State(book: selected)) {
            BookDetailFeature()
        } withDependencies: {
            $0.recentlyFoundBooksClient.record = { books in recorded.setValue(books) }
        }

        await store.send(.guidanceStarted)
        #expect(recorded.value == [selected])
    }

    @Test("소속 변경 화면은 저장된 소속을 미리 고르고, 바꾼 소속을 관심 분야와 함께 저장한다")
    func editAffiliationSaves() async {
        let saved = LockIsolated<([String], String, [String])?>(nil)
        let profile = UserProfileSnapshot(
            departmentName: "수학과", interests: ["수학"], affiliationKey: Self.undergraduateMath.key
        )
        let store = TestStore(initialState: EditMyAffiliationFeature.State()) {
            EditMyAffiliationFeature()
        } withDependencies: {
            $0.userProfileClient.load = { profile }
            $0.userProfileClient.save = { key, name, interests in saved.setValue((key, name, interests)) }
            $0.recommendationDatasetClient.load = { Self.dataset }
        }
        store.exhaustivity = .off

        await store.send(.task)
        await store.skipReceivedActions()
        #expect(store.state.selectedAffiliation == Self.undergraduateMath)
        #expect(store.state.canSave == false)
        // 저장된 소속 그대로면 변경하기 버튼이 꺼져 있다.

        await store.send(.parentSelected("POSTECH 대학원"))
        await store.send(.groupSelected("독립 대학원 및 학부"))
        await store.send(.affiliationSelected(Self.graduateAI))
        #expect(store.state.canSave)

        await store.send(.changeButtonTapped)
        await store.skipReceivedActions()
        #expect(saved.value?.0 == Self.graduateAI.key)
        #expect(saved.value?.1 == "인공지능대학원")
        #expect(saved.value?.2 == ["수학"])
    }
}
