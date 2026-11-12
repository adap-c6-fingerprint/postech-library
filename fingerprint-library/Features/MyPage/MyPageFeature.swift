//
//  MyPageFeature.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  마이페이지 화면 feature
//  전역 상단 바(LibraryTabTopBar)의 마이페이지 버튼으로 들어온다.
//

import ComposableArchitecture
import Foundation

@Reducer
struct MyPageFeature {
    @ObservableState
    struct State: Equatable {
        var shelf = RecentlyFoundBookFeature.State()
        // 마이페이지 책장 카드. 최근 찾은 책 화면과 같은 State를 쓴다.
        @Presents var editAffiliation: EditMyAffiliationFeature.State?
        @Presents var editInterests: OnboardingFeature.State?
        // 관심 분야 변경은 별도 화면 없이 온보딩의 선호 분류 화면을 그대로 쓴다.
        @Presents var setupProfile: OnboardingFeature.State?
        // 온보딩을 건너뛰어 프로필이 없을 때: 온보딩의 소속 → 선호 분류 화면으로 프로필을 새로 만든다.
        @Shared(.userProfile) var userProfile: UserProfile?
    }

    enum Action {
        case shelf(RecentlyFoundBookFeature.Action)
        case addButtonTapped
        // "최근 찾은 책 목록" 오른쪽 + 버튼
        case editAffiliationRowTapped
        case editInterestsRowTapped
        case editAffiliation(PresentationAction<EditMyAffiliationFeature.Action>)
        case editInterests(PresentationAction<OnboardingFeature.Action>)
        case setupProfile(PresentationAction<OnboardingFeature.Action>)
        case delegate(Delegate)

        /// 다른 기능과 함께 쓰는 화면으로의 이동은 App이 맡는다.
        enum Delegate: Equatable {
            case showRecentlyFound(RecentlyFoundBookFeature.State)
        }
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.shelf, action: \.shelf) { RecentlyFoundBookFeature() }
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                // 이미 받은 책등을 그대로 넘겨 화면이 바로 채워지게 한다.
                return .send(.delegate(.showRecentlyFound(state.shelf)))

            case .editAffiliationRowTapped:
                guard state.userProfile != nil else {
                    state.setupProfile = .settingUpProfile()
                    return .none
                }
                // 프로필이 없으면(온보딩을 건너뜀) 변경 화면 대신 처음 설정 화면으로 간다.
                state.editAffiliation = EditMyAffiliationFeature.State()
                return .none

            case .editAffiliation(.presented(.delegate(.saved))):
                state.editAffiliation = nil
                // 소속을 저장하면 마이페이지로 돌아온다.
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
                // 관심 분야를 저장하면 마이페이지로 돌아온다.
                return .none

            case .setupProfile(.presented(.delegate(.completed))):
                state.setupProfile = nil
                // 프로필을 만들면 마이페이지로 돌아온다.
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
