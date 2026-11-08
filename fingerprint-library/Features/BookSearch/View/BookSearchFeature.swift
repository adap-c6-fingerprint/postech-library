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
        let analyticsID = UUID()
        var analyticsOperation: String { analyticsID.uuidString + ":" + String(searchGeneration) }
        var query: String = ""
        var category: BookSearchCategory = .all
        var searchGeneration: Int = 0
        // 검색어 기록은 추천 입력으로 유지하고, 화면에는 선택한 도서를 표시한다.
        var recentQueries: [String] = []
        var recentBooks: [Book] = []
        var recentBookInfo: [Book.ID: RecentBookInfoState] = [:]
        var recentBookInfoGeneration = 0
        var favoriteBookKeys: Set<[String?]> = []
        var books: [Book] = []
        // 원본 결과를 유지해 탭 전환 시 캐시 조회나 네트워크 요청 없이 필터링한다.
        var visibleBooks: [Book] { books.filter(category.includes) }
        var isLoading: Bool = false
        var errorMessage: String? = nil
        var hasSearched: Bool = false
        
        var cartBooks: [Book] = []
        var isCartLimitAlertPresented = false
        @Presents var detail: BookDetailFeature.State?
        @Presents var favoriteShelf: BookShelfMapFeature.State?
        @Presents var cart: BookCartFeature.State?
        @Presents var favorites: BookFavoritesFeature.State?
        @Presents var shelfMap: BookShelfMapFeature.State?
        @Presents var myPage: MyPageFeature.State?
    }
    
    enum RecentBookInfoState: Equatable {
        case loading
        case loaded(BookCardLibraryInfo)
        case unavailable
        case failed
    }

    // 이 기능에서 발생할 수 있는 이벤트
    enum Action {
        case task
        case loadRecentBookInfo
        case recentBookInfoLoaded(generation: Int, Book.ID, [BookHolding])
        case recentBookInfoFailed(generation: Int, Book.ID)
        case recentBookInfoCancelled
        case queryChanged(String)
        case categoryChanged(BookSearchCategory)
        case searchCancelled
        case searchButtonTapped
        case refreshButtonTapped
        case searchSucceeded(generation: Int, books: [Book])
        case searchFailed(generation: Int, message: String)
        case favoriteButtonTapped(Book)
        
        case addToCart(Book)
        case cartButtonTapped
        case favoritesButtonTapped
        case favorites(PresentationAction<BookFavoritesFeature.Action>)
        case profileButtonTapped
        case myPage(PresentationAction<MyPageFeature.Action>)
        case cart(PresentationAction<BookCartFeature.Action>)
        case cartLimitAlertDismissed
        case removeFromCart(Set<Book.ID>)
        case bookSelected(Book)
        case favoriteMarkerTapped(HomeMapMarker)
        case favoriteShelf(PresentationAction<BookShelfMapFeature.Action>)
        case detail(PresentationAction<BookDetailFeature.Action>)
        case directionsButtonTapped(Book)
        case cartDirectionsButtonTapped(Set<Book.ID>)
        case shelfMap(PresentationAction<BookShelfMapFeature.Action>)
        case delegate(Delegate)

        enum Delegate {
            case recommendationLayoutRequested(isExpanded: Bool)
            case kulumiCoversRequested
        }
    }
    
    // 검색에 사용할 BookClient 값
    @Dependency(\.bookSearchClient)
    var bookSearchClient: BookSearchClient
    @Dependency(\.analyticsClient) private var analytics

    @Dependency(\.searchHistoryClient)
    var searchHistoryClient: SearchHistoryClient

    @Dependency(\.recentSearchBooksClient)
    var recentSearchBooksClient: RecentSearchBooksClient

    @Dependency(\.bookHoldingsClient)
    var bookHoldingsClient: BookHoldingsClient

    @Dependency(\.bookFavoritesClient)
    var bookFavoritesClient: BookFavoritesClient

    @Dependency(\.bookCartClient)
    var bookCartClient: BookCartClient

    @Dependency(\.date.now)
    var now: Date

    private nonisolated enum CancelID: Hashable, Sendable {
        case search
        case recentBookInfo
    }
    
    // Action을 받아 State를 바꾸고, 필요한 Effect를 반환
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.recentQueries = searchHistoryClient.load()
                state.recentBooks = recentSearchBooksClient.load()
                state.favoriteBookKeys = bookFavoritesClient.load()
                state.cartBooks = bookCartClient.load().map(\.book)
                return .none

            case .loadRecentBookInfo:
                return loadRecentBookInfo(state: &state)

            case let .recentBookInfoLoaded(generation, bookID, holdings):
                guard state.recentBookInfoGeneration == generation,
                      state.recentBooks.contains(where: { $0.id == bookID }) else { return .none }
                state.recentBookInfo[bookID] = .loaded(.init(holdings: holdings))
                return .none

            case let .recentBookInfoFailed(generation, bookID):
                guard state.recentBookInfoGeneration == generation,
                      state.recentBooks.contains(where: { $0.id == bookID }) else { return .none }
                state.recentBookInfo[bookID] = .failed
                return .none

            case .recentBookInfoCancelled:
                state.recentBookInfoGeneration += 1
                return .cancel(id: CancelID.recentBookInfo)

            case let .favoriteButtonTapped(book):
                state.favoriteBookKeys = bookFavoritesClient.load()
                let key = book.recordKey
                if state.favoriteBookKeys.contains(key) {
                    state.favoriteBookKeys.remove(key)
                } else {
                    state.favoriteBookKeys.insert(key)
                    bookFavoritesClient.record(book, now)
                    // 찜 목록 화면에서 날짜별로 보여 주도록 책 정보와 찜한 시각을 남긴다.
                }
                bookFavoritesClient.save(state.favoriteBookKeys)
                analytics.record(.init(.bookFavoriteChanged, [
                    .bookRecordID: .text(AnalyticsEvent.bookID(book)),
                    .action: .text(state.favoriteBookKeys.contains(key) ? "added" : "removed")
                ]))
                if let detailBook = state.detail?.book {
                    let isFavorite = state.favoriteBookKeys.contains(detailBook.recordKey)
                    state.detail?.isFavorite = isFavorite
                }
                return .none

            case let .favoriteMarkerTapped(marker):
                // 마커가 만들어진 뒤 찜이 바뀌었을 수 있으므로 현재 저장 목록으로 다시 확인한다.
                let activeKeys = bookFavoritesClient.load().intersection(marker.bookKeys)
                let items = bookFavoritesClient.loadItems().sorted { $0.favoritedAt > $1.favoritedAt }
                var seen = Set<[String?]>()
                let books = (items.map(\.book) + state.books + state.recentBooks)
                    .filter { activeKeys.contains($0.recordKey) && seen.insert($0.recordKey).inserted }
                guard let book = books.first else { return .none }
                if books.count == 1 {
                    state.detail = BookDetailFeature.State(book: book, isFavorite: true)
                    state.detail?.sourceFavoriteMarkerID = marker.id
                } else {
                    state.favoriteShelf = BookShelfMapFeature.State(previewing: books)
                    state.favoriteShelf?.sourceFavoriteMarkerID = marker.id
                }
                return .none

            case .favoriteShelf:
                return .none

            case let .bookSelected(book):
                analytics.record(.init(.searchResultSelected, [
                    .bookRecordID: .text(AnalyticsEvent.bookID(book)),
                    .source: .text(state.hasSearched ? "results" : "recent")
                ]))
                recentSearchBooksClient.record(book)
                state.recentBooks = recentSearchBooksClient.load()
                state.favoriteBookKeys = bookFavoritesClient.load()
                state.detail = BookDetailFeature.State(
                    book: book, isFavorite: state.favoriteBookKeys.contains(book.recordKey)
                )
                return .none

            case .detail(.presented(.addToCartButtonTapped)),
                 .detail(.presented(.cart(.presented(.removeConfirmed)))):
                state.cartBooks = bookCartClient.load().map(\.book)
                return .none

            case let .detail(.presented(.delegate(.startGuidance(book)))):
                state.shelfMap = BookShelfMapFeature.State(book: book)
                return .none

            case let .detail(.presented(.delegate(.favoritesChanged(keys)))):
                state.favoriteBookKeys = keys
                return .none

            case .detail(.dismiss):
                // 상세 화면에서 담은 책을 검색 화면의 바로가기 권수에 반영한다.
                state.cartBooks = bookCartClient.load().map(\.book)
                return .none

            case .cartButtonTapped:
                state.cart = BookCartFeature.State()
                return .none

            case .cart(.dismiss), .cart(.presented(.removeConfirmed)):
                state.cartBooks = bookCartClient.load().map(\.book)
                return .none

            case let .cart(.presented(.delegate(.startGuidance(books)))):
                state.shelfMap = BookShelfMapFeature.State(books: books)
                return .none

            case .favoritesButtonTapped:
                state.favorites = BookFavoritesFeature.State()
                return .none

            case let .favorites(.presented(.delegate(.favoritesChanged(keys)))):
                state.favoriteBookKeys = keys
                // 지도 찜 표시와 검색 결과 하트가 찜 목록 화면에서 지운 내용을 따라가게 한다.
                return .none

            case .favorites(.presented(.delegate(.cartChanged))),
                 .favorites(.presented(.cart(.presented(.removeConfirmed)))),
                 .favorites(.dismiss):
                state.cartBooks = bookCartClient.load().map(\.book)
                return .none

            case .profileButtonTapped:
                state.myPage = MyPageFeature.State()
                return .none

            case .detail, .cart, .favorites, .myPage:
                return .none

            case .directionsButtonTapped(let book):
                state.shelfMap = BookShelfMapFeature.State(book: book)
                return .none

            case .cartDirectionsButtonTapped(let bookIDs):
                let books = state.cartBooks.filter { bookIDs.contains($0.id) }
                guard books.count == bookIDs.count,
                      let shelfMap = BookShelfMapFeature.State(books: books) else { return .none }
                state.shelfMap = shelfMap
                return .none

            case .shelfMap:
                return .none
                
            case let .addToCart(book):
                let result = bookCartClient.add(book, at: now)
                if result == .added {
                    analytics.record(.init(.cartBookAdded, [.bookRecordID: .text(AnalyticsEvent.bookID(book))]))
                }
                state.cartBooks = bookCartClient.load().map(\.book)
                if result == .limitExceeded {
                    analytics.record(.init(.cartLimitBlocked, [.kind: .text("capacity")]))
                    state.isCartLimitAlertPresented = true
                }
                return .none

            case .cartLimitAlertDismissed:
                state.isCartLimitAlertPresented = false
                return .none

            case let .queryChanged(query):
                let previousQuery = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
                state.query = query
                guard previousQuery != query.trimmingCharacters(in: .whitespacesAndNewlines),
                      state.hasSearched || state.isLoading || !state.books.isEmpty
                        || state.errorMessage != nil else { return .none }
                // 새 입력에는 이전 검색의 결과나 늦게 도착한 응답을 표시하지 않는다.
                recordCancellation(state)
                state.searchGeneration += 1
                state.books = []
                state.isLoading = false
                state.errorMessage = nil
                state.hasSearched = false
                return .cancel(id: CancelID.search)

            case let .categoryChanged(category):
                guard state.category != category else { return .none }
                state.category = category
                return .none

            case .searchCancelled:
                recordCancellation(state)
                state.searchGeneration += 1
                state.query = ""
                state.books = []
                state.isLoading = false
                state.errorMessage = nil
                state.hasSearched = false
                return .cancel(id: CancelID.search)
                
            case .searchButtonTapped:
                let command = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
                let delegate: Action.Delegate
                switch command {
                case "/ver1", "/ver2":
                    delegate = .recommendationLayoutRequested(isExpanded: command == "/ver2")
                case "/kulumi":
                    delegate = .kulumiCoversRequested
                default:
                    guard !state.isLoading else { return .none }
                    return search(state: &state)
                }

                recordCancellation(state)
                state.searchGeneration += 1
                state.query = ""
                state.books = []
                state.isLoading = false
                state.errorMessage = nil
                state.hasSearched = false
                // 숨겨진 명령은 검색 API나 추천 입력용 검색 기록에 보내지 않는다.
                return .merge(.cancel(id: CancelID.search), .send(.delegate(delegate)))

            case .delegate:
                return .none

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
                analytics.record(.init(.searchCompleted, [
                    .operationID: .text(state.analyticsOperation), .resultCount: .integer(books.count),
                    .cacheHit: .flag(false)
                ]))
                return .none
                
            case let .searchFailed(generation, message):
                guard generation == state.searchGeneration, state.isLoading else {
                    return .none
                }
                state.isLoading = false
                state.errorMessage = message
                analytics.record(.init(.searchFailed, [
                    .operationID: .text(state.analyticsOperation), .errorCode: .text("request_failed")
                ]))
                return .none
                
            case let .removeFromCart(bookIDs):
                let removedKeys = Set(
                    state.cartBooks.filter { bookIDs.contains($0.id) }.map(\.recordKey)
                )
                state.cartBooks.removeAll { book in
                    bookIDs.contains(book.id)
                }
                let stored = bookCartClient.load()
                let remaining = stored.filter { !removedKeys.contains($0.book.recordKey) }
                bookCartClient.save(remaining)
                if stored.count > remaining.count {
                    analytics.record(.init(.cartBooksRemoved, [
                        .removedCount: .integer(stored.count - remaining.count)
                    ]))
                }

                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) {
            BookDetailFeature()
        }
        .ifLet(\.$favoriteShelf, action: \.favoriteShelf) {
            BookShelfMapFeature()
        }
        .ifLet(\.$cart, action: \.cart) {
            BookCartFeature()
        }
        .ifLet(\.$favorites, action: \.favorites) {
            BookFavoritesFeature()
        }
        .ifLet(\.$shelfMap, action: \.shelfMap) {
            BookShelfMapFeature()
        }
        .ifLet(\.$myPage, action: \.myPage) {
            MyPageFeature()
        }
    }

    private func loadRecentBookInfo(state: inout State) -> Effect<Action> {
        state.recentBookInfoGeneration += 1
        let generation = state.recentBookInfoGeneration
        state.recentBookInfo = [:]
        var requests: [(bookID: Book.ID, recordID: String)] = []
        for book in state.recentBooks {
            guard let recordID = BookHoldingsClient.recordID(for: book) else {
                state.recentBookInfo[book.id] = .unavailable
                continue
            }
            state.recentBookInfo[book.id] = .loading
            requests.append((book.id, recordID))
        }
        return .run { [bookHoldingsClient, requests] send in
            // 도서 목록은 즉시 표시하고, 소장 정보는 최대 3권씩 조회한다.
            for start in stride(from: 0, to: requests.count, by: 3) {
                guard !Task.isCancelled else { return }
                await withTaskGroup(of: Void.self) { group in
                    for request in requests[start..<min(start + 3, requests.count)] {
                        group.addTask {
                            do {
                                let holdings = try await bookHoldingsClient.fetch(request.recordID)
                                try Task.checkCancellation()
                                await send(.recentBookInfoLoaded(generation: generation, request.bookID, holdings))
                            } catch {
                                guard !Task.isCancelled else { return }
                                await send(.recentBookInfoFailed(generation: generation, request.bookID))
                            }
                        }
                    }
                }
            }
        }
        .cancellable(id: CancelID.recentBookInfo, cancelInFlight: true)
    }

    private func search(
        state: inout State,
        refreshing: Bool = false,
        recordsHistory: Bool = true
    ) -> Effect<Action> {
        // 자료 유형은 화면 필터다. 검색·새로고침·캐시는 항상 같은 전체 결과를 사용한다.
        let request = BookSearchRequest(query: state.query, category: .all)
        recordCancellation(state)
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
        analytics.record(.init(.searchSubmitted, [.operationID: .text(state.analyticsOperation)]))
        if recordsHistory {
            state.recentQueries.removeAll { $0 == request.query }
            state.recentQueries.insert(request.query, at: 0)
            state.recentQueries = Array(state.recentQueries.prefix(20))
            searchHistoryClient.save(state.recentQueries)
        }
        
        if !refreshing, let books = bookSearchClient.cached(request) {
            state.books = books
            state.isLoading = false
            analytics.record(.init(.searchCompleted, [
                .operationID: .text(state.analyticsOperation), .resultCount: .integer(books.count),
                .cacheHit: .flag(true)
            ]))
            return .cancel(id: CancelID.search)
        }

        state.isLoading = true
        // 당겨서 새로고침하는 동안 ScrollView와 기존 목록을 유지한다.
        if !refreshing {
            state.books = []
        }
        
        return .run { [bookSearchClient] send in
            do {
                let books = try await bookSearchClient.search(request, refreshing)
                try Task.checkCancellation()
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

    private func recordCancellation(_ state: State) {
        guard state.isLoading else { return }
        analytics.record(.init(.searchCancelled, [.operationID: .text(state.analyticsOperation)]))
    }
}
