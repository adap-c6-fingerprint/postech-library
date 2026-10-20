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

    // 화면 전체의 현재 상태
    @ObservableState
    struct State: Equatable {
        let book: Book

        // 책 소개
        var description: BookDescription? = nil
        var isLoading = false
        var errorMessage: String? = nil
        var hasLoaded = false

        // 연관 도서
        var relatedBooksState: RelatedBooksState = .idle

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
    }

    @Dependency(\.bookDetailClient)
    var bookDetailClient

    @Dependency(\.relatedBooksClient)
    var relatedBooksClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
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
            }
        }
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case description
        case relatedBooks
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
