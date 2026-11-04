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

@Reducer
struct RecentlyFoundBookFeature {
    enum SpinePhase: Equatable {
        case loading
        // 책등 이미지를 받는 중. 받기 전까지 bookSpinePlaceHolder 에셋으로 그린다.
        case loaded(Data)
        // 받은 책등 PNG 데이터
        case unavailable
        // ISBN이 없거나 책등 이미지를 받지 못한 책. bookSpinePlaceHolder 에셋으로 그린다.
    }

    @ObservableState
    struct State: Equatable {
        var books: [Book] = []
        // 최근에 찾은 책이 앞(책장의 왼쪽)에 온다.
        var spines: [Book.ID: SpinePhase] = [:]
        @Presents var detail: BookDetailFeature.State?
        // 최근 찾은 책 화면에서 책등을 누르면 그 책의 상세를 연다. (마이페이지 카드는 쓰지 않는다)
    }

    enum Action {
        case task
        // 화면이 뜰 때마다 기록을 다시 읽고, 아직 없는 책등만 받는다.
        case spineLoaded(Book.ID, Data?)
        case bookSelected(Book)
        case detail(PresentationAction<BookDetailFeature.Action>)
    }

    @Dependency(\.recentlyFoundBooksClient) var recentlyFoundBooksClient
    @Dependency(\.bookCoverClient) var bookCoverClient
    @Dependency(\.bookFavoritesClient) var bookFavoritesClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                state.books = recentlyFoundBooksClient.load()
                var requests: [(id: Book.ID, isbn: String)] = []
                for book in state.books where state.spines[book.id] == nil {
                    if let isbn = book.isbn {
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
                                let data = try? await bookCoverClient.spinePngData(request.isbn)
                                await send(.spineLoaded(request.id, data))
                            }
                        }
                    }
                }
                // 같은 ISBN은 Yes24BookCoverResolver가 한 번만 요청하고, 결과는 15분 동안 캐시된다.

            case let .spineLoaded(id, data):
                state.spines[id] = data.map(SpinePhase.loaded) ?? .unavailable
                // spinePngData는 "책등 없음"과 "실패"를 같은 에러로 던지므로 둘 다 bookSpinePlaceHolder 에셋으로 그린다.
                return .none

            case let .bookSelected(book):
                state.detail = BookDetailFeature.State(
                    book: book, isFavorite: bookFavoritesClient.load().contains(book.recordKey)
                )
                // 홈·검색에서 상세를 열 때와 같은 방식으로 찜 여부를 함께 넘긴다.
                return .none

            case .detail:
                return .none
            }
        }
        .ifLet(\.$detail, action: \.detail) { BookDetailFeature() }
    }
}
