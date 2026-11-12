//
//  AppPathDestinationView.swift
//  fingerprint-library
//
//  App이 소유한 탭별 스택에 쌓인 화면을 그린다.
//

import ComposableArchitecture
import SwiftUI

struct AppPathDestinationView: View {
    let store: StoreOf<AppFeature.Path>
    let homeStore: StoreOf<HomeFeature>
    let mapStore: StoreOf<IndoorMapFeature>

    var body: some View {
        switch store.case {
        case let .detail(detailStore):
            BookDetailMapView(store: detailStore, mapStore: mapStore)
        case let .cart(cartStore):
            BookCartView(store: cartStore)
                .toolbar(.visible, for: .navigationBar)
        case let .favorites(favoritesStore):
            BookFavoritesView(store: favoritesStore)
        case let .favoriteShelf(shelfStore):
            FavoriteShelfBooksView(store: shelfStore, mapStore: mapStore)
        case let .myPage(myPageStore):
            MyPageView(store: myPageStore, mapStore: mapStore)
        case let .recentlyFound(recentlyFoundStore):
            RecentlyFoundBookView(store: recentlyFoundStore, mapStore: mapStore)
        case .departmentRecommendations:
            DepartmentRecommendationsView(store: homeStore)
        }
    }
}
