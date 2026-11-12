//
//  RecentlyFoundBookFeature.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  마이페이지에서 navigate되는 최근 찾은 책 화면 feature
//  마이페이지의 책장 카드도 같은 State·로직을 쓴다.
//

import ComposableArchitecture
import Foundation
import UIKit

@Reducer
struct RecentlyFoundBookFeature {
    enum SpinePhase: Equatable {
        case loading
        case loaded(UIImage)
        case unavailable
    }

    @ObservableState
    struct State: Equatable {
        var books: [Book] = []
        var spines: [Book.ID: SpinePhase] = [:]
    }

    enum Action {
        case task
        case spineLoaded(Book.ID, UIImage?)
        case bookSelected(Book)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case showDetail(Book)
        }
    }

    @Dependency(\.recentlyFoundBooksClient) var recentlyFoundBooksClient
    @Dependency(\.bookCoverClient) var bookCoverClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.books = recentlyFoundBooksClient.load()
                var requests: [(id: Book.ID, isbn: String)] = []
                for book in state.books where state.spines[book.id] == nil {
                    if let isbn = book.isbn, let image = bookCoverClient.cachedSpineImage(isbn) {
                        state.spines[book.id] = .loaded(image)
                    } else if let isbn = book.isbn {
                        state.spines[book.id] = .loading
                        requests.append((book.id, isbn))
                    } else {
                        state.spines[book.id] = .unavailable
                    }
                }
                guard !requests.isEmpty else { return .none }
                return .run { [bookCoverClient, requests] send in
                    await withTaskGroup(of: Void.self) { group in
                        for request in requests {
                            group.addTask {
                                let image = try? await bookCoverClient.spineImage(request.isbn)
                                await send(.spineLoaded(request.id, image))
                            }
                        }
                    }
                }

            case let .spineLoaded(id, image):
                state.spines[id] = image.map(SpinePhase.loaded) ?? .unavailable
                return .none

            case let .bookSelected(book):
                return .send(.delegate(.showDetail(book)))

            case .delegate:
                return .none
            }
        }
    }
}
