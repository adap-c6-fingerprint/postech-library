//
//  OnboardingFeature.swift
//  fingerprint-library
//

import Foundation
import ComposableArchitecture

@Reducer
struct OnboardingFeature {
    static let maxPreferenceCount = 3
    enum Step: Int, CaseIterable, Equatable {
        case welcome
        case affiliation
        case interests
    }
    // 시작 → 소속 → 선호 분류 순서로 진행한다.
    
    typealias AffiliationPath = RecommendationDataset.AffiliationPath
    
    @ObservableState
    struct State: Equatable {
        var step: Step = .welcome
        var dataset: RecommendationDataset = .empty
        // 소속 301개·선호 분류 20개 선택지. 앱에 넣은 하드데이터에서 읽는다.
        var optionsErrorMessage: String?
        var selectedParent: String?
        // 1단계: 상위 소속. 예: "POSTECH 학부"
        var selectedGroup: String?
        // 2단계: 그룹. 예: "학과 및 학부"
        var selectedAffiliation: AffiliationPath?
        // 3단계: 최종 소속. 이름이 아니라 세 단계 경로로 보관해 학부·대학원의 같은 학과를 구분한다.
        var selectedPreferences: [String] = []
        // 고른 순서대로 보관하는 선호 분류 이름. 예: ["수학", "역사"]
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
        
        var preferenceNames: [String] { dataset.preferenceNames }
        
        var isPreferenceLimitReached: Bool {
            selectedPreferences.count >= OnboardingFeature.maxPreferenceCount } // 관심사를 최대 개수(3개)까지 골랐는지 확인하는 Bool
        
        
        var isAffiliationComplete: Bool {
            selectedAffiliation != nil
        }
        
        var canFinish: Bool {
            isAffiliationComplete && !selectedPreferences.isEmpty && !isSaving
        }
    }
    
    enum Action {
        case task
        // ✅ 화면이 뜨면 선택지를 읽는다.
        case optionsLoaded(RecommendationDataset)
        case optionsFailed(String)
        case startButtonTapped
        case parentSelected(String)
        case groupSelected(String)
        case affiliationSelected(AffiliationPath)
        case nextButtonTapped
        case backButtonTapped
        // ✅ 내비게이션 뒤로가기(버튼·스와이프)로 화면이 pop될 때
        case preferenceToggled(String)
        case finishButtonTapped
        case saveSucceeded
        case saveFailed(String)
        case errorAlertDismissed
        case delegate(Delegate)
        
        @CasePathable
        enum Delegate: Equatable {
            case completed
        }
    }
    
    @Dependency(\.userProfileClient)
    var userProfileClient
    @Dependency(\.recommendationDatasetClient)
    var recommendationDatasetClient
    
    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .task:
                guard state.dataset.affiliationPaths.isEmpty else { return .none }
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
                
            case .startButtonTapped:
                state.step = .affiliation
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
                // 지금 고른 상위 소속·그룹에 속한 항목만 받는다.
                guard state.affiliationChoices.contains(path) else { return .none }
                state.selectedAffiliation = path
                return .none
                
            case .nextButtonTapped:
                guard state.isAffiliationComplete else { return .none }
                state.step = .interests
                return .none

            case .backButtonTapped:
                guard let previous = Step(rawValue: state.step.rawValue - 1) else { return .none }
                state.step = previous
                // ✅ 이전 단계로만 돌아가고, 이미 고른 소속·선호 분류는 그대로 둔다.
                return .none

            case let .preferenceToggled(name):
                if let index = state.selectedPreferences.firstIndex(of: name) {
                    state.selectedPreferences.remove(at: index)
                } else if state.preferenceNames.contains(name), !state.isPreferenceLimitReached {
                    state.selectedPreferences.append(name)
                }
                return .none
                
            case .finishButtonTapped:
                guard state.canFinish, let affiliation = state.selectedAffiliation else { return .none }
                state.isSaving = true
                let preferences = state.selectedPreferences
                return .run { [userProfileClient] send in
                    do {
                        try await userProfileClient.save(affiliation.key, affiliation.name, preferences)
                        // ✅ 소속 경로·최종 소속 이름(홈 제목용)·선호 분류 이름을 저장한다.
                        await send(.saveSucceeded)
                    } catch {
                        await send(.saveFailed(error.localizedDescription))
                    }
                }
                
            case .saveSucceeded:
                state.isSaving = false
                return .send(.delegate(.completed))
                
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
