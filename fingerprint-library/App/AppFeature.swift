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

    nonisolated static let analyticsCheckpointInterval: Duration = .seconds(60)

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
                guard let destination = Self.destination(for: delegate) else { return .none }
                push(destination, onto: state.selectedTab, state: &state)
                return .none

            case .bookSearch:
                return .none

            case let .home(.delegate(delegate)):
                push(Self.destination(for: delegate), onto: .recommendations, state: &state)
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
                    await withTaskGroup(of: Void.self) { group in
                        group.addTask {
                            for await profile in $userProfile.publisher.dropFirst().values {
                                analytics.updateProfile(profile)
                            }
                        }
                        group.addTask {
                            for await _ in analytics.consentChanges() {
                                analytics.updateProfile(userProfile)
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
                guard state.home.recommendationSessionID == nil else { return .none }
                return .send(.home(.recommendationSessionStarted))
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
