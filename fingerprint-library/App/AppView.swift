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
        .task {
            AnalyticsRuntime.shared.updateProfile(store.userProfile)
        }
        // 데이터 수집 설정은 앱 실행 직후 자동으로 띄우지 않는다. 마이페이지의 "데이터 수집 설정" 행에서만 연다.
        // 아직 고르지 않은 동안(hasChosen == false)은 분석·진단·화면 녹화를 수집하지 않는다.
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

            Tab("추천", systemImage: "books.vertical", value: AppFeature.Tab.recommendations) {
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
        .tabViewSearchActivation(.searchTabSelection)
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
}
