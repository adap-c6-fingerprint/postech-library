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

    @ObservableState
    struct State: Equatable {
        let book: Book
        var isFavorite = false
        @Presents var shelfMap: BookShelfMapFeature.State?

        // MARK: - 책 소개
        var description: BookDescription? = nil
        var isLoading = false
        var errorMessage: String? = nil
        var hasLoaded = false

        // MARK: - 연관 도서
        var relatedBooksState: RelatedBooksState = .idle

        // MARK: - 소장 정보와 경로 요약
        var holdingsState: HoldingsState = .idle
        var routeSummary: BookRouteSummary = .mock

        var displayedHolding: BookHolding? {
            guard case let .loaded(holdings) = holdingsState else { return nil }
            return BookHoldingPresentation.preferred(in: holdings)
        }

        // MARK: - 장바구니
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
        case loadFavorites
        case favoriteButtonTapped
        case addToBasketButtonTapped
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

    @Dependency(\.bookBasketClient) var bookBasketClient
    @Dependency(\.date.now) var now

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadFavorites:
                state.isFavorite = bookFavoritesClient.load().contains(state.book.recordKey)
                return .none

            case .favoriteButtonTapped:
                let keys = bookFavoritesClient.toggle(state.book)
                let key = state.book.recordKey
                state.isFavorite = keys.contains(key)
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
                return .none

            case .holdingsFailed:
                state.holdingsState = .failed
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
                // 이미 한도까지 담겨 있으면 저장하지 않고 한도 팝업을 띄운다.
                if bookBasketClient.add(state.book, at: now) == .limitExceeded {
                    state.isBasketLimitAlertPresented = true
                }

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
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case description
        case relatedBooks
        case holdings
    }

    private func loadHoldings(state: inout State) -> Effect<Action> {
        guard state.holdingsState != .loading else { return .none }
        guard let recordID = BookHoldingsClient.recordID(for: state.book) else {
            state.holdingsState = .failed
            return .none
        }
        state.holdingsState = .loading
        return .run { [bookHoldingsClient] send in
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
