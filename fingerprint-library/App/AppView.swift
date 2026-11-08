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
    let store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var isBookSearchFocused: Bool
    @State private var showsAnalyticsChoice = false
    #if DEBUG
    @State private var showsSimulationSettings = false
    #endif

    var body: some View {
        Group {
            if let onboardingStore = store.scope(state: \.onboarding, action: \.onboarding) {
                OnboardingView(store: onboardingStore)
                    .analyticsScreen(.onboarding)
            } else if store.hasCheckedProfile {
                tabs
            } else {
                Color.basketBackground.ignoresSafeArea()
            }
        }
        // 저장된 프로필이 없으면 온보딩을 먼저 보여주고, 마치면 탭 화면으로 넘어간다.
        .clarityUnmask()
        .task { store.send(.profileCheckRequested) }
        .sheet(isPresented: $showsAnalyticsChoice) {
            AnalyticsSettingsView(isFirstChoice: true)
        }
        .task {
            showsAnalyticsChoice = !AnalyticsRuntime.shared.consent.hasChosen
                || !SessionReplayRuntime.shared.consent.hasChosen
            AnalyticsRuntime.shared.updateProfile(store.userProfile)
        }
        .task(id: scenePhase) {
            AnalyticsRuntime.shared.setActive(scenePhase == .active)
            SessionReplayRuntime.shared.setActive(scenePhase == .active)
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
                AnalyticsRuntime.shared.checkpoint()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            AnalyticsRuntime.shared.setActive(phase == .active)
            SessionReplayRuntime.shared.setActive(phase == .active)
        }
        .onChange(of: store.userProfile) { _, profile in
            AnalyticsRuntime.shared.updateProfile(profile)
        }
        .onReceive(NotificationCenter.default.publisher(for: AnalyticsRuntime.consentChanged)) { _ in
            AnalyticsRuntime.shared.updateProfile(store.userProfile)
            showsAnalyticsChoice = false
        }
    }

    private var tabs: some View {
        TabView(selection: Binding(
            get: { store.selectedTab },
            set: { store.send(.tabSelected($0)) }
        )) {
            Tab("홈", systemImage: "house", value: AppFeature.Tab.map) {
                LibraryMapView(store: store)
                    .analyticsScreen(.map)
            }

            Tab("추천", systemImage: "book", value: AppFeature.Tab.recommendations) {
            // 피그마 탭바 시안(00.전역_홈)의 펼친 책 심볼. 홈 탭의 "house"처럼 탭바가 채운 모양(book.fill)으로 그린다.
                HomeView(
                    store: store.scope(state: \.home, action: \.home),
                    mapStore: store.scope(state: \.indoorMap, action: \.indoorMap)
                )
                .analyticsScreen(.recommendations)
            }

            Tab(value: AppFeature.Tab.search, role: .search) {
                BookSearchTabView(
                    store: store.scope(state: \.bookSearch, action: \.bookSearch),
                    mapStore: store.scope(state: \.indoorMap, action: \.indoorMap)
                )
                .analyticsScreen(.search)
            }
        }
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
        .onChange(of: store.bookSearch.detail != nil) { _, showsDetail in
            if showsDetail { isBookSearchFocused = false }
        }
        #if DEBUG
        .background {
            HomeTabDebugTrigger(
                isEnabled: scenePhase == .active && !showsSimulationSettings,
                isHomeSelected: { store.selectedTab == .map }
            ) {
                guard store.selectedTab == .map, !showsSimulationSettings else { return }
                showsSimulationSettings = true
            }
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
        .sheet(isPresented: $showsSimulationSettings) {
            SimulationConnectionSheet(
                position: store.indoorMap.latestPosition,
                floorName: store.indoorMap.map?.floors.first {
                    $0.ordinal == store.indoorMap.latestPosition?.floorOrdinal
                }?.name,
                message: store.indoorMap.locationMessage,
                onReconnect: { store.send(.indoorMap(.simulationConnectionChanged)) }
            )
            // 내부 Mac 주소가 표시되는 개발용 연결 설정은 녹화하지 않는다.
            .sessionReplayProtected()
        }
        #endif
        .tint(Color(red: 0.88, green: 0.95, blue: 0.19))
        .environment(\.indoorRouteMapStore, store.scope(state: \.indoorMap, action: \.indoorMap))
        // 위치 스트림은 탭 전환이 아닌 앱 루트 수명에 맞춘다.
        .task {
            store.send(.appStarted)
            await store.send(.indoorMap(.task)).finish()
        }
        .onDisappear { store.send(.indoorMap(.disappeared)) }
        .onChange(of: scenePhase) { _, phase in
            store.send(.indoorMap(.sceneActiveChanged(phase == .active)))
            if phase == .background { store.send(.appEnteredBackground) }
            if phase == .active { store.send(.appBecameActive) }
        }
    }

    private func submitBookSearch() {
        guard store.selectedTab == .search,
              !store.bookSearch.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        store.send(.bookSearch(.searchButtonTapped))
    }
}
