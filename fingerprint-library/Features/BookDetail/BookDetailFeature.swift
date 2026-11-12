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

    enum CartNotice: Equatable {
        case added
        case alreadyAdded
    }

    @ObservableState
    struct State: Equatable {
        let book: Book
        var cachedCoverURL: URL?
        @Shared(.favoriteBookKeys) var favoriteBookKeys
        var isGuidancePresented = false
        var isFavorite: Bool { favoriteBookKeys.contains(book.recordKey) }
        var sourceFavoriteMarkerID: String?

        var description: BookDescription? = nil
        var isLoading = false
        var errorMessage: String? = nil
        var hasLoaded = false

        var relatedBooksState: RelatedBooksState = .idle
        var holdingsState: HoldingsState = .idle
        var mapContext: BookDetailMapContext?
        var destinationPresentation: BookDetailDestinationPresentation?
        var destinationRouteState: DestinationRouteState = .idle
        var destinationRouteRequestID = 0

        var displayedHolding: BookHolding? {
            guard case let .loaded(holdings) = holdingsState else { return nil }
            return BookHoldingPresentation.preferred(in: holdings)
        }

        var cartNotice: CartNotice?
        @Presents var cart: BookCartFeature.State?
        var isCartLimitAlertPresented = false

        var isbn13: String? {
            BookISBN.isbn13(from: book.isbn)
        }
    }

    enum Action {
        case loadDescription
        case retryButtonTapped
        case descriptionLoaded(BookDescription?)
        case descriptionFailed(String)

        case loadRelatedBooks
        case retryRelatedBooksButtonTapped
        case relatedBooksLoaded([Book])
        case relatedBooksFailed(String)

        case loadHoldings
        case retryHoldingsButtonTapped
        case holdingsLoaded([BookHolding])
        case holdingsFailed
        case mapContextChanged(BookDetailMapContext)
        case destinationRouteLoaded(requestID: Int, BookDetailRoutePresentation)
        case destinationRouteFailed(requestID: Int)
        case loadFavorites
        case viewAppeared
        case favoriteButtonTapped
        case addToCartButtonTapped
        case cartNoticeDismissed
        case cartShortcutTapped
        case cart(PresentationAction<BookCartFeature.Action>)
        case cartLimitAlertDismissed
        case guidanceStarted
        case guidanceDismissed
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case startGuidance([Book])
        }
    }

    @Dependency(\.bookDetailClient)
    var bookDetailClient
    @Dependency(\.analyticsClient) private var analytics

    @Dependency(\.relatedBooksClient)
    var relatedBooksClient

    @Dependency(\.bookHoldingsClient)
    var bookHoldingsClient

    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient

    @Dependency(\.indoorRouteClient) var indoorRouteClient
    @Dependency(\.recentlyViewedBooksClient) var recentlyViewedBooksClient
    @Dependency(\.recentlyFoundBooksClient) var recentlyFoundBooksClient
    @Dependency(\.bookCoverClient) var bookCoverClient
    @Dependency(\.date.now) var now

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .viewAppeared:
                analytics.record(.init(.bookDetailViewed, [
                    .bookRecordID: .text(AnalyticsEvent.bookID(state.book))
                ]))
                return .none

            case .loadFavorites:
                recentlyViewedBooksClient.record(state.book)
                return .none

            case .favoriteButtonTapped:
                let isFavorite = BookFavorites().toggle(state.book, at: now)
                analytics.record(.init(.bookFavoriteChanged, [
                    .bookRecordID: .text(AnalyticsEvent.bookID(state.book)),
                    .action: .text(isFavorite ? "added" : "removed")
                ]))
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
                let previousContext = state.mapContext
                guard previousContext != context else { return .none }
                state.mapContext = context
                if previousContext?.map != context.map || previousContext?.labels != context.labels {
                    return refreshDestination(state: &state)
                }
                return refreshDestinationRoute(state: &state)

            case let .destinationRouteLoaded(requestID, summary):
                guard requestID == state.destinationRouteRequestID else { return .none }
                state.destinationRouteState = .loaded(summary)
                return .none

            case let .destinationRouteFailed(requestID):
                guard requestID == state.destinationRouteRequestID else { return .none }
                state.destinationRouteState = .unavailable
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

            case .addToCartButtonTapped:
                @Shared(.bookCart) var cartItems
                switch $cartItems.withLock({ $0.add(state.book, at: now) }) {
                case .added:
                    state.cartNotice = .added
                    analytics.record(.init(.cartBookAdded, [
                        .bookRecordID: .text(AnalyticsEvent.bookID(state.book))
                    ]))
                case .alreadyAdded:
                    state.cartNotice = .alreadyAdded
                case .limitExceeded:
                    state.isCartLimitAlertPresented = true
                    analytics.record(.init(.cartLimitBlocked, [.kind: .text("capacity")]))
                }
                return .none

            case .cartNoticeDismissed:
                state.cartNotice = nil
                return .none

            case .cartShortcutTapped:
                guard state.cart == nil else { return .none }
                state.cartNotice = nil
                state.cart = BookCartFeature.State()
                return .none

            case let .cart(.presented(.delegate(.startGuidance(books)))):
                state.cart = nil
                state.isGuidancePresented = true
                return .send(.delegate(.startGuidance(books)))

            case .cart, .delegate:
                return .none

            case .cartLimitAlertDismissed:
                state.isCartLimitAlertPresented = false

                return .none

            case .guidanceDismissed:
                state.isGuidancePresented = false
                return .none

            case .guidanceStarted:
                state.isGuidancePresented = true
                recentlyFoundBooksClient.record([state.book])
                bookCoverClient.prefetchSpines([state.book.isbn].compactMap { $0 })
                return .send(.delegate(.startGuidance([state.book])))
            }
        }
        .ifLet(\.$cart, action: \.cart) { BookCartFeature() }
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case description
        case relatedBooks
        case holdings
        case destinationRoute
    }

    private func refreshDestination(state: inout State) -> Effect<Action> {
        if case let .loaded(holdings) = state.holdingsState {
            state.destinationPresentation = BookDetailDestinationPresentation.resolve(
                holdings: holdings, context: state.mapContext
            )
        } else {
            state.destinationPresentation = nil
        }
        return refreshDestinationRoute(state: &state)
    }

    private func refreshDestinationRoute(state: inout State) -> Effect<Action> {
        state.destinationRouteRequestID += 1
        let requestID = state.destinationRouteRequestID
        let cancel: Effect<Action> = .cancel(id: CancelID.destinationRoute)
        guard case .loaded = state.holdingsState else {
            state.destinationRouteState = state.holdingsState == .failed ? .unavailable : .idle
            return cancel
        }
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

    private func loadRelatedBooks(
        state: inout State
    ) -> Effect<Action> {
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
