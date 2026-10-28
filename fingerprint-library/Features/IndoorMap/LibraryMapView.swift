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
            IndoorMapView(store: mapStore, topContentInset: headerHeight, appearance: .home)
                .ignoresSafeArea(.container, edges: .top)
                .overlay(alignment: .topLeading) { homeHeader }
                .background(.black)
                .toolbar {
                    LibraryTopBar(title: "홈", onBasket: { searchStore.send(.basketButtonTapped) })
                }
                .toolbarBackground(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
            .task {
                searchStore.send(.task)
            }
            .navigationDestination(
                item: $searchStore.scope(state: \.basket, action: \.basket)
            ) { basketStore in
                BookBasketView(store: basketStore)
                    .toolbar(.visible, for: .navigationBar)
            }
            .navigationDestination(
                item: $searchStore.scope(state: \.detail, action: \.detail)
            ) { detailStore in
                BookDetailView(store: detailStore)
            }
            .navigationDestination(
                item: $searchStore.scope(state: \.shelfMap, action: \.shelfMap)
            ) { shelfMapStore in
                BookShelfMapView(store: shelfMapStore)
                    .toolbar(.visible, for: .navigationBar)
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
            .font(.title.weight(.bold))
            .lineSpacing(6)
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .frame(maxWidth: .infinity, minHeight: headerHeight, alignment: .topLeading)
            .background { LibraryTopBarBackground().ignoresSafeArea(.container, edges: .top) }
            .allowsHitTesting(false)
            .accessibilityIdentifier("library-home-greeting")
    }

}

#Preview {
    AppView(store: Store(initialState: AppFeature.State()) { AppFeature() })
}
