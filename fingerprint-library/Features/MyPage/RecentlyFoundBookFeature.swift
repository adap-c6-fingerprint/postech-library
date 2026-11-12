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
        // 책등 이미지를 받는 중. 받기 전까지 제목을 얹은 recentlyFoundBookPlaceHolder 에셋으로 그린다.
        case loaded(UIImage)
        // 받은 책등 이미지. 표지와 같은 메모리 캐시(BookCoverPipeline.shared)에 있는 이미지 그대로다.
        case unavailable
        // ISBN이 없거나 책등 이미지를 받지 못한 책. 제목을 얹은 recentlyFoundBookPlaceHolder 에셋으로 그린다.
    }

    @ObservableState
    struct State: Equatable {
        var books: [Book] = []
        // 최근에 찾은 책이 앞(책장의 왼쪽)에 온다.
        var spines: [Book.ID: SpinePhase] = [:]
    }

    enum Action {
        case task
        // 화면이 뜰 때마다 기록을 다시 읽고, 아직 없는 책등만 받는다.
        case spineLoaded(Book.ID, UIImage?)
        case bookSelected(Book)
        case delegate(Delegate)

        /// 최근 찾은 책 화면에서 책등을 누르면 App이 그 책의 상세를 연다. (마이페이지 카드는 쓰지 않는다)
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
                        // 표지처럼 이미 받아 둔 책등은 기다리지 않고 바로 그린다. 다시 들어올 때 플레이스홀더가 잠깐 보이지 않는다.
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
                // 같은 ISBN은 Yes24BookCoverResolver가 한 번만 요청하고, 결과는 15분 동안 캐시된다.
                // 받은 이미지는 표지와 같은 메모리 캐시에 남아, 다음에 들어올 때 cachedSpineImage로 바로 꺼낸다.

            case let .spineLoaded(id, image):
                state.spines[id] = image.map(SpinePhase.loaded) ?? .unavailable
                // spineImage는 "책등 없음"과 "실패"를 같은 에러로 던지므로 둘 다 플레이스홀더 에셋으로 그린다.
                return .none

            case let .bookSelected(book):
                return .send(.delegate(.showDetail(book)))

            case .delegate:
                return .none
            }
        }
    }
}
