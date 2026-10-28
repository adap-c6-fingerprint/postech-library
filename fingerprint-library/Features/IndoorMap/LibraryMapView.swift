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
    @State private var isBasketPresented = false

    init(store: StoreOf<AppFeature>, searchStore: StoreOf<BookSearchFeature>? = nil) {
        self.store = store
        self.searchStore = searchStore ?? store.scope(state: \.bookSearch, action: \.bookSearch)
    }

    private var mapStore: StoreOf<IndoorMapFeature> {
        store.scope(state: \.indoorMap, action: \.indoorMap)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                homeHeader
                IndoorMapView(store: mapStore)
                    .background(Color(uiColor: .systemGroupedBackground))
            }
            .task {
                searchStore.send(.task)
            }
            .navigationDestination(isPresented: $isBasketPresented) {
                BookBasketView(
                    books: searchStore.basketBooks,
                    onDeletedSelected: { bookIDs in
                        searchStore.send(.removeFromBasket(bookIDs))
                    },
                    onShowDirections: { bookIDs in
                        searchStore.send(.basketDirectionsButtonTapped(bookIDs))
                    }
                )
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
        HStack(spacing: 8) {
            Text("오늘은 어떤 책을\n읽어볼까요?")
                .font(.system(size: 28, weight: .bold))

            Spacer()

            Button {
                isBasketPresented = true
            } label: {
                Image(systemName: "cart")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("책바구니")

            Button {
                // 마이페이지 이동 연결
            } label: {
                Image(systemName: "person")
                    .font(.system(size: 22))
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel("마이페이지")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

}

#Preview {
    AppView(store: Store(initialState: AppFeature.State()) { AppFeature() })
}
