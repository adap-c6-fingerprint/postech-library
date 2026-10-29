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
        // MARK: - 탭과 지도 화면
        var home = HomeFeature.State()
        var bookSearch = BookSearchFeature.State()
        var indoorMap = IndoorMapFeature.State()
        var isRouteSettingsPresented = false
        // MARK: - 앱 접속 수명
        var hasStartedRecommendationSession = false
        var hasEnteredBackground = false
        // MARK: - 온보딩
        // 저장된 프로필을 확인하기 전에는 탭 화면도 온보딩도 띄우지 않는다.
        var hasCheckedProfile = false
        var onboarding: OnboardingFeature.State?
    }

    enum Action {
        case home(HomeFeature.Action)
        case bookSearch(BookSearchFeature.Action)
        case indoorMap(IndoorMapFeature.Action)
        case routeSettingsPresentationChanged(Bool)
        case appStarted
        case appEnteredBackground
        case appBecameActive
        case profileCheckRequested
        case profileChecked(hasProfile: Bool)
        case onboarding(OnboardingFeature.Action)
    }

    @Dependency(\.bookBasketClient) var bookBasketClient
    @Dependency(\.userProfileClient) var userProfileClient

    var body: some Reducer<State, Action> {
        Scope(state: \.home, action: \.home) { HomeFeature() }
        Scope(state: \.bookSearch, action: \.bookSearch) { BookSearchFeature() }
        Scope(state: \.indoorMap, action: \.indoorMap) { IndoorMapFeature() }
        Reduce { state, action in
            switch action {
            case .home(.detail(.presented(.addToBasketButtonTapped))),
                 .home(.basket(.presented(.removeConfirmed))),
                 .bookSearch(.detail(.presented(.addToBasketButtonTapped))),
                 .bookSearch(.basket(.presented(.removeConfirmed))),
                 .bookSearch(.addToBasket(_)), .bookSearch(.removeFromBasket(_)):
                synchronizeBasket(state: &state)
                return .none

            case .bookSearch(.task):
                synchronizeBasket(state: &state)
                synchronizeFavorites(state.bookSearch.favoriteBookKeys, state: &state)
                return .none

            case let .home(.delegate(.favoritesChanged(keys))):
                synchronizeFavorites(keys, state: &state)
                return .none

            case .bookSearch(.bookSelected(_)),
                 .bookSearch(.favoriteButtonTapped(_)),
                 .bookSearch(.detail(.presented(.delegate(.favoritesChanged(_))))):
                synchronizeFavorites(state.bookSearch.favoriteBookKeys, state: &state)
                return .none

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

            case .profileCheckRequested:
                guard !state.hasCheckedProfile else { return .none }
                return .run { [userProfileClient] send in
                    // 확인에 실패하면 온보딩을 보여준다. 저장할 때 기존 프로필이 있으면 덮어쓴다.
                    let hasProfile = (try? await userProfileClient.hasProfile()) ?? false
                    await send(.profileChecked(hasProfile: hasProfile))
                }
            case let .profileChecked(hasProfile):
                state.hasCheckedProfile = true
                state.onboarding = hasProfile ? nil : OnboardingFeature.State()
                return .none
            case .onboarding(.delegate(.completed)):
                state.onboarding = nil
                return .none
            case .onboarding:
                return .none
            }
        }
        .ifLet(\.onboarding, action: \.onboarding) { OnboardingFeature() }
    }

    private func synchronizeBasket(state: inout State) {
        let items = bookBasketClient.load()
        let ids = Set(items.map(\.id))
        state.bookSearch.basketBooks = items.map(\.book)
        if state.bookSearch.basket != nil {
            state.bookSearch.basket?.items = items
            state.bookSearch.basket?.selectedIDs.removeAll { !ids.contains($0) }
        }
        if state.home.basket != nil {
            state.home.basket?.items = items
            state.home.basket?.selectedIDs.removeAll { !ids.contains($0) }
        }
    }

    private func synchronizeFavorites(_ keys: Set<[String?]>, state: inout State) {
        state.bookSearch.favoriteBookKeys = keys
        if let book = state.bookSearch.detail?.book {
            state.bookSearch.detail?.isFavorite = keys.contains(book.recordKey)
        }
        if let book = state.home.detail?.book {
            state.home.detail?.isFavorite = keys.contains(book.recordKey)
        }
    }
}
