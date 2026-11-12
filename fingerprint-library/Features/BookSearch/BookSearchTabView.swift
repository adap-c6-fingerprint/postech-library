//
//  BookSearchTabView.swift
//  fingerprint-library
//
//  Created by Codex on 10/27/26.
//

import ComposableArchitecture
import SwiftUI

/// 검색 탭의 첫 화면. 화면 이동 스택은 App이 소유한다.
struct BookSearchTabView: View {
    @Bindable var store: StoreOf<BookSearchFeature>

    var body: some View {
        BookSearchView(
            store: store,
            onShowCart: {
                store.send(.cartButtonTapped)
            },
            onShowFavorites: {
                store.send(.favoritesButtonTapped)
            },
            onShowProfile: {
                store.send(.profileButtonTapped)
            }
        )
        .task {
            store.send(.task)
        }
    }
}
