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
    @State private var isSearchPresented = false
    @State private var isBasketPresented = false
    @FocusState private var isSearchFocused: Bool

    private var mapStore: StoreOf<IndoorMapFeature> {
        store.scope(state: \.indoorMap, action: \.indoorMap)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                homeHeader
                ZStack(alignment: .top) {
                    // 검색 중에도 지도를 유지해 카메라와 층 선택 상태를 보존
                    IndoorMapView(store: mapStore)
                        .ignoresSafeArea(.keyboard, edges: .bottom)
                        .opacity(isSearchPresented ? 0 : 1)
                        .allowsHitTesting(!isSearchPresented)
                        .accessibilityHidden(isSearchPresented)

                    if isSearchPresented {
                        BookSearchView(
                            store: searchStore,
                            isEditingSearch: isSearchFocused,
                            onSelectRecentQuery: { keyword in
                                searchStore.send(.queryChanged(keyword))
                                submitSearch()
                            },
                            onShowBasket: {
                                isSearchFocused = false
                                isBasketPresented = true
                            }
                        )
                        .padding(.top, 44)
                    }

                    HomeSearchBar(
                        text: Binding(
                            get: { searchStore.query },
                            set: { searchStore.send(.queryChanged($0)) }
                        ),
                        isFocused: $isSearchFocused,
                        isPresented: isSearchPresented,
                        onCancel: {
                            isSearchFocused = false
                            isSearchPresented = false
                        },
                        onSubmit: submitSearch
                    )
                }
                .background(Color(uiColor: .systemGroupedBackground))
            }
            .onChange(of: isSearchFocused) { _, isFocused in
                if isFocused {
                    isSearchPresented = true
                }
            }
            .onChange(of: isSearchPresented) { _, isPresented in
                if !isPresented {
                    searchStore.send(.searchCancelled)
                }
            }
            .task {
                searchStore.send(.task)
            }
            .navigationDestination(isPresented: $isBasketPresented) {
                BookBasketView(
                    books: searchStore.basketBooks,
                    onDeletedSelected: { bookIDs in
                        searchStore.send(.removeFromBasket(bookIDs))
                    }
                )
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
            Text("추천")
                .font(.system(size: 28, weight: .bold))

            Spacer()

            Button {
                isSearchFocused = false
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

    private func submitSearch() {
        guard !searchStore.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        isSearchFocused = false
        searchStore.send(.searchButtonTapped)
    }
}

private struct HomeSearchBar: View {
    @Binding var text: String
    var isFocused: FocusState<Bool>.Binding
    let isPresented: Bool
    let onCancel: () -> Void
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)

                TextField("어떤 책을 찾으시나요?", text: $text)
                    .focused(isFocused)
                    .submitLabel(.search)
                    .onSubmit(onSubmit)

                if !text.isEmpty {
                    Button {
                        text = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityLabel("검색어 지우기")
                }
            }
            .padding(.horizontal, 12)
            .frame(minHeight: 36)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))

            if isPresented {
                Button("취소", action: onCancel)
                    .foregroundStyle(.primary)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

#Preview {
    AppView(store: Store(initialState: AppFeature.State()) { AppFeature() })
}
