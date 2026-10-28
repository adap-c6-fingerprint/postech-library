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
        var bookSearch = BookSearchFeature.State()
        var indoorMap = IndoorMapFeature.State()
        var isRouteSettingsPresented = false
        var hasStartedRecommendationSession = false
        var hasEnteredBackground = false
    }

    enum Action {
        case home(HomeFeature.Action)
        case bookSearch(BookSearchFeature.Action)
        case indoorMap(IndoorMapFeature.Action)
        case routeSettingsPresentationChanged(Bool)
        case appStarted
        case appEnteredBackground
        case appBecameActive
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.home, action: \.home) { HomeFeature() }
        Scope(state: \.bookSearch, action: \.bookSearch) { BookSearchFeature() }
        Scope(state: \.indoorMap, action: \.indoorMap) { IndoorMapFeature() }
        Reduce { state, action in
            switch action {
            case let .home(.delegate(.addToBasket(book))):
                return .send(.bookSearch(.addToBasket(book)))

            case .bookSearch:
                return .none

            case .appStarted:
                guard !state.hasStartedRecommendationSession else { return .none }
                state.hasStartedRecommendationSession = true
                guard state.home.recommendationSessionID == nil else { return .none }
                return .send(.home(.recommendationSessionStarted))
            case .appEnteredBackground:
                state.hasEnteredBackground = true
                return .none
            case .appBecameActive:
                guard state.hasStartedRecommendationSession, state.hasEnteredBackground else { return .none }
                state.hasEnteredBackground = false
                return .send(.home(.recommendationSessionStarted))
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
