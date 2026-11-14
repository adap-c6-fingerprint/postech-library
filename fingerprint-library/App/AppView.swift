//
//  AppView.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import ComposableArchitecture
import SwiftUI
import Clarity

struct AppView: View {
    @Bindable var store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isBookSearchFocused: Bool

    var body: some View {
        Group {
            if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                OnboardingView(store: onboardingStore)
                    .analyticsScreen(.onboarding)
            } else if store.hasCheckedProfile {
                tabs
            } else {
                Color.cartBackground.ignoresSafeArea()
            }
        }

        .clarityUnmask()
        .task { store.send(.profileCheckRequested) }
        .task { store.send(.analyticsObservationStarted) }
        .onChange(of: scenePhase, initial: true) { _, phase in
            store.send(.scenePhaseChanged(isActive: phase == .active))
        }
    }

    private var tabs: some View {
        TabView(selection: Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )) {
            Tab("홈", systemImage: "house", value: AppFeature.Tab.map) {
                NavigationStack(path: $store.scope(state: \.mapPath, action: \.mapPath)) {
                    LibraryMapView(store: store)
                } destination: { pathDestination($0) }
                .tint(.primary)
                .analyticsScreen(.map)
                .tint(Color?.none)
            }

            Tab("추천", systemImage: "book", value: AppFeature.Tab.recommendations) {
                NavigationStack(
                    path: $store.scope(state: \.recommendationsPath, action: \.recommendationsPath)
                ) {
                    HomeView(
                        store: store.scope(state: \.home, action: \.home),
                        mapStore: store.scope(state: \.indoorMap, action: \.indoorMap)
                    )
                } destination: { pathDestination($0) }
                .analyticsScreen(.recommendations)
                .tint(Color?.none)
            }

            Tab(value: AppFeature.Tab.search, role: .search) {
                NavigationStack(path: $store.scope(state: \.searchPath, action: \.searchPath)) {
                    BookSearchTabView(store: store.scope(state: \.bookSearch, action: \.bookSearch))
                } destination: { pathDestination($0) }
                .searchable(
                    text: Binding(
                        get: { store.bookSearch.query },
                        set: { store.send(.bookSearch(.queryChanged($0))) }
                    ),
                    prompt: "책 제목이나 저자를 검색하세요"
                )
                .searchFocused($isBookSearchFocused)
                .searchPresentationToolbarBehavior(.avoidHidingContent)
                .onSubmit(of: .search, submitBookSearch)
                .analyticsScreen(.search)
                .tint(Color?.none)
            }
        }
        .tint(PobookUI.ColorToken.accent)
        .tabViewSearchActivation(.searchTabSelection)
        .onChange(of: store.searchPath.isEmpty) { _, isEmpty in
            if !isEmpty { isBookSearchFocused = false }
        }
        .fullScreenCover(item: $store.scope(state: \.modal, action: \.modal)) { modalStore in
            switch modalStore.case {
            case let .routePreview(routeStore):
                BookRoutePreviewView(store: routeStore)
                    .environment(\.indoorRouteMapStore, store.scope(state: \.indoorMap, action: \.indoorMap))
            }
        }
        .environment(\.indoorRouteMapStore, store.scope(state: \.indoorMap, action: \.indoorMap))
        .task {
            store.send(.appStarted)
            store.send(.locationSession(.started))
            await store.send(.indoorMap(.task)).finish()
        }
        .onDisappear { store.send(.indoorMap(.disappeared)) }
        .onChange(of: scenePhase) { _, phase in
            store.send(.locationSession(.sceneActiveChanged(phase == .active)))
            store.send(.indoorMap(.sceneActiveChanged(phase == .active)))
            if phase == .background { store.send(.appEnteredBackground) }
            if phase == .active { store.send(.appBecameActive) }
        }
    }

    private func pathDestination(_ pathStore: StoreOf<AppFeature.Path>) -> some View {
        AppPathDestinationView(
            store: pathStore,
            homeStore: store.scope(state: \.home, action: \.home),
            mapStore: store.scope(state: \.indoorMap, action: \.indoorMap)
        )
    }

    private func submitBookSearch() {
        guard store.selectedTab == .search,
              !store.bookSearch.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        store.send(.bookSearch(.searchButtonTapped))
    }
}
