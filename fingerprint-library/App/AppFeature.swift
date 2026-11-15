//
//  AppFeature.swift
//  2026-C6-M06-Fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import Combine
import ComposableArchitecture

@Reducer
struct AppFeature {
    enum Tab: Hashable {
        case map
        case recommendations
        case search
    }

    @ObservableState
    struct State: Equatable {
        var selectedTab = Tab.map
        var home = HomeFeature.State()
        var bookSearch = BookSearchFeature.State()
        var indoorMap = IndoorMapFeature.State()
        var locationSession = LocationSessionFeature.State()
        var mapPath = StackState<Path.State>()
        var recommendationsPath = StackState<Path.State>()
        var searchPath = StackState<Path.State>()
        @Presents var modal: Modal.State?
        var guidanceOrigin: GuidanceOrigin?
        var hasStartedRecommendationSession = false
        var hasEnteredBackground = false
        var hasCheckedProfile = false
        var onboarding: OnboardingFeature.State?
        @Shared(.userProfile) var userProfile: UserProfile?
        @Shared(.hasSkippedOnboarding) var hasSkippedOnboarding: Bool
    }

    enum Action {
        case tabSelected(Tab)
        case goHomeRequested
        case home(HomeFeature.Action)
        case bookSearch(BookSearchFeature.Action)
        case indoorMap(IndoorMapFeature.Action)
        case locationSession(LocationSessionFeature.Action)
        case mapPath(StackActionOf<Path>)
        case recommendationsPath(StackActionOf<Path>)
        case searchPath(StackActionOf<Path>)
        case modal(PresentationAction<Modal.Action>)
        case appStarted
        case analyticsObservationStarted
        case scenePhaseChanged(isActive: Bool)
        case appEnteredBackground
        case appBecameActive
        case profileCheckRequested
        case legacyProfileLoaded(UserProfile?)
        case onboarding(OnboardingFeature.Action)
    }

    @Dependency(\.legacyUserProfileClient) var legacyUserProfileClient
    @Dependency(\.analyticsClient) var analytics
    @Dependency(\.continuousClock) var clock
    @Dependency(\.recentlyFoundBooksClient) var recentlyFoundBooksClient
    @Dependency(\.bookCoverClient) var bookCoverClient

    nonisolated static let analyticsCheckpointInterval: Duration = .seconds(60)

    static func analyticsRootScreen(of tab: Tab) -> AnalyticsScreen {
        // 탭의 첫 화면 이름 (탭 위에 다른 화면이 쌓여 있어도 탭 기준으로 고른다)
        switch tab {
        case .map: .map
        case .recommendations: .recommendations
        case .search: .search
        }
    }

    private nonisolated enum CancelID: Hashable, Sendable {
        case analyticsCheckpoint
        case analyticsObservation
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.home, action: \.home) { HomeFeature() }
        Scope(state: \.bookSearch, action: \.bookSearch) { BookSearchFeature() }
        Scope(state: \.indoorMap, action: \.indoorMap) { IndoorMapFeature() }
        Scope(state: \.locationSession, action: \.locationSession) { LocationSessionFeature() }
        Reduce { state, action in
            switch action {
            case let .tabSelected(tab):
                let button: AnalyticsEvent.ButtonID = switch tab {
                case .map: .tabHome
                case .recommendations: .tabRecommendations
                case .search: .search
                }
                // 누른 하단 탭
                analytics.record(.button(button, on: Self.analyticsRootScreen(of: state.selectedTab)))
                // screen_name은 떠나는 탭의 첫 화면 이름
                state.selectedTab = tab
                return .none

            case .goHomeRequested:
                state.mapPath.removeAll()
                state.recommendationsPath.removeAll()
                state.searchPath.removeAll()
                state.modal = nil
                state.guidanceOrigin = nil
                state.selectedTab = .map
                return .none

            case let .bookSearch(.delegate(.recommendationLayoutRequested(isExpanded))):
                state.home.isRecommendationExpanded = isExpanded
                state.selectedTab = .recommendations
                return .none

            case .bookSearch(.delegate(.kulumiCoversRequested)):
                state.home.showsKulumiCovers = true
                state.selectedTab = .recommendations
                return .none

            case let .bookSearch(.delegate(delegate)):
                let source: AnalyticsScreen = state.bookSearch.hasSearched ? .searchResults : Self.analyticsRootScreen(of: state.selectedTab)
                // 책을 고른 화면 (검색 결과 또는 탭의 첫 화면)
                guard let destination = Self.destination(for: delegate, from: source) else { return .none }
                push(destination, onto: state.selectedTab, state: &state)
                return .none

            case .bookSearch(.cartButtonTapped):
                analytics.record(.button(.cart, on: Self.analyticsRootScreen(of: state.selectedTab)))
                // 상단 장바구니 버튼 (지도 탭과 검색 탭이 같은 BookSearchFeature를 쓰므로 탭으로 화면을 구분)
                return .none

            case .bookSearch(.favoritesButtonTapped):
                analytics.record(.button(.bookmark, on: Self.analyticsRootScreen(of: state.selectedTab)))
                // 상단 북마크 버튼
                return .none

            case .bookSearch(.profileButtonTapped):
                analytics.record(.button(.myPage, on: Self.analyticsRootScreen(of: state.selectedTab)))
                // 상단 마이페이지 버튼
                return .none

            case .bookSearch:
                return .none

            case let .home(.delegate(delegate)):
                let source: AnalyticsScreen = state.recommendationsPath.last == .departmentRecommendations ? .departmentRecommendations : .recommendations
                // 학과 추천 화면과 추천 탭이 같은 HomeFeature를 쓰므로, 맨 위 화면으로 구분
                push(Self.destination(for: delegate, from: source), onto: .recommendations, state: &state)
                return .none

            case let .mapPath(action):
                return handlePath(action, on: .map, state: &state)
            case let .recommendationsPath(action):
                return handlePath(action, on: .recommendations, state: &state)
            case let .searchPath(action):
                return handlePath(action, on: .search, state: &state)

            case .modal(.presented(.routePreview(.delegate(.goHomeRequested)))):
                return .send(.goHomeRequested)

            case .modal(.dismiss):
                return guidanceDismissed(state: &state)

            case .modal:
                return .none

            case .analyticsObservationStarted:
                return .run { [analytics] _ in
                    @Shared(.userProfile) var userProfile
                    @Shared(.favoriteBookKeys) var favoriteBookKeys
                    @Shared(.bookCart) var bookCart
                    analytics.updateCollectionCounts(favoriteBookKeys.count, bookCart.count)
                    // 시작 시점의 찜·장바구니 개수를 사용자 속성으로 설정한다
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await profile in $userProfile.publisher.dropFirst().values {
                                analytics.updateProfile(profile)
                            }
                        }
                        group.addTask {
                            for await keys in $favoriteBookKeys.publisher.dropFirst().values {
                                analytics.updateCollectionCounts(keys.count, bookCart.count)
                            }
                            // 찜 목록이 바뀔 때마다 개수를 다시 설정한다
                        }
                        group.addTask {
                            for await items in $bookCart.publisher.dropFirst().values {
                                analytics.updateCollectionCounts(favoriteBookKeys.count, items.count)
                            }
                            // 장바구니가 바뀔 때마다 개수를 다시 설정한다
                        }
                        group.addTask {
                            for await _ in analytics.consentChanges() {
                                analytics.updateProfile(userProfile)
                                analytics.updateCollectionCounts(favoriteBookKeys.count, bookCart.count)
                                // 분석에 다시 동의하면 지워졌던 개수 속성을 다시 설정한다
                            }
                        }
                    }
                }
                .cancellable(id: CancelID.analyticsObservation, cancelInFlight: true)

            case let .scenePhaseChanged(isActive):
                let activity: Effect<Action> = .run { [analytics] _ in await analytics.setActive(isActive) }
                guard isActive else { return .merge(activity, .cancel(id: CancelID.analyticsCheckpoint)) }
                return .merge(
                    activity,
                    .run { [analytics, clock] _ in
                        for await _ in clock.timer(interval: Self.analyticsCheckpointInterval) {
                            analytics.checkpoint()
                        }
                    }
                    .cancellable(id: CancelID.analyticsCheckpoint, cancelInFlight: true)
                )

            case .appStarted:
                guard !state.hasStartedRecommendationSession else { return .none }
                state.hasStartedRecommendationSession = true
                let preloadSpines: Effect<Action> = .run { [recentlyFoundBooksClient, bookCoverClient] _ in
                    await bookCoverClient.preloadSavedSpines(recentlyFoundBooksClient.load().compactMap(\.isbn))
                }
                guard state.home.recommendationSessionID == nil else { return preloadSpines }
                return .merge(preloadSpines, .send(.home(.recommendationSessionStarted)))
            case .appEnteredBackground:
                state.hasEnteredBackground = true
                return .none
            case .appBecameActive:
                guard state.hasStartedRecommendationSession, state.hasEnteredBackground else { return .none }
                state.hasEnteredBackground = false
                return .send(.home(.recommendationSessionStarted))
            case .home:
                return .none
            case .indoorMap, .locationSession:
                return .none

            case .profileCheckRequested:
                guard !state.hasCheckedProfile else { return .none }
                if state.userProfile != nil || state.hasSkippedOnboarding {
                    state.hasCheckedProfile = true
                    return .none
                }
                return .run { [legacyUserProfileClient] send in
                    await send(.legacyProfileLoaded(await legacyUserProfileClient.load()))
                }
            case let .legacyProfileLoaded(profile):
                state.hasCheckedProfile = true
                if let profile {
                    state.$userProfile.withLock { $0 = profile }
                } else {
                    state.onboarding = OnboardingFeature.State()
                }
                return .none
            case .onboarding(.delegate(.completed)):
                state.onboarding = nil
                return .none
            case .onboarding(.delegate(.skipped)):
                state.onboarding = nil
                return .none
            case .onboarding:
                return .none
            }
        }
        .forEach(\.mapPath, action: \.mapPath)
        .forEach(\.recommendationsPath, action: \.recommendationsPath)
        .forEach(\.searchPath, action: \.searchPath)
        .ifLet(\.$modal, action: \.modal)
        .ifLet(\.onboarding, action: \.onboarding) { OnboardingFeature() }
    }
}
