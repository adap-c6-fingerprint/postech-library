//
//  LibraryMapView.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/26/26.
//

import ComposableArchitecture
import SwiftUI

struct LibraryMapView: View {
    @Bindable var store: StoreOf<AppFeature>

    @Bindable private var searchStore: StoreOf<BookSearchFeature>
    @ScaledMetric(relativeTo: .title) private var headerHeight: CGFloat = 160


    init(store: StoreOf<AppFeature>, searchStore: StoreOf<BookSearchFeature>? = nil) {
        self.store = store
        self.searchStore = searchStore ?? store.scope(state: \.bookSearch, action: \.bookSearch)
    }

    private var mapStore: StoreOf<IndoorMapFeature> {
        store.scope(state: \.indoorMap, action: \.indoorMap)
    }

    var body: some View {
        NavigationStack {
            moreDestinations(destinations(mapContent))
        }
        .tint(.primary)
    }
    // 수식어가 한 줄로 길게 이어지면 컴파일러가 타입 검사를 제시간에 끝내지 못해 지도 화면과 이동 목적지를 나눈다.

    private var mapLayout: some View {
            IndoorMapView(store: mapStore, topContentInset: headerHeight, appearance: .home,
                onSelectFavoriteMarker: { searchStore.send(.favoriteMarkerTapped($0)) })
                .ignoresSafeArea(.container, edges: .top)
                .overlay(alignment: .topLeading) {
                    // 전체 높이의 컨테이너가 상단 안전 영역까지 확장되어 배경은 기기 맨 위에서 시작한다.
                    VStack(spacing: 0) {
                        LibraryTopBarBackground()
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .ignoresSafeArea(.container, edges: [.top, .horizontal])
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .topLeading) { homeHeader }
                .background(.black)
                .safeAreaInset(edge: .top, spacing: LibraryTabIntroText.topBarSpacing) {
                    LibraryTabTopBar(
                        title: "홈",
                        onFavorites: { searchStore.send(.favoritesButtonTapped) },
                        onCart: { searchStore.send(.cartButtonTapped) },
                        onProfile: { searchStore.send(.profileButtonTapped) }
                    )
                }
                .toolbar(.hidden, for: .navigationBar)
    }

    private var mapContent: some View {
        mapLayout
            .task { await mapStore.send(.requestLocationPermission).finish() }
            .task {
                searchStore.send(.task)
            }
            .task(id: searchStore.favoriteBookKeys) {
                mapStore.send(.homeAnnotations(.favoritesChanged(searchStore.favoriteBookKeys)))
            }
            .task { await mapStore.send(.homeAnnotations(.task)).finish() }
            .onDisappear { mapStore.send(.homeAnnotations(.disappeared)) }
    }

    private func destinations(_ content: some View) -> some View {
        content
            .navigationDestination(
                item: $searchStore.scope(state: \.cart, action: \.cart)
            ) { cartStore in
                BookCartView(store: cartStore)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(
                item: $searchStore.scope(state: \.favorites, action: \.favorites)
            ) { favoritesStore in
                BookFavoritesView(store: favoritesStore)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(
                item: $searchStore.scope(state: \.detail, action: \.detail)
            ) { detailStore in
                BookDetailMapView(
                    store: detailStore,
                    mapStore: mapStore
                )
            }
    }

    private func moreDestinations(_ content: some View) -> some View {
        content
            .navigationDestination(
                item: $searchStore.scope(state: \.favoriteShelf, action: \.favoriteShelf)
            ) { shelfStore in
                FavoriteShelfBooksView(store: shelfStore, mapStore: mapStore)
            }
            .navigationDestination(
                item: $searchStore.scope(state: \.shelfMap, action: \.shelfMap)
            ) { shelfMapStore in
                BookShelfMapView(store: shelfMapStore)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(
                item: $searchStore.scope(state: \.myPage, action: \.myPage)
            ) { myPageStore in
                MyPageView(store: myPageStore, mapStore: mapStore)
            }
            .navigationDestination(
                isPresented: Binding(
                    get: { store.isRouteSettingsPresented },
                    set: { store.send(.routeSettingsPresentationChanged($0)) }
                )
            ) {
                IndoorRouteSettingsView(store: mapStore)
            }
    }
    
    private var homeHeader: some View {
        LibraryTabIntroText(title: "오늘은 어떤 책을\n읽어볼까요?")
            .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityIdentifier("library-home-greeting")
    }

}

#Preview {
    AppView(store: Store(initialState: AppFeature.State()) { AppFeature() })
}
