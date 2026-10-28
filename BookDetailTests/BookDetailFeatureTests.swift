import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookDetailFeatureTests {
    private func book(isbn: String? = "9788966260959") -> Book {
        Book(id: "selected", isbn: isbn, controlNumber: "record-1", title: "선택한 책",
             author: "저자", publisher: "출판사", publicationYear: "2026",
             description: nil, imageURL: nil)
    }

    private var description: BookDescription {
        BookDescription(text: "책 소개", sourceURL: URL(string: "https://www.yes24.com/product/goods/1")!)
    }

    @Test("소개를 반영하고 화면 재표시로 같은 요청을 반복하지 않는다")
    func loadDescription() async {
        let description = description
        let store = TestStore(initialState: BookDetailFeature.State(book: book(isbn: "8966260950 9788966260959"))) {
            BookDetailFeature()
        } withDependencies: {
            $0.bookDetailClient.fetchDescription = { isbn in
                #expect(isbn == "9788966260959")
                return description
            }
        }
        await store.send(.loadDescription) { $0.isLoading = true }
        await store.receive(\.descriptionLoaded) {
            $0.isLoading = false
            $0.hasLoaded = true
            $0.description = description
        }
        await store.send(.loadDescription)
        await store.finish()
    }

    @Test("바로 안내 시작은 이 책 1권을 길안내 위임 액션으로 전달한다")
    func startGuidanceWithThisBook() async {
        let selected = book()
        let store = TestStore(initialState: BookDetailFeature.State(book: selected)) {
            BookDetailFeature()
        }

        await store.send(.startGuidanceButtonTapped)
        await store.receive(\.delegate.startGuidance, selected)
    }

    @Test("소개 없음은 오류 없이 완료한다")
    func emptyDescription() async {
        let store = TestStore(initialState: BookDetailFeature.State(book: book())) {
            BookDetailFeature()
        } withDependencies: {
            $0.bookDetailClient.fetchDescription = { _ in nil }
        }
        await store.send(.loadDescription) { $0.isLoading = true }
        await store.receive(\.descriptionLoaded) { $0.isLoading = false; $0.hasLoaded = true }
        #expect(store.state.description == nil)
        #expect(store.state.errorMessage == nil)
    }

    @Test("ISBN 누락 시 통신 없이 안내한다")
    func missingISBN() async {
        let store = TestStore(initialState: BookDetailFeature.State(book: book(isbn: nil))) {
            BookDetailFeature()
        } withDependencies: {
            $0.bookDetailClient.fetchDescription = { _ in
                Issue.record("ISBN이 없으면 API를 호출하면 안 됩니다.")
                return nil
            }
        }
        await store.send(.loadDescription) {
            $0.hasLoaded = true
            $0.errorMessage = "조회 가능한 ISBN 정보가 없어 책 소개를 불러올 수 없어요."
        }
        #expect(store.state.isbn13 == nil)
    }

    private actor RetryResponse {
        var attempts = 0
        func fetch(_ description: BookDescription) throws -> BookDescription {
            attempts += 1
            if attempts == 1 { throw URLError(.notConnectedToInternet) }
            return description
        }
    }

    @Test("조회 실패 후 재시도하면 오류를 지우고 소개를 표시한다")
    func retry() async {
        let response = RetryResponse()
        let description = description
        let store = TestStore(initialState: BookDetailFeature.State(book: book())) {
            BookDetailFeature()
        } withDependencies: {
            $0.bookDetailClient.fetchDescription = { _ in try await response.fetch(description) }
        }
        await store.send(.loadDescription) { $0.isLoading = true }
        await store.receive(\.descriptionFailed) {
            $0.isLoading = false; $0.hasLoaded = true
            $0.errorMessage = "책 소개를 불러오지 못했어요. 다시 시도해 주세요."
        }
        await store.send(.retryButtonTapped) { $0.isLoading = true; $0.errorMessage = nil }
        await store.receive(\.descriptionLoaded) { $0.isLoading = false; $0.description = description }
        await store.finish()
        #expect(await response.attempts == 2)
    }

    @Test("상세 화면을 닫으면 진행 중인 요청을 취소하고 검색 결과와 책바구니를 보존한다")
    func dismissDetail() async {
        let selected = book()
        let (started, signal) = AsyncStream.makeStream(of: Void.self)
        let (pending, _) = AsyncStream.makeStream(of: BookDescription.self)
        let store = TestStore(initialState: BookSearchFeature.State(
            query: "검색어", books: [selected], hasSearched: true, basketBooks: [selected]
        )) {
            BookSearchFeature()
        } withDependencies: {
            // 상세를 닫으면 저장소 기준으로 책바구니를 다시 읽는다.
            $0.bookBasketClient.load = { [BookBasketItem(book: selected, addedAt: .distantPast)] }
            $0.bookDetailClient.fetchDescription = { _ in
                signal.yield(())
                for await description in pending { return description }
                throw CancellationError()
            }
        }
        await store.send(.bookSelected(selected)) { $0.detail = BookDetailFeature.State(book: selected) }
        await store.send(.detail(.presented(.loadDescription))) { $0.detail?.isLoading = true }
        for await _ in started { break }
        await store.send(.detail(.presented(.loadDescription)))
        await store.send(.detail(.dismiss)) { $0.detail = nil }
        await store.finish()
        #expect(store.state.query == "검색어")
        #expect(store.state.books == [selected])
        #expect(store.state.basketBooks == [selected])
        await store.send(.addToBasket(selected))
        #expect(store.state.basketBooks.count == 1)
    }
}
