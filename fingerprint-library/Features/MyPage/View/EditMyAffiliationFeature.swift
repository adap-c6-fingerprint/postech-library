//
//  EditMyAffiliationFeature.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  마이페이지에서 소속·세부 분류·학과를 바꾸는 화면 feature
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
        var selectedGroup: String?
        // 2단계: 그룹. 예: "학과 및 학부"
        var selectedAffiliation: AffiliationPath?
        // 3단계: 최종 소속
        var savedAffiliationKey: [String] = []
        // 지금 저장돼 있는 소속 경로. 같은 값으로는 저장하지 않는다.
        var interests: [String] = []
        // save가 관심 분야까지 함께 받으므로, 저장된 값을 그대로 다시 넘긴다.
        var isSaving = false
        var errorMessage: String?

        var parents: [String] { dataset.parents }

        var groups: [String] {
            selectedParent.map { dataset.groups(in: $0) } ?? []
        }

        var affiliationChoices: [AffiliationPath] {
            guard let selectedParent, let selectedGroup else { return [] }
            return dataset.paths(in: selectedParent, group: selectedGroup)
        }

        var canSave: Bool {
            guard let selectedAffiliation, !isSaving else { return false }
            return selectedAffiliation.key != savedAffiliationKey
        }
    }

    enum Action {
        case task
        case profileLoaded(UserProfileSnapshot)
        case optionsLoaded(RecommendationDataset)
        case optionsFailed(String)
        case parentSelected(String)
        case groupSelected(String)
        case affiliationSelected(AffiliationPath)
        case changeButtonTapped
        case saveSucceeded
        case saveFailed(String)
        case errorAlertDismissed
        case delegate(Delegate)

        @CasePathable
        enum Delegate: Equatable {
            case saved
            // 저장을 마쳤다. 마이페이지가 이 화면을 닫는다.
        }
    }

    @Dependency(\.userProfileClient) var userProfileClient
    @Dependency(\.recommendationDatasetClient) var recommendationDatasetClient

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.dataset.affiliationPaths.isEmpty else { return .none }
                return .merge(
                    .run { [userProfileClient] send in
                        if let profile = try? await userProfileClient.load() {
                            await send(.profileLoaded(profile))
                        }
                    },
                    .run { [recommendationDatasetClient] send in
                        do {
                            await send(.optionsLoaded(try await recommendationDatasetClient.load()))
                        } catch {
                            await send(.optionsFailed(error.localizedDescription))
                        }
                    }
                )

            case let .profileLoaded(profile):
                state.interests = profile.interests
                state.savedAffiliationKey = profile.affiliationKey
                let key = profile.affiliationKey
                guard key.count == 3 else { return .none }
                state.selectedParent = key[0]
                state.selectedGroup = key[1]
                state.selectedAffiliation = AffiliationPath(parent: key[0], group: key[1], name: key[2])
                // 지금 저장된 소속을 미리 골라 둔 상태로 보여준다.
                return .none

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
                state.selectedGroup = nil
                state.selectedAffiliation = nil
                return .none

            case let .groupSelected(group):
                guard state.groups.contains(group), state.selectedGroup != group else { return .none }
                state.selectedGroup = group
                state.selectedAffiliation = nil
                return .none

            case let .affiliationSelected(path):
                guard state.affiliationChoices.contains(path) else { return .none }
                // 지금 고른 상위 소속·그룹에 속한 항목만 받는다.
                state.selectedAffiliation = path
                return .none

            case .changeButtonTapped:
                guard state.canSave, let affiliation = state.selectedAffiliation else { return .none }
                state.isSaving = true
                let interests = state.interests
                return .run { [userProfileClient] send in
                    do {
                        try await userProfileClient.save(affiliation.key, affiliation.name, interests)
                        await send(.saveSucceeded)
                    } catch {
                        await send(.saveFailed(error.localizedDescription))
                    }
                }

            case .saveSucceeded:
                state.isSaving = false
                return .send(.delegate(.saved))

            case let .saveFailed(message):
                state.isSaving = false
                state.errorMessage = message
                return .none

            case .errorAlertDismissed:
                state.errorMessage = nil
                return .none

            case .delegate:
                return .none
            }
        }
    }
}
