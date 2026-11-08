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
    let mapStore: StoreOf<IndoorMapFeature>

    var body: some View {
        NavigationStack {
            BookSearchView(
                store: store,
                onShowBasket: {
                    store.send(.basketButtonTapped)
                },
                onShowFavorites: {
                    store.send(.favoritesButtonTapped)
                },
                onShowProfile: {
                    store.send(.profileButtonTapped)
                }
            )
            .navigationDestination(
                item: $store.scope(state: \.favorites, action: \.favorites)
            ) { favoritesStore in
                BookFavoritesView(store: favoritesStore)
            }
            .navigationDestination(
                item: $store.scope(state: \.basket, action: \.basket)
            ) { basketStore in
                BookBasketView(store: basketStore)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(
                item: $store.scope(state: \.detail, action: \.detail)
            ) { detailStore in
                BookDetailMapView(
                    store: detailStore,
                    mapStore: mapStore
                )
            }
            .navigationDestination(
                item: $store.scope(state: \.shelfMap, action: \.shelfMap)
            ) { shelfMapStore in
                BookShelfMapView(store: shelfMapStore)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(
                item: $store.scope(state: \.myPage, action: \.myPage)
            ) { myPageStore in
                MyPageView(store: myPageStore, mapStore: mapStore)
            }
        }
        .task {
            store.send(.task)
        }
    }
}
