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
        var category: BookSearchCategory = .all
        var searchGeneration: Int = 0
        var recentQueries: [String] = []
        var favoriteBookKeys: Set<[String?]> = []
        var books: [Book] = []
        var isLoading: Bool = false
        var errorMessage: String? = nil
        var hasSearched: Bool = false
        
        var basketBooks: [Book] = []
        @Presents var detail: BookDetailFeature.State?
    }
    
    // 이 기능에서 발생할 수 있는 이벤트
    enum Action {
        case task
        case queryChanged(String)
        case categoryChanged(BookSearchCategory)
        case searchCancelled
        case searchButtonTapped
        case refreshButtonTapped
        case searchSucceeded(generation: Int, books: [Book])
        case searchFailed(generation: Int, message: String)
        case favoriteButtonTapped(Book)
        
        case addToBasket(Book)
        case removeFromBasket(Set<Book.ID>)
        case bookSelected(Book)
        case detail(PresentationAction<BookDetailFeature.Action>)
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
                return .none

            case let .favoriteButtonTapped(book):
                state.favoriteBookKeys = bookFavoritesClient.load()
                let key = book.recordKey
                if state.favoriteBookKeys.contains(key) {
                    state.favoriteBookKeys.remove(key)
                } else {
                    state.favoriteBookKeys.insert(key)
                }
                bookFavoritesClient.save(state.favoriteBookKeys)
                if let detailBook = state.detail?.book {
                    let isFavorite = state.favoriteBookKeys.contains(detailBook.recordKey)
                    state.detail?.isFavorite = isFavorite
                }
                return .none

            case let .bookSelected(book):
                state.favoriteBookKeys = bookFavoritesClient.load()
                state.detail = BookDetailFeature.State(
                    book: book, isFavorite: state.favoriteBookKeys.contains(book.recordKey)
                )
                return .none

            case let .detail(.presented(.delegate(.addToBasket(book)))):
                return .send(.addToBasket(book))

            case let .detail(.presented(.delegate(.favoritesChanged(keys)))):
                state.favoriteBookKeys = keys
                return .none

            case .detail:
                return .none
                
            case let .addToBasket(book):
                guard !state.basketBooks.contains(where: {
                    $0.recordKey == book.recordKey
                }) else {
                    return .none
                }
                
                state.basketBooks.append(book)
                return .none
                
            case let .queryChanged(query):
                state.query = query
                return .none

            case let .categoryChanged(category):
                guard state.category != category else { return .none }
                state.category = category
                guard state.hasSearched else { return .none }
                // 검색 중이어도 새 분류로 교체하고 이전 요청을 취소한다.
                return search(state: &state, recordsHistory: false)

            case .searchCancelled:
                state.searchGeneration += 1
                state.query = ""
                state.books = []
                state.isLoading = false
                state.errorMessage = nil
                state.hasSearched = false
                return .cancel(id: CancelID.search)
                
            case .searchButtonTapped:
                guard !state.isLoading else { return .none }
                return search(state: &state)

            case .refreshButtonTapped:
                guard !state.isLoading else { return .none }
                return search(state: &state, refreshing: true)

            case let .searchSucceeded(generation, books):
                guard generation == state.searchGeneration, state.isLoading else {
                    return .none
                }
                // 화면 ID가 모두 다른지 확인
                assert(Set(books.map(\.id)).count == books.count)
                
                // 제어번호가 있는 항목끼리 중복되는지 확인
                let controlNumber = books.compactMap(\.controlNumber)
                assert(Set(controlNumber).count == controlNumber.count)
                
                state.isLoading = false
                state.books = books
                return .none
                
            case let .searchFailed(generation, message):
                guard generation == state.searchGeneration, state.isLoading else {
                    return .none
                }
                state.isLoading = false
                state.errorMessage = message
                return .none
                
            case let .removeFromBasket(bookIDs):
                state.basketBooks.removeAll { book in
                    bookIDs.contains(book.id)
                }
                
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            BookDetailFeature()
        }
    }

    private func search(
        state: inout State,
        refreshing: Bool = false,
        recordsHistory: Bool = true
    ) -> Effect<Action> {
        let request = BookSearchRequest(query: state.query, category: state.category)
        state.searchGeneration += 1
        let generation = state.searchGeneration
        state.errorMessage = nil

        guard !request.query.isEmpty else {
            state.books = []
            state.isLoading = false
            state.hasSearched = false
            return .cancel(id: CancelID.search)
        }

        state.hasSearched = true
        if recordsHistory {
            state.recentQueries.removeAll { $0 == request.query }
            state.recentQueries.insert(request.query, at: 0)
            state.recentQueries = Array(state.recentQueries.prefix(20))
            searchHistoryClient.save(state.recentQueries)
        }

        if refreshing {
            bookSearchCache.remove(request)
        } else if let books = bookSearchCache.load(request) {
            state.books = books
            state.isLoading = false
            return .cancel(id: CancelID.search)
        }

        state.isLoading = true
        // 당겨서 새로고침하는 동안 ScrollView와 기존 목록을 유지한다.
        if !refreshing {
            state.books = []
        }
        return .run { [bookClient, bookSearchCache] send in
            do {
                let books = try await bookClient.search(request)
                try Task.checkCancellation()
                bookSearchCache.save(request, books)
                await send(.searchSucceeded(generation: generation, books: books))
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await send(.searchFailed(
                    generation: generation, message: error.localizedDescription
                ))
            }
        }
        .cancellable(id: CancelID.search, cancelInFlight: true)
    }

}
