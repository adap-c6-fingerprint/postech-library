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

        // 저장된 프로필이 없으면 온보딩을 먼저 보여주고, 마치면 탭 화면으로 넘어간다.
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
            // 피그마 탭바 시안(00.전역_홈)의 펼친 책 심볼. 홈 탭의 "house"처럼 탭바가 채운 모양(book.fill)으로 그린다.
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
                .analyticsScreen(.search)
                .tint(Color?.none)
            }
        }
        // 탭바만 강조색을 사용하고, 각 탭의 화면은 위에서 기본 색으로 되돌린다.
        .tint(Color(red: 0.88, green: 0.95, blue: 0.19))
        .searchable(
            text: Binding(
                get: { store.bookSearch.query },
                set: { store.send(.bookSearch(.queryChanged($0))) }
            ),
            prompt: "책 제목이나 저자를 검색하세요"
        )
        .searchFocused($isBookSearchFocused)
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .tabViewSearchActivation(.searchTabSelection)
        .onSubmit(of: .search, submitBookSearch)
        .onChange(of: store.searchPath.isEmpty) { _, isEmpty in
            // 검색 탭에서 다른 화면을 열면 검색창 키보드를 내린다.
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
        // 위치 스트림은 탭 전환이 아닌 앱 루트 수명에 맞춘다.
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
