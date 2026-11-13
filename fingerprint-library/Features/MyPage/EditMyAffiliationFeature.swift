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
        var selectedAffiliation: AffiliationPath?
        var errorMessage: String?
        @Shared(.userProfile) var userProfile: UserProfile?

        var savedAffiliationKey: [String] { userProfile?.affiliationKey ?? [] }

        var parents: [String] { dataset.parents }

        var groups: [String] {
            selectedParent.map { dataset.groups(in: $0) } ?? []
        }

        func affiliationChoices(in group: String) -> [AffiliationPath] {
            guard let selectedParent else { return [] }
            return dataset.paths(in: selectedParent, group: group)
        }

        var affiliationChoices: [AffiliationPath] {
            groups.flatMap(affiliationChoices(in:))
        }

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
                state.selectedParent = parent
                state.selectedAffiliation = nil
                return .none

            case let .affiliationSelected(path):
                guard state.affiliationChoices.contains(path) else { return .none }
                state.selectedAffiliation = path
                return .none

            case .changeButtonTapped:
                guard state.canSave, let affiliation = state.selectedAffiliation,
                      let current = state.userProfile else { return .none }
                do {
                    let updated = try current.updatingAffiliation(key: affiliation.key, departmentName: affiliation.name)
                    state.$userProfile.withLock { $0 = updated }
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
