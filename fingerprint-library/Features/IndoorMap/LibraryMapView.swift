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

    @State private var searchStore = Store(
        initialState: BookSearchFeature.State()
    ) {
        BookSearchFeature()
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
            .navigationDestination(
                item: $searchStore.scope(state: \.basket, action: \.basket)
            ) { basketStore in
                BookBasketView(store: basketStore)
            }
            .navigationDestination(
                item: $searchStore.scope(state: \.detail, action: \.detail)
            ) { detailStore in
                BookDetailView(store: detailStore)
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
                searchStore.send(.basketButtonTapped)
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
