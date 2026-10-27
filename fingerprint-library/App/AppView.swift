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
        TabView {
            Tab("홈", systemImage: "house") {
                LibraryMapView(store: store)
            }

            Tab("추천", systemImage: "books.vertical") {
                NavigationStack {
                    HomeView(
                        store: store.scope(state: \.home, action: \.home)
                    )
                }
            }

            Tab(role: .search) {
                BookSearchTabView()
            }
        }
        .tabViewSearchActivation(.searchTabSelection)
        .tint(Color(red: 0.88, green: 0.95, blue: 0.19))
        // 위치 스트림은 탭 전환이 아닌 앱 루트 수명에 맞춘다.
        .task { await store.send(.indoorMap(.task)).finish() }
        .onDisappear { store.send(.indoorMap(.disappeared)) }
        .onChange(of: scenePhase) { _, phase in
            store.send(.indoorMap(.sceneActiveChanged(phase == .active)))
        }
    }
}
