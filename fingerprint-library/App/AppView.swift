//
//  AppView.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import ComposableArchitecture
import SwiftUI

struct AppView: View {
    let store: StoreOf<AppFeature>
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(
            selection: Binding(
                get: { store.selectedTab },
                set: { store.send(.tabSelected($0)) }
            )
        ) {
            Tab("홈", systemImage: "house.fill", value: AppFeature.Tab.home) {
                LibraryMapView(store: store)
            }

            Tab("추천", systemImage: "books.vertical", value: AppFeature.Tab.recommendation) {
                NavigationStack {
                    HomeView(
                        store: store.scope(state: \.home, action: \.home)
                    )
                }
            }
        }
        .tint(Color(red: 0xC5 / 255, green: 0xE3 / 255, blue: 0))  // 디자인 시스템 Primary Dark(#C5E300)
        // 위치 스트림은 탭 전환이 아닌 앱 루트 수명에 맞춘다.
        .task { await store.send(.indoorMap(.task)).finish() }
        .onDisappear { store.send(.indoorMap(.disappeared)) }
        .onChange(of: scenePhase) { _, phase in
            store.send(.indoorMap(.sceneActiveChanged(phase == .active)))
        }
    }
}
