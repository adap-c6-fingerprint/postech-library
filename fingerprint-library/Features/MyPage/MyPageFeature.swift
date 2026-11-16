//
//  MyPageFeature.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  마이페이지 화면 feature
//  전역 상단 바(libraryTabToolbar)의 마이페이지 버튼으로 들어온다.
//

import ComposableArchitecture
import Foundation

@Reducer
struct MyPageFeature {
    @ObservableState
    struct State: Equatable {
        var shelf = RecentlyFoundBookFeature.State()
        @Presents var editAffiliation: EditMyAffiliationFeature.State?
        @Presents var editInterests: OnboardingFeature.State?
        @Presents var setupProfile: OnboardingFeature.State?
        /// 실험 브랜치 전용: 검색창 `/test` 측정 모드가 켜져 있을 때만 기록 목록을 연다.
        @Presents var diagnosticsSessions: LocationDiagnosticsSessionsFeature.State?
        @Shared(.userProfile) var userProfile: UserProfile?
        @Shared(.locationDiagnosticsAutoRecord) var isLocationDiagnosticsMode: Bool
    }

    enum Action {
        case shelf(RecentlyFoundBookFeature.Action)
        case addButtonTapped
        case editAffiliationRowTapped
        case editInterestsRowTapped
        case locationPermissionRowTapped
        // "위치 권한 설정" (설정 앱 열기는 View가 한다)
        case privacyPolicyRowTapped
        // "개인정보 처리방침" (링크 열기는 View가 한다)
        case editAffiliation(PresentationAction<EditMyAffiliationFeature.Action>)
        case editInterests(PresentationAction<OnboardingFeature.Action>)
        case setupProfile(PresentationAction<OnboardingFeature.Action>)
        case diagnosticsSessionsRowTapped
        case diagnosticsSessions(PresentationAction<LocationDiagnosticsSessionsFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case showRecentlyFound(RecentlyFoundBookFeature.State)
        }
    }

    @Dependency(\.analyticsClient) private var analytics

    var body: some Reducer<State, Action> {
        Scope(state: \.shelf, action: \.shelf) { RecentlyFoundBookFeature() }
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                analytics.record(.button(.recentMore, on: .myPage))
                // 최근 찾은 책 "더보기"
                return .send(.delegate(.showRecentlyFound(state.shelf)))

            case .editAffiliationRowTapped:
                analytics.record(.button(.editAffiliation, on: .myPage))
                // "소속 및 학과 정보 변경" (프로필이 없으면 프로필 설정으로 이어진다)
                guard state.userProfile != nil else {
                    state.setupProfile = .settingUpProfile()
                    return .none
                }
                state.editAffiliation = EditMyAffiliationFeature.State()
                return .none

            case .editAffiliation(.presented(.delegate(.saved))):
                state.editAffiliation = nil
                return .none

            case .editAffiliation(.dismiss):
                if let edit = state.editAffiliation {
                    analytics.record(.button(.back, on: .editAffiliation,
                                             [.action: .text(edit.hasChangedSelection ? "changed" : "unchanged")]))
                }
                // 소속 변경 화면에서 저장하지 않고 뒤로가기 (선택을 바꿨다가 나갔는지 함께 보낸다)
                return .none

            case .editInterestsRowTapped:
                analytics.record(.button(.editInterests, on: .myPage))
                // "관심 분야 변경하기" (프로필이 없으면 프로필 설정으로 이어진다)
                guard state.userProfile != nil else {
                    state.setupProfile = .settingUpProfile()
                    return .none
                }
                state.editInterests = .changingInterests()
                return .none

            case .editInterests(.presented(.delegate(.completed))):
                state.editInterests = nil
                return .none

            case .editInterests(.dismiss):
                if let edit = state.editInterests {
                    analytics.record(.button(.back, on: .myPageInterests,
                                             [.action: .text(edit.hasChangedInterests ? "changed" : "unchanged")]))
                }
                // 관심 분야 변경 화면에서 완료하지 않고 뒤로가기 (선택을 바꿨다가 나갔는지 함께 보낸다)
                return .none

            case .setupProfile(.presented(.delegate(.completed))):
                state.setupProfile = nil
                return .none

            case .diagnosticsSessionsRowTapped:
                guard state.isLocationDiagnosticsMode else { return .none }
                state.diagnosticsSessions = LocationDiagnosticsSessionsFeature.State()
                return .none

            case .locationPermissionRowTapped:
                analytics.record(.button(.locationPermission, on: .myPage))
                // "위치 권한 설정"
                return .none

            case .privacyPolicyRowTapped:
                analytics.record(.button(.privacyPolicy, on: .myPage))
                // "개인정보 처리방침"
                return .none

            case .shelf, .editAffiliation, .editInterests, .setupProfile, .diagnosticsSessions, .delegate:
                return .none
            }
        }
        .ifLet(\.$editAffiliation, action: \.editAffiliation) { EditMyAffiliationFeature() }
        .ifLet(\.$editInterests, action: \.editInterests) { OnboardingFeature() }
        .ifLet(\.$setupProfile, action: \.setupProfile) { OnboardingFeature() }
        .ifLet(\.$diagnosticsSessions, action: \.diagnosticsSessions) { LocationDiagnosticsSessionsFeature() }
    }
}
