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
        /// 앱 활성 수명 동안 위치 이벤트를 한 곳에서 구독한다.
        var locationSession = LocationSessionFeature.State()
        // 탭마다 따로 쌓는 push 화면 스택. 기능은 delegate로 요청하고 App이 쌓는다.
        var mapPath = StackState<Path.State>()
        var recommendationsPath = StackState<Path.State>()
        var searchPath = StackState<Path.State>()
        @Presents var modal: Modal.State?
        var guidanceOrigin: GuidanceOrigin?
        var isRouteSettingsPresented = false
        var hasStartedRecommendationSession = false
        var hasEnteredBackground = false
        // 저장된 프로필을 확인하기 전에는 탭 화면도 온보딩도 띄우지 않는다.
        var hasCheckedProfile = false
        var onboarding: OnboardingFeature.State?
        @Shared(.userProfile) var userProfile: UserProfile?
        // 앱 전체가 함께 쓰는 프로필 하나. nil이면 온보딩을 보여준다.
        @Shared(.hasSkippedOnboarding) var hasSkippedOnboarding: Bool
        // 온보딩을 건너뛰었으면 프로필이 없어도 온보딩을 다시 띄우지 않는다.
    }

    enum Action {
        case tabSelected(Tab)
        /// 깊은 화면에서 홈 지도 탭으로 돌아간다. 띄워 둔 상세·책바구니 화면을 함께 닫는다.
        case goHomeRequested
        case home(HomeFeature.Action)
        case bookSearch(BookSearchFeature.Action)
        case indoorMap(IndoorMapFeature.Action)
        case locationSession(LocationSessionFeature.Action)
        case mapPath(StackActionOf<Path>)
        case recommendationsPath(StackActionOf<Path>)
        case searchPath(StackActionOf<Path>)
        case modal(PresentationAction<Modal.Action>)
        case routeSettingsPresentationChanged(Bool)
        case appStarted
        /// 앱 루트 화면이 뜰 때 프로필·동의 변경을 분석에 반영하기 시작한다.
        case analyticsObservationStarted
        case scenePhaseChanged(isActive: Bool)
        case appEnteredBackground
        case appBecameActive
        case profileCheckRequested
        case legacyProfileLoaded(UserProfile?)
        // 새 저장소가 비어 있을 때 이전 저장소(SwiftData)에서 읽어 온 프로필
        case onboarding(OnboardingFeature.Action)
    }

    @Dependency(\.legacyUserProfileClient) var legacyUserProfileClient
    @Dependency(\.analyticsClient) var analytics
    @Dependency(\.continuousClock) var clock

    /// 앱이 활성인 동안 분석 이벤트를 저장하는 주기.
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
                state.isRouteSettingsPresented = false
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
                // 검색 상태는 홈 지도 탭과 검색 탭이 함께 쓰므로, 요청이 생긴 지금 탭에 쌓는다.
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
                            // 처음 값은 런타임이 시작할 때 읽으므로 바뀐 값만 반영한다.
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
                return .none
            case .indoorMap, .locationSession:
                return .none

            case .profileCheckRequested:
                guard !state.hasCheckedProfile else { return .none }
                if state.userProfile != nil || state.hasSkippedOnboarding {
                    state.hasCheckedProfile = true
                    return .none
                }
                // 새 저장소가 비어 있으면, 이전 버전에서 온보딩을 마친 기기일 수 있으니 이전 저장소를 한 번 확인한다.
                return .run { [legacyUserProfileClient] send in
                    await send(.legacyProfileLoaded(await legacyUserProfileClient.load()))
                }
            case let .legacyProfileLoaded(profile):
                state.hasCheckedProfile = true
                if let profile {
                    state.$userProfile.withLock { $0 = profile }
                    // 이전 값을 새 저장소로 옮긴다. 이후로는 새 저장소만 쓴다.
                } else {
                    state.onboarding = OnboardingFeature.State()
                }
                return .none
            case .onboarding(.delegate(.completed)):
                state.onboarding = nil
                state.home.isFirstVisitAfterOnboarding = true
                // ✅ 이번 실행의 첫 홈 표시는 하드데이터만으로 바로 보여준다. (Q4)
                return .none
            case .onboarding(.delegate(.skipped)):
                state.onboarding = nil
                state.home.isFirstVisitAfterOnboarding = true
                // 안내 팝업("건너뛰었어요")에서 "확인했어요"를 누른 뒤에만 여기로 온다.
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
