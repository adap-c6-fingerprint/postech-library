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
    @ObservableState
    struct State: Equatable {
        let book: Book
        var description: BookDescription? = nil
        var isLoading = false
        var errorMessage: String? = nil
        var hasLoaded = false

        var isbn13: String? { BookISBN.isbn13(from: book.isbn) }
    }

    enum Action {
        case loadDescription
        case retryButtonTapped
        case descriptionLoaded(BookDescription?)
        case descriptionFailed(String)
    }

    @Dependency(\.bookDetailClient)
    var bookDetailClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .loadDescription:
                guard !state.hasLoaded else { return .none }
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
            }
        }
    }

    private nonisolated enum CancelID: Hashable, Sendable { case description }

    private func loadDescription(state: inout State) -> Effect<Action> {
        guard !state.isLoading else { return .none }
        state.description = nil
        state.errorMessage = nil
        guard let isbn13 = state.isbn13 else {
            state.hasLoaded = true
            state.errorMessage = "조회 가능한 ISBN 정보가 없어 책 소개를 불러올 수 없어요."
            return .none
        }
        state.isLoading = true
        return .run { [bookDetailClient] send in
            do {
                let description = try await bookDetailClient.fetchDescription(isbn13)
                try Task.checkCancellation()
                await send(.descriptionLoaded(description))
            } catch {
                guard !Task.isCancelled else { return }
                await send(.descriptionFailed("책 소개를 불러오지 못했어요. 다시 시도해 주세요."))
            }
        }
        .cancellable(id: CancelID.description, cancelInFlight: true)
    }
}
