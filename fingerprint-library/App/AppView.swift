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
        HomeView(store: store)
            // 위치 스트림은 홈의 push/pop이 아닌 전체 navigation 수명에 맞춘다.
            .task { await store.send(.indoorMap(.task)).finish() }
            .onDisappear { store.send(.indoorMap(.disappeared)) }
            .onChange(of: scenePhase) { _, phase in
                store.send(.indoorMap(.sceneActiveChanged(phase == .active)))
            }
    }
}
