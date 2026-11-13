//
//  BookSearchTabView.swift
//  fingerprint-library
//
//  Created by Codex on 10/27/26.
//

import ComposableArchitecture
import SwiftUI

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
