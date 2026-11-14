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

    private let searchStore: StoreOf<BookSearchFeature>
    @ScaledMetric(relativeTo: .title) private var headerHeight: CGFloat = 160


    init(store: StoreOf<AppFeature>, searchStore: StoreOf<BookSearchFeature>? = nil) {
        self.store = store
        self.searchStore = searchStore ?? store.scope(state: \.bookSearch, action: \.bookSearch)
    }

    private var mapStore: StoreOf<IndoorMapFeature> {
        store.scope(state: \.indoorMap, action: \.indoorMap)
    }

    var body: some View {
        mapContent
    }

    private var mapLayout: some View {
            IndoorMapView(store: mapStore, topContentInset: headerHeight, appearance: .home,
                onSelectFavoriteMarker: { searchStore.send(.favoriteMarkerTapped($0)) })
                .ignoresSafeArea(.container, edges: .top)
                .overlay(alignment: .topLeading) {
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
                .libraryTabToolbar(
                    title: "홈",
                    onFavorites: { searchStore.send(.favoritesButtonTapped) },
                    onCart: { searchStore.send(.cartButtonTapped) },
                    onProfile: { searchStore.send(.profileButtonTapped) }
                )
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

    private var homeHeader: some View {
        LibraryTabIntroText(title: "오늘은 어떤 책을\n읽어볼까요?")
            .padding(.top, LibraryTabIntroText.topBarSpacing)
            .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .topLeading)
            .allowsHitTesting(false)
            .accessibilityIdentifier("library-home-greeting")
    }

}

#Preview {
    AppView(store: Store(initialState: AppFeature.State()) { AppFeature() })
}
