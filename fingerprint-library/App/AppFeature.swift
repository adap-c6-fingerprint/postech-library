//
//  AppFeature.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import ComposableArchitecture

@Reducer
struct AppFeature {
    @ObservableState
    struct State: Equatable {
        var home = HomeFeature.State()
        var indoorMap = IndoorMapFeature.State()
        var isRouteSettingsPresented = false
    }

    enum Action {
        case home(HomeFeature.Action)
        case indoorMap(IndoorMapFeature.Action)
        case routeSettingsPresentationChanged(Bool)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.home, action: \.home) { HomeFeature() }
        Scope(state: \.indoorMap, action: \.indoorMap) { IndoorMapFeature() }
        Reduce { state, action in
            switch action {
            case .indoorMap(.delegate(.showRouteSettings)):
                guard !state.isRouteSettingsPresented, state.indoorMap.routeDestination != nil
                else {
                    return .none
                }
                state.isRouteSettingsPresented = true
                return .send(.indoorMap(.routeRequested))
            case .routeSettingsPresentationChanged(let isPresented):
                guard state.isRouteSettingsPresented != isPresented else { return .none }
                guard !isPresented || state.indoorMap.routeDestination != nil else { return .none }
                state.isRouteSettingsPresented = isPresented
                return isPresented
                    ? .send(.indoorMap(.routeRequested)) : .send(.indoorMap(.routeCleared))
            case .home:
                // TODO: 홈 delegate 액션으로 책바구니·프로필·전체 보기를 연결한다.
                return .none
            case .indoorMap:
                return .none
            }
        }
    }
}
