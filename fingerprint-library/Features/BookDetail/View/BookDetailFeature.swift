//
//  BookDetailFeature.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/18/26.
//

import Foundation
import ComposableArchitecture

@Reducer
struct BookDetailFeature {
    // 연관 도서 조회의 가능한 상태
    enum RelatedBooksState: Equatable {
        case idle
        case loading
        case loaded([Book])
        case failed(String)
    }

    enum HoldingsState: Equatable {
        case idle
        case loading
        case loaded([BookHolding])
        case failed
    }

    enum DestinationRouteState: Equatable {
        case idle
        case loading
        case loaded(BookDetailRoutePresentation)
        case unavailable
    }

    enum BasketNotice: Equatable {
        case added
        case alreadyAdded
    }

    // 화면 전체의 현재 상태
    @ObservableState
    struct State: Equatable {
        let book: Book
        var isFavorite = false
        @Presents var shelfMap: BookShelfMapFeature.State?

        // 책 소개
        var description: BookDescription? = nil
        var isLoading = false
        var errorMessage: String? = nil
        var hasLoaded = false

        // 연관 도서
        var relatedBooksState: RelatedBooksState = .idle
        var holdingsState: HoldingsState = .idle
        var routeSummary: BookRouteSummary = .mock
        var mapContext: BookDetailMapContext?
        var destinationPresentation: BookDetailDestinationPresentation?
        var destinationRouteState: DestinationRouteState = .idle
        var destinationRouteRequestID = 0

        var displayedHolding: BookHolding? {
            guard case let .loaded(holdings) = holdingsState else { return nil }
            return BookHoldingPresentation.preferred(in: holdings)
        }

        // 장바구니
        var basketNotice: BasketNotice?
        @Presents var basket: BookBasketFeature.State?
        var isBasketLimitAlertPresented = false

        var isbn13: String? {
            BookISBN.isbn13(from: book.isbn)
        }
    }

    enum Action {
        // 책 소개
        case loadDescription
        case retryButtonTapped
        case descriptionLoaded(BookDescription?)
        case descriptionFailed(String)

        // 연관 도서
        case loadRelatedBooks
        case retryRelatedBooksButtonTapped
        case relatedBooksLoaded([Book])
        case relatedBooksFailed(String)

        case directionsButtonTapped
        case shelfMap(PresentationAction<BookShelfMapFeature.Action>)
        case loadHoldings
        case retryHoldingsButtonTapped
        case holdingsLoaded([BookHolding])
        case holdingsFailed
        case routeSummaryUpdated(BookRouteSummary)
        case mapContextChanged(BookDetailMapContext)
        case destinationRouteLoaded(requestID: Int, BookDetailRoutePresentation)
        case destinationRouteFailed(requestID: Int)
        case loadFavorites
        case favoriteButtonTapped
        case addToBasketButtonTapped
        case basketNoticeDismissed
        case basketShortcutTapped
        case basket(PresentationAction<BookBasketFeature.Action>)
        case basketLimitAlertDismissed
        case startGuidanceButtonTapped
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case startGuidance(Book)
            case favoritesChanged(Set<[String?]>)
        }
    }

    @Dependency(\.bookDetailClient)
    var bookDetailClient

    @Dependency(\.relatedBooksClient)
    var relatedBooksClient

    @Dependency(\.bookHoldingsClient)
    var bookHoldingsClient

    @Dependency(\.bookFavoritesClient)
    var bookFavoritesClient
    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient

    @Dependency(\.indoorRouteClient) var indoorRouteClient
    @Dependency(\.bookBasketClient) var bookBasketClient
    @Dependency(\.recentlyViewedBooksClient) var recentlyViewedBooksClient
    // ✅ 상세 화면에 들어간 책을 '조회한 책'으로 기록한다. (Q5)
    @Dependency(\.date.now) var now

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadFavorites:
                state.isFavorite = bookFavoritesClient.load().contains(state.book.recordKey)
                recentlyViewedBooksClient.record(state.book)
                // ✅ 상세 화면이 뜰 때 한 번 보내는 액션이므로 여기서 조회 기록을 남긴다.
                return .none

            case .favoriteButtonTapped:
                // 다른 화면에서 추가한 찜도 보존하도록 최신 저장 목록에서 변경한다.
                var keys = bookFavoritesClient.load()
                let key = state.book.recordKey
                if keys.contains(key) {
                    keys.remove(key)
                } else {
                    keys.insert(key)
                    bookFavoritesClient.record(state.book, now)
                    // 찜 목록 화면에서 날짜별로 보여 주도록 책 정보와 찜한 시각을 남긴다.
                }
                state.isFavorite = keys.contains(key)
                bookFavoritesClient.save(keys)
                return .send(.delegate(.favoritesChanged(keys)))

            case .directionsButtonTapped:
                var destination = BookShelfMapFeature.State(book: state.book)
                // 상세에서 받은 전체 소장처를 지도에 전달해 위치 후보를 보존한다.
                if case let .loaded(holdings) = state.holdingsState {
                    destination.holdings[state.book.id] = .loaded(holdings)
                }
                state.shelfMap = destination
                return .none

            case .shelfMap:
                return .none

            case .loadHoldings:
                guard case .idle = state.holdingsState else { return .none }
                return loadHoldings(state: &state)

            case .retryHoldingsButtonTapped:
                return loadHoldings(state: &state)

            case let .holdingsLoaded(holding):
                state.holdingsState = .loaded(holding)
                bookLocationCacheClient.record(state.book, holding)
                return state.mapContext == nil ? .none : refreshDestination(state: &state)

            case .holdingsFailed:
                state.holdingsState = .failed
                return state.mapContext == nil ? .none : refreshDestination(state: &state)

            case let .mapContextChanged(context):
                guard state.mapContext != context else { return .none }
                state.mapContext = context
                return refreshDestination(state: &state)

            case let .destinationRouteLoaded(requestID, summary):
                guard requestID == state.destinationRouteRequestID else { return .none }
                state.destinationRouteState = .loaded(summary)
                return .none

            case let .destinationRouteFailed(requestID):
                guard requestID == state.destinationRouteRequestID else { return .none }
                state.destinationRouteState = .unavailable
                return .none

            case let .routeSummaryUpdated(summary):
                state.routeSummary = summary
                return .none

            case .loadDescription:
                guard !state.hasLoaded else {
                    return .none
                }

                return loadDescription(state: &state)

            case .retryButtonTapped:
                return loadDescription(state: &state)

            case let .descriptionLoaded(description):
                state.isLoading = false
                state.hasLoaded = true
                state.description = description
                state.errorMessage = nil

                return .none

            case let .descriptionFailed(message):
                state.isLoading = false
                state.hasLoaded = true
                state.errorMessage = message

                return .none

            case .loadRelatedBooks:
                guard case .idle = state.relatedBooksState else {
                    return .none
                }

                return loadRelatedBooks(state: &state)

            case .retryRelatedBooksButtonTapped:
                return loadRelatedBooks(state: &state)

            case let .relatedBooksLoaded(books):
                state.relatedBooksState = .loaded(books)

                return .none

            case let .relatedBooksFailed(message):
                state.relatedBooksState = .failed(message)

                return .none

            case .addToBasketButtonTapped:
                switch bookBasketClient.add(state.book, at: now) {
                case .added:
                    state.basketNotice = .added
                case .alreadyAdded:
                    state.basketNotice = .alreadyAdded
                case .limitExceeded:
                    state.isBasketLimitAlertPresented = true
                }
                return .none

            case .basketNoticeDismissed:
                state.basketNotice = nil
                return .none

            case .basketShortcutTapped:
                // 시스템 얼럿이 버튼 액션보다 먼저 표시 상태를 초기화할 수 있다.
                guard state.basket == nil else { return .none }
                state.basketNotice = nil
                state.basket = BookBasketFeature.State()
                return .none

            case .basket:
                return .none

            case .basketLimitAlertDismissed:
                state.isBasketLimitAlertPresented = false

                return .none

            case .startGuidanceButtonTapped:
                // 장바구니를 거치지 않고 이 책 1권으로 길안내를 시작한다.
                return .send(.delegate(.startGuidance(state.book)))

            case .delegate:
                return .none
            }
        }
        .ifLet(\.$shelfMap, action: \.shelfMap) { BookShelfMapFeature() }
        .ifLet(\.$basket, action: \.basket) { BookBasketFeature() }
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case description
        case relatedBooks
        case holdings
        case destinationRoute
    }

    private func refreshDestination(state: inout State) -> Effect<Action> {
        state.destinationRouteRequestID += 1
        let requestID = state.destinationRouteRequestID
        let cancel: Effect<Action> = .cancel(id: CancelID.destinationRoute)
        guard case let .loaded(holdings) = state.holdingsState else {
            state.destinationPresentation = nil
            state.destinationRouteState = state.holdingsState == .failed ? .unavailable : .idle
            return cancel
        }
        state.destinationPresentation = BookDetailDestinationPresentation.resolve(
            holdings: holdings, context: state.mapContext
        )
        guard let destination = state.destinationPresentation,
              ShelfOverlapPolicy().allows(destination.shelves),
              let context = state.mapContext, let navigation = context.navigation,
              navigation.shelves.mode == .library,
              let position = context.position, position.isRecent(at: now) else {
            state.destinationRouteState = .unavailable
            return cancel
        }
        let targets = destination.shelves.compactMap { shelf in
            navigation.shelves.destinations.first {
                $0.key.value == shelf.fixtureNumber && $0.mapElementID == shelf.mapElementID && $0.floorID == shelf.floorID
            }
        }
        guard targets.count == destination.shelves.count else {
            state.destinationRouteState = .unavailable
            return cancel
        }
        state.destinationRouteState = .loading
        let requests = targets.map {
            IndoorRouteRequest(navigation: navigation, start: position, destination: $0.key, preference: context.preference)
        }
        return .run { [indoorRouteClient] send in
            var best: BookDetailRoutePresentation?
            var bestDistance = Double.infinity
            for request in requests {
                do {
                    try Task.checkCancellation()
                    guard case let .route(route) = try await indoorRouteClient.search(request),
                          route.destination == request.destination,
                          let summary = BookDetailRoutePresentation(route: route) else { continue }
                    if route.distanceMeters < bestDistance {
                        bestDistance = route.distanceMeters
                        best = summary
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                }
            }
            guard !Task.isCancelled else { return }
            if let best { await send(.destinationRouteLoaded(requestID: requestID, best)) }
            else { await send(.destinationRouteFailed(requestID: requestID)) }
        }
        .cancellable(id: CancelID.destinationRoute, cancelInFlight: true)
    }

    private func loadHoldings(state: inout State) -> Effect<Action> {
        guard state.holdingsState != .loading else { return .none }
        guard let recordID = BookHoldingsClient.recordID(for: state.book) else {
            state.holdingsState = .failed
            return state.mapContext == nil ? .none : refreshDestination(state: &state)
        }
        state.holdingsState = .loading
        if state.mapContext != nil {
            state.destinationPresentation = nil
            state.destinationRouteState = .idle
            state.destinationRouteRequestID += 1
        }
        let effect: Effect<Action> = .run { [bookHoldingsClient] send in
            do {
                let holding = try await bookHoldingsClient.fetch(recordID)
                try Task.checkCancellation()
                await send(.holdingsLoaded(holding))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.holdingsFailed)
            }
        }
        .cancellable(id: CancelID.holdings, cancelInFlight: true)
        return .merge(.cancel(id: CancelID.destinationRoute), effect)
    }

    // 책 소개 조회
    private func loadDescription(
        state: inout State
    ) -> Effect<Action> {
        guard !state.isLoading else {
            return .none
        }

        state.description = nil
        state.errorMessage = nil

        guard let isbn13 = state.isbn13 else {
            state.hasLoaded = true
            state.errorMessage =
                "조회 가능한 ISBN 정보가 없어 책 소개를 불러올 수 없어요."

            return .none
        }

        state.isLoading = true

        return .run { [bookDetailClient] send in
            do {
                let description =
                    try await bookDetailClient.fetchDescription(isbn13)

                try Task.checkCancellation()

                await send(.descriptionLoaded(description))
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await send(
                    .descriptionFailed(
                        "책 소개를 불러오지 못했어요. 다시 시도해 주세요."
                    )
                )
            }
        }
        .cancellable(
            id: CancelID.description,
            cancelInFlight: true
        )
    }

    // 연관 도서 조회
    private func loadRelatedBooks(
        state: inout State
    ) -> Effect<Action> {
        // 이미 조회 중이면 중복 요청하지 않아요.
        if case .loading = state.relatedBooksState {
            return .none
        }

        guard let isbn13 = state.isbn13 else {
            state.relatedBooksState = .failed(
                "조회 가능한 ISBN 정보가 없어 연관 도서를 불러올 수 없어요."
            )

            return .none
        }

        state.relatedBooksState = .loading

        return .run { [relatedBooksClient] send in
            do {
                let books = try await relatedBooksClient.fetch(isbn13)

                try Task.checkCancellation()

                await send(.relatedBooksLoaded(books))
            } catch {
                guard !Task.isCancelled else {
                    return
                }

                await send(
                    .relatedBooksFailed(
                        "연관 도서를 불러오지 못했어요. 다시 시도해 주세요."
                    )
                )
            }
        }
        .cancellable(
            id: CancelID.relatedBooks,
            cancelInFlight: true
        )
    }
}
