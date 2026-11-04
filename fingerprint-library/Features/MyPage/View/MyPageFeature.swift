//
//  MyPageFeature.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  마이페이지 화면 feature
//  전역 상단 바(LibraryTopBar)의 마이페이지 버튼으로 들어온다.
//

import ComposableArchitecture
import Foundation

@Reducer
struct MyPageFeature {
    @ObservableState
    struct State: Equatable {
        var shelf = RecentlyFoundBookFeature.State()
        // 마이페이지 책장 카드. 최근 찾은 책 화면과 같은 State를 쓴다.
        @Presents var recentlyFound: RecentlyFoundBookFeature.State?
        @Presents var editAffiliation: EditMyAffiliationFeature.State?
        @Presents var editInterests: OnboardingFeature.State?
        // 관심 분야 변경은 별도 화면 없이 온보딩의 선호 분류 화면을 그대로 쓴다.
    }

    enum Action {
        case shelf(RecentlyFoundBookFeature.Action)
        case addButtonTapped
        // "최근 찾은 책 목록" 오른쪽 + 버튼
        case editAffiliationRowTapped
        case editInterestsRowTapped
        case recentlyFound(PresentationAction<RecentlyFoundBookFeature.Action>)
        case editAffiliation(PresentationAction<EditMyAffiliationFeature.Action>)
        case editInterests(PresentationAction<OnboardingFeature.Action>)
    }

    var body: some Reducer<State, Action> {
        Scope(state: \.shelf, action: \.shelf) { RecentlyFoundBookFeature() }
        Reduce { state, action in
            switch action {
            case .addButtonTapped:
                state.recentlyFound = state.shelf
                // 이미 받은 책등을 그대로 넘겨 화면이 바로 채워지게 한다.
                return .none

            case .editAffiliationRowTapped:
                state.editAffiliation = EditMyAffiliationFeature.State()
                return .none

            case .editAffiliation(.presented(.delegate(.saved))):
                state.editAffiliation = nil
                // 소속을 저장하면 마이페이지로 돌아온다.
                return .none

            case .editInterestsRowTapped:
                state.editInterests = .changingInterests()
                return .none

            case .editInterests(.presented(.delegate(.completed))):
                state.editInterests = nil
                // 관심 분야를 저장하면 마이페이지로 돌아온다.
                return .none

            case .shelf, .recentlyFound, .editAffiliation, .editInterests:
                return .none
            }
        }
        .ifLet(\.$recentlyFound, action: \.recentlyFound) { RecentlyFoundBookFeature() }
        .ifLet(\.$editAffiliation, action: \.editAffiliation) { EditMyAffiliationFeature() }
        .ifLet(\.$editInterests, action: \.editInterests) { OnboardingFeature() }
    }
}
