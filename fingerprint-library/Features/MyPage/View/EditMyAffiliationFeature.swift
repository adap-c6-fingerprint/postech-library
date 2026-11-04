//
//  EditMyAffiliationFeature.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  마이페이지에서 소속·학과를 바꾸는 화면 feature
//  선택 규칙은 온보딩(OnboardingFeature)의 소속 단계와 같다.
//

import ComposableArchitecture
import Foundation

@Reducer
struct EditMyAffiliationFeature {
    typealias AffiliationPath = RecommendationDataset.AffiliationPath

    @ObservableState
    struct State: Equatable {
        var dataset: RecommendationDataset = .empty
        var optionsErrorMessage: String?
        var selectedParent: String?
        // 1단계: 상위 소속. 예: "POSTECH 학부"
        var selectedAffiliation: AffiliationPath?
        // 2단계: 최종 소속. 그룹(예: "학과 및 학부")은 학과 메뉴의 묶음 제목으로만 쓴다.
        var errorMessage: String?
        @Shared(.userProfile) var userProfile: UserProfile?
        // 앱 전체가 함께 쓰는 프로필. 온보딩에서 저장한 바로 그 값이다.

        var savedAffiliationKey: [String] { userProfile?.affiliationKey ?? [] }
        // 지금 저장돼 있는 소속 경로. 같은 값으로는 저장하지 않는다.

        var parents: [String] { dataset.parents }

        var groups: [String] {
            selectedParent.map { dataset.groups(in: $0) } ?? []
        }
        // 학과 메뉴의 묶음 제목들

        func affiliationChoices(in group: String) -> [AffiliationPath] {
            guard let selectedParent else { return [] }
            return dataset.paths(in: selectedParent, group: group)
        }
        // 한 묶음 제목 아래에 보여줄 학과들

        var affiliationChoices: [AffiliationPath] {
            groups.flatMap(affiliationChoices(in:))
        }
        // 고른 상위 소속의 모든 학과

        var canSave: Bool {
            guard let selectedAffiliation, userProfile != nil else { return false }
            return selectedAffiliation.key != savedAffiliationKey
        }
    }

    enum Action {
        case task
        case optionsLoaded(RecommendationDataset)
        case optionsFailed(String)
        case parentSelected(String)
        case affiliationSelected(AffiliationPath)
        case changeButtonTapped
        case errorAlertDismissed
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case saved
            // 저장을 마쳤다. 마이페이지가 이 화면을 닫는다.
        }
    }

    @Dependency(\.recommendationDatasetClient) var recommendationDatasetClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.dataset.affiliationPaths.isEmpty else { return .none }
                if state.selectedAffiliation == nil,
                   let key = state.userProfile?.affiliationKey, let saved = AffiliationPath(key: key) {
                    state.selectedParent = saved.parent
                    state.selectedAffiliation = saved
                    // 지금 저장된 소속을 미리 골라 둔 상태로 보여준다.
                }
                return .run { [recommendationDatasetClient] send in
                    do {
                        await send(.optionsLoaded(try await recommendationDatasetClient.load()))
                    } catch {
                        await send(.optionsFailed(error.localizedDescription))
                    }
                }

            case let .optionsLoaded(dataset):
                state.dataset = dataset
                state.optionsErrorMessage = nil
                return .none

            case let .optionsFailed(message):
                state.optionsErrorMessage = message
                return .none

            case let .parentSelected(parent):
                guard state.selectedParent != parent else { return .none }
                // 상위 소속을 바꾸면 아래 단계의 선택을 지운다.
                state.selectedParent = parent
                state.selectedAffiliation = nil
                return .none

            case let .affiliationSelected(path):
                guard state.affiliationChoices.contains(path) else { return .none }
                // 지금 고른 상위 소속에 속한 항목만 받는다.
                state.selectedAffiliation = path
                return .none

            case .changeButtonTapped:
                guard state.canSave, let affiliation = state.selectedAffiliation,
                      let current = state.userProfile else { return .none }
                do {
                    let updated = try current.updatingAffiliation(key: affiliation.key, departmentName: affiliation.name)
                    // 관심 분야는 그대로 두고 소속·학과만 바꾼다.
                    state.$userProfile.withLock { $0 = updated }
                    // 함께 쓰는 프로필을 바꾸면 홈 등 이 값을 쓰는 모든 화면에 바로 반영된다.
                    return .send(.delegate(.saved))
                } catch {
                    state.errorMessage = error.localizedDescription
                    return .none
                }

            case .errorAlertDismissed:
                state.errorMessage = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
