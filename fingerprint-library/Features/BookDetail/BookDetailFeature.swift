//
//  BookDetailFeature.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/18/26.
//

import Foundation
import os
import ComposableArchitecture

@Reducer
struct BookDetailFeature {
    enum CartNotice: Equatable {
        case added
        case alreadyAdded
    }

    @ObservableState
    struct State: Equatable, Identifiable {
        let book: Book
        var id: Book.ID { book.id }
        var cachedCoverURL: URL?
        @Shared(.favoriteBookKeys) var favoriteBookKeys
        var isGuidancePresented = false
        var isFavorite: Bool { favoriteBookKeys.contains(book.recordKey) }
        var sourceFavoriteMarkerID: String?

        var description: BookDescription? = nil
        var isLoading = false
        var errorMessage: String? = nil
        var hasLoaded = false

        var holdingsState: BookHoldingsState = .idle
        var mapContext: BookDetailMapContext?
        var destinationPresentation: BookDetailDestinationPresentation?

        var displayedHolding: BookHolding? {
            guard case let .loaded(holdings) = holdingsState else { return nil }
            return BookHolding.preferred(in: holdings)
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


        case loadHoldings
        case retryHoldingsButtonTapped
        case holdingsLoaded([BookHolding])
        case holdingsFailed
        case mapContextChanged(BookDetailMapContext)
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


    @Dependency(\.bookHoldingsClient)
    var bookHoldingsClient

    @Dependency(\.bookLocationCacheClient) var bookLocationCacheClient

    @Dependency(\.recentlyViewedBooksClient) var recentlyViewedBooksClient
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
                MapPerformanceSignpost.signposter.emitEvent("HoldingsLoaded")
                state.holdingsState = .loaded(holding)
                bookLocationCacheClient.record(state.book, holding)
                refreshDestination(state: &state)
                return .none

            case .holdingsFailed:
                state.holdingsState = .failed("소장 정보를 불러오지 못했어요.")
                refreshDestination(state: &state)
                return .none

            case let .mapContextChanged(context):
                guard state.mapContext != context else { return .none }
                MapPerformanceSignpost.signposter.emitEvent("MapContextChanged")
                state.mapContext = context
                refreshDestination(state: &state)
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
                bookCoverClient.prefetchSpines([state.book.isbn].compactMap { $0 })
                return .send(.delegate(.startGuidance([state.book])))
            }
        }
        .ifLet(\.$cart, action: \.cart) { BookCartFeature() }
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case description
        case holdings
    }

    private func refreshDestination(state: inout State) {
        guard state.mapContext != nil, case let .loaded(holdings) = state.holdingsState else {
            state.destinationPresentation = nil
            return
        }
        state.destinationPresentation = BookDetailDestinationPresentation.resolve(
            holdings: holdings, context: state.mapContext
        )
    }

    private func loadHoldings(state: inout State) -> Effect<Action> {
        guard state.holdingsState != .loading else { return .none }
        guard let recordID = BookHoldingsClient.recordID(for: state.book) else {
            state.holdingsState = .failed(BookHoldingsError.invalidRecordID.localizedDescription)
            refreshDestination(state: &state)
            return .none
        }
        state.holdingsState = .loading
        state.destinationPresentation = nil
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
        return effect
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
}
