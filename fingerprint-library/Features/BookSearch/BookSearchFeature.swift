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
    @ObservableState
    struct State: Equatable {
        let analyticsID: UUID = { @Dependency(\.uuid) var uuid; return uuid() }()
        var analyticsOperation: String { analyticsID.uuidString + ":" + String(searchGeneration) }
        var query: String = ""
        var category: BookSearchCategory = .all
        var searchGeneration: Int = 0
        var recentQueries: [String] = []
        var recentBooks: [Book] = []
        var recentBookInfo: [Book.ID: RecentBookInfoState] = [:]
        var recentBookInfoGeneration = 0
        @Shared(.favoriteBookKeys) var favoriteBookKeys
        var books: [Book] = []
        var cachedResultHoldings: [[String?]: [BookHolding]] = [:]
        var visibleBooks: [Book] { books.filter(category.includes) }
        var isLoading: Bool = false
        var errorMessage: String? = nil
        var hasSearched: Bool = false
        /// 검색창 명령(`/test` 등)의 결과 안내
        var commandNotice: CommandNotice?
    }

    struct CommandNotice: Equatable {
        let title: String
        let message: String
    }
    
    enum RecentBookInfoState: Equatable {
        case loading
        case loaded(BookCardLibraryInfo)
        case unavailable
        case failed
    }

    enum Action {
        case task
        case loadRecentBookInfo
        case recentBookInfoLoaded(generation: Int, Book.ID, [BookHolding])
        case recentBookInfoFailed(generation: Int, Book.ID)
        case recentBookInfoCancelled
        case recentBookDeleted(Book)
        case queryChanged(String)
        case categoryChanged(BookSearchCategory)
        case searchCancelled
        case searchButtonTapped
        case commandNoticeDismissed
        case refreshButtonTapped
        case searchSucceeded(generation: Int, books: [Book])
        case searchFailed(generation: Int, message: String)
        case favoriteButtonTapped(Book)

        case cartButtonTapped
        case favoritesButtonTapped
        case profileButtonTapped
        case bookSelected(Book)
        case searchResultsAppeared
        case favoriteMarkerTapped(HomeMapMarker)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case recommendationLayoutRequested(isExpanded: Bool)
            case kulumiCoversRequested
            case showDetail(Book, sourceFavoriteMarkerID: String?)
            case showFavoriteShelf([Book], sourceFavoriteMarkerID: String)
            case showCart
            case showFavorites
            case showMyPage
        }
    }

    @Dependency(\.bookSearchClient)
    var bookSearchClient: BookSearchClient
    @Dependency(\.analyticsClient) private var analytics

    @Dependency(\.searchHistoryClient)
    var searchHistoryClient: SearchHistoryClient

    @Dependency(\.recentSearchBooksClient)
    var recentSearchBooksClient: RecentSearchBooksClient

    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient
    @Dependency(\.bookHoldingsClient)
    var bookHoldingsClient: BookHoldingsClient



    @Dependency(\.date.now)
    var now: Date

    private nonisolated enum CancelID: Hashable, Sendable {
        case search
        case recentBookInfo
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.recentQueries = searchHistoryClient.load()
                state.recentBooks = recentSearchBooksClient.load()
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

            case let .recentBookDeleted(book):
                recentSearchBooksClient.remove(book)
                state.recentBooks = recentSearchBooksClient.load()
                state.recentBookInfo[book.id] = nil
                return .none

            case let .favoriteButtonTapped(book):
                let isFavorite = BookFavorites().toggle(book, at: now)
                analytics.record(.init(.bookFavoriteChanged, [
                    .bookRecordID: .text(AnalyticsEvent.bookID(book)),
                    .action: .text(isFavorite ? "added" : "removed")
                ]))
                return .none

            case let .favoriteMarkerTapped(marker):
                let favorites = BookFavorites()
                let activeKeys = favorites.keys.intersection(marker.bookKeys)
                let items = favorites.items.sorted { $0.favoritedAt > $1.favoritedAt }
                var seen = Set<[String?]>()
                let books = (items.map(\.book) + state.books + state.recentBooks)
                    .filter { activeKeys.contains($0.recordKey) && seen.insert($0.recordKey).inserted }
                guard let book = books.first else { return .none }
                if books.count == 1 {
                    return .send(.delegate(.showDetail(book, sourceFavoriteMarkerID: marker.id)))
                }
                return .send(.delegate(.showFavoriteShelf(books, sourceFavoriteMarkerID: marker.id)))

            case let .bookSelected(book):
                analytics.record(.init(.searchResultSelected, [
                    .bookRecordID: .text(AnalyticsEvent.bookID(book)),
                    .source: .text(state.hasSearched ? "results" : "recent")
                ]))
                recentSearchBooksClient.record(book)
                state.recentBooks = recentSearchBooksClient.load()
                return .send(.delegate(.showDetail(book, sourceFavoriteMarkerID: nil)))

            case .searchResultsAppeared:
                state.cachedResultHoldings = bookLocationCacheClient.loadRecent(Set(state.books.map(\.recordKey)))
                return .none

            case .cartButtonTapped:
                return .send(.delegate(.showCart))

            case .favoritesButtonTapped:
                return .send(.delegate(.showFavorites))

            case .profileButtonTapped:
                return .send(.delegate(.showMyPage))

            case let .queryChanged(query):
                let previousQuery = state.query.trimmingCharacters(in: .whitespacesAndNewlines)
                state.query = query
                guard previousQuery != query.trimmingCharacters(in: .whitespacesAndNewlines),
                      state.hasSearched || state.isLoading || !state.books.isEmpty
                        || state.errorMessage != nil else { return .none }
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
                case "/test":
                    // 실험 브랜치 전용: 위치 측정 모드를 켜고 끈다. 검색은 하지 않는다.
                    @Shared(.locationDiagnosticsAutoRecord) var isAutoRecording
                    let isOn = !isAutoRecording
                    $isAutoRecording.withLock { $0 = isOn }
                    state.query = ""
                    state.commandNotice = isOn
                        ? .init(title: "측정 모드를 켰어요",
                                message: "이제 길안내를 시작하면 위치 기록이 자동으로 시작되고, 안내를 끝내면 저장돼요. 다시 /test를 입력하면 꺼져요.")
                        : .init(title: "측정 모드를 껐어요", message: "다음 길안내부터는 위치를 기록하지 않아요.")
                    return .none
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
                return .merge(.cancel(id: CancelID.search), .send(.delegate(delegate)))

            case .commandNoticeDismissed:
                state.commandNotice = nil
                return .none

            case .delegate:
                return .none

            case .refreshButtonTapped:
                guard !state.isLoading else { return .none }
                return search(state: &state, refreshing: true)

            case let .searchSucceeded(generation, books):
                guard generation == state.searchGeneration, state.isLoading else {
                    return .none
                }
                assert(Set(books.map(\.id)).count == books.count)

                let controlNumber = books.compactMap(\.controlNumber)
                assert(Set(controlNumber).count == controlNumber.count)
                
                state.isLoading = false
                state.books = books
                state.cachedResultHoldings = bookLocationCacheClient.loadRecent(Set(books.map(\.recordKey)))
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
            }
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
