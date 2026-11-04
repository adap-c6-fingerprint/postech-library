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

    struct Constants {
      static let colorTextTitle: Color = Color(red: 0.98, green: 0.98, blue: 0.98)
      static let FontSize24: CGFloat = 24
      static let FontFamilyPretendard: String = "Pretendard"
    }

    init(store: StoreOf<AppFeature>, searchStore: StoreOf<BookSearchFeature>? = nil) {
        self.store = store
        self.searchStore = searchStore ?? store.scope(state: \.bookSearch, action: \.bookSearch)
    }

    private var mapStore: StoreOf<IndoorMapFeature> {
        store.scope(state: \.indoorMap, action: \.indoorMap)
    }

    var body: some View {
        NavigationStack {
            IndoorMapView(store: mapStore, topContentInset: headerHeight, appearance: .home)
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
                .safeAreaInset(edge: .top, spacing: 0) {
                    LibraryMapTopBar(
                        title: "홈",
                        onFavorites: { searchStore.send(.favoritesButtonTapped) },
                        onBasket: { searchStore.send(.basketButtonTapped) },
                        onProfile: { searchStore.send(.profileButtonTapped) }
                    )
                }
                .toolbar(.hidden, for: .navigationBar)
            .task {
                searchStore.send(.task)
            }
            .task(id: searchStore.favoriteBookKeys) {
                mapStore.send(.homeAnnotations(.favoritesChanged(searchStore.favoriteBookKeys)))
            }
            .task { await mapStore.send(.homeAnnotations(.task)).finish() }
            .onDisappear { mapStore.send(.homeAnnotations(.disappeared)) }
            .navigationDestination(
                item: $searchStore.scope(state: \.basket, action: \.basket)
            ) { basketStore in
                BookBasketView(store: basketStore)
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
        .tint(.primary)
    }
    
    private var homeHeader: some View {
        Text("오늘은 어떤 책을\n읽어볼까요?")
            .font(Font.custom(Constants.FontFamilyPretendard, size: Constants.FontSize24)
                .weight(.semibold))
            .lineSpacing(6)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityIdentifier("library-home-greeting")
    }

}

#Preview {
    AppView(store: Store(initialState: AppFeature.State()) { AppFeature() })
}
