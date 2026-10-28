//
//  BookSearchFeature.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Foundation
import ComposableArchitecture

@Reducer
struct BookSearchFeature {
    
    // 화면과 검색 로직에 필요한 데이터
    @ObservableState
    struct State: Equatable {
        var query: String = ""
        var recentQueries: [String] = []
        var favoriteBookKeys: Set<[String?]> = []
        var books: [Book] = []
        var isLoading: Bool = false
        var errorMessage: String? = nil
        var hasSearched: Bool = false
        
        var basketBooks: [Book] = []
        @Presents var detail: BookDetailFeature.State?
        @Presents var basket: BookBasketFeature.State?
    }
    
    // 이 기능에서 발생할 수 있는 이벤트
    enum Action {
        case task
        case queryChanged(String)
        case searchCancelled
        case searchButtonTapped
        case refreshButtonTapped
        case searchSucceeded([Book])
        case searchFailed(String)
        case favoriteButtonTapped(Book)
        
        case addToBasket(Book)
        case removeFromBasket(Set<Book.ID>)
        case bookSelected(Book)
        case detail(PresentationAction<BookDetailFeature.Action>)
        case basketButtonTapped
        case basket(PresentationAction<BookBasketFeature.Action>)
    }
    
    // 검색에 사용할 BookClient 값
    @Dependency(\.bookClient)
    var bookClient: BookClient

    @Dependency(\.bookSearchCache)
    var bookSearchCache: BookSearchCacheClient

    @Dependency(\.searchHistoryClient)
    var searchHistoryClient: SearchHistoryClient

    @Dependency(\.bookFavoritesClient)
    var bookFavoritesClient: BookFavoritesClient

    @Dependency(\.bookBasketClient)
    var bookBasketClient: BookBasketClient

    @Dependency(\.date.now)
    var now: Date

    private nonisolated enum CancelID: Hashable, Sendable {
        case search
    }
    
    // Action을 받아 State를 바꾸고, 필요한 Effect를 반환
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.recentQueries = searchHistoryClient.load()
                state.favoriteBookKeys = bookFavoritesClient.load()
                // 저장된 장바구니를 복원하되 이미 담긴 책은 다시 넣지 않는다.
                for item in bookBasketClient.load() where !state.basketBooks.contains(where: {
                    $0.recordKey == item.book.recordKey
                }) {
                    state.basketBooks.append(item.book)
                }
                return .none

            case let .favoriteButtonTapped(book):
                let key = book.recordKey
                if state.favoriteBookKeys.contains(key) {
                    state.favoriteBookKeys.remove(key)
                } else {
                    state.favoriteBookKeys.insert(key)
                }
                bookFavoritesClient.save(state.favoriteBookKeys)
                return .none

            case let .bookSelected(book):
                state.detail = BookDetailFeature.State(book: book)
                return .none

            case .detail(.dismiss):
                // 상세 화면에서 담은 책을 검색 화면의 바로가기 권수에 반영한다.
                state.basketBooks = bookBasketClient.load().map(\.book)
                return .none

            case .detail:
                return .none

            case .basketButtonTapped:
                state.basket = BookBasketFeature.State()
                return .none

            case .basket(.dismiss):
                // 장바구니 화면에서 바뀐 목록을 검색 화면의 바로가기 권수에 반영한다.
                state.basketBooks = bookBasketClient.load().map(\.book)
                return .none

            case .basket(.presented(.delegate(.startGuidance))):
                // TODO: 경로 요약 페이지(07)를 구현하면 선택한 책을 넘겨 화면을 연다.
                return .none

            case .basket:
                return .none
                
            case let .addToBasket(book):
                guard !state.basketBooks.contains(where: {
                    $0.recordKey == book.recordKey
                }) else {
                    return .none
                }
                
                state.basketBooks.append(book)
                bookBasketClient.add(book, at: now)
                return .none
                
            case let .queryChanged(query):
                state.query = query
                return .none

            case .searchCancelled:
                state.query = ""
                state.books = []
                state.isLoading = false
                state.errorMessage = nil
                state.hasSearched = false
                return .cancel(id: CancelID.search)
                
            case .searchButtonTapped, .refreshButtonTapped:
                // 이미 검색 중이면 추가 요청을 보내지 않음
                guard !state.isLoading else {
                    return .none
                }
                
                let keyword = state.query.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                
                // 빈 검색어는 통신 없이 처리
                guard !keyword.isEmpty else {
                    state.books = []
                    state.errorMessage = nil
                    state.hasSearched = false
                    return .none
                }
                
                state.errorMessage = nil
                state.hasSearched = true
                
                state.recentQueries.removeAll { $0 == keyword }
                state.recentQueries.insert(keyword, at: 0)
                state.recentQueries = Array(state.recentQueries.prefix(20))
                searchHistoryClient.save(state.recentQueries)

                if case .refreshButtonTapped = action {
                    // 사용자가 새로고침하면 유효기간 안의 결과도 다시 조회한다.
                    bookSearchCache.remove(keyword)
                } else if let books = bookSearchCache.load(keyword) {
                    state.books = books
                    return .none
                }

                state.isLoading = true
                state.books = []

                // 검색할 작업을 담은 Effect 값을 만들어 반환
                return .run { [bookClient, bookSearchCache] send in
                    do {
                        // Store가 Effect를 실행하면 이 코드가 동작
                        let books = try await bookClient.search(keyword)
                        try Task.checkCancellation()
                        bookSearchCache.save(keyword, books)
                        
                        // 검색 결과를 새로운 Action으로 보냄
                        await send(.searchSucceeded(books))
                    } catch is CancellationError {
                        return
                    } catch {
                        guard !Task.isCancelled else { return }
                        await send(
                            .searchFailed(error.localizedDescription)
                        )
                    }
                }
                .cancellable(id: CancelID.search, cancelInFlight: true)
                
            case let .searchSucceeded(books):
                // 화면 ID가 모두 다른지 확인
                assert(Set(books.map(\.id)).count == books.count)
                
                // 제어번호가 있는 항목끼리 중복되는지 확인
                let controlNumber = books.compactMap(\.controlNumber)
                assert(Set(controlNumber).count == controlNumber.count)
                
                state.isLoading = false
                state.books = books
                return .none
                
            case let .searchFailed(message):
                state.isLoading = false
                state.errorMessage = message
                return .none
                
            case let .removeFromBasket(bookIDs):
                let removedKeys = Set(
                    state.basketBooks.filter { bookIDs.contains($0.id) }.map(\.recordKey)
                )
                state.basketBooks.removeAll { book in
                    bookIDs.contains(book.id)
                }
                bookBasketClient.save(
                    bookBasketClient.load().filter { !removedKeys.contains($0.book.recordKey) }
                )

                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            BookDetailFeature()
        }
        .ifLet(\.$basket, action: \.basket) {
            BookBasketFeature()
        }
    }
}
