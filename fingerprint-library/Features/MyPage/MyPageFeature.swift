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
        @Shared(.userProfile) var userProfile: UserProfile?
    }

    enum Action {
        case shelf(RecentlyFoundBookFeature.Action)
        case addButtonTapped
        case editAffiliationRowTapped
        case editInterestsRowTapped
        case editAffiliation(PresentationAction<EditMyAffiliationFeature.Action>)
        case editInterests(PresentationAction<OnboardingFeature.Action>)
        case setupProfile(PresentationAction<OnboardingFeature.Action>)
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case showRecentlyFound(RecentlyFoundBookFeature.State)
        }
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.shelf, action: \.shelf) { RecentlyFoundBookFeature() }
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                return .send(.delegate(.showRecentlyFound(state.shelf)))

            case .editAffiliationRowTapped:
                guard state.userProfile != nil else {
                    state.setupProfile = .settingUpProfile()
                    return .none
                }
                state.editAffiliation = EditMyAffiliationFeature.State()
                return .none

            case .editAffiliation(.presented(.delegate(.saved))):
                state.editAffiliation = nil
                return .none

            case .editInterestsRowTapped:
                guard state.userProfile != nil else {
                    state.setupProfile = .settingUpProfile()
                    return .none
                }
                state.editInterests = .changingInterests()
                return .none

            case .editInterests(.presented(.delegate(.completed))):
                state.editInterests = nil
                return .none

            case .setupProfile(.presented(.delegate(.completed))):
                state.setupProfile = nil
                return .none

            case .shelf, .editAffiliation, .editInterests, .setupProfile, .delegate:
                return .none
            }
        }
        .ifLet(\.$editAffiliation, action: \.editAffiliation) { EditMyAffiliationFeature() }
        .ifLet(\.$editInterests, action: \.editInterests) { OnboardingFeature() }
        .ifLet(\.$setupProfile, action: \.setupProfile) { OnboardingFeature() }
    }
}
