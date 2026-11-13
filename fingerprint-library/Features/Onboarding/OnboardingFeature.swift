//
//  OnboardingFeature.swift
//  fingerprint-library
//

import Foundation
import ComposableArchitecture

@Reducer
struct OnboardingFeature {
    enum Step: Int, CaseIterable, Equatable {
        case welcome
        case affiliation
        case interests
    }

    enum Entry: Equatable {
        case firstRun
        case changeInterests
        case setupFromMyPage
    }

    typealias AffiliationPath = RecommendationDataset.AffiliationPath
    
    @ObservableState
    struct State: Equatable {
        var entry: Entry = .firstRun
        var step: Step = .welcome
        var dataset: RecommendationDataset = .empty
        var optionsErrorMessage: String?
        var selectedParent: String?
        var selectedAffiliation: AffiliationPath?
        var selectedPreferences: [String] = []
        var errorMessage: String?
        var isCompleted = false
        @Shared(.userProfile) var userProfile: UserProfile?
        @Shared(.hasSkippedOnboarding) var hasSkippedOnboarding: Bool
        @Presents var alert: AlertState<Action.Alert>?
        var isSkipNoticePresented = false

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

        var preferenceNames: [String] { dataset.preferenceNames }
        
        var isAffiliationComplete: Bool {
            selectedAffiliation != nil
        }
        
        var canFinish: Bool {
            switch entry {
            case .firstRun, .setupFromMyPage:
                isAffiliationComplete && !selectedPreferences.isEmpty
            case .changeInterests:
                !selectedPreferences.isEmpty && selectedPreferences != userProfile?.interests
            }
        }

        static func changingInterests() -> Self {
            var state = Self()
            state.entry = .changeInterests
            state.step = .interests
            state.selectedPreferences = state.userProfile?.interests ?? []
            return state
        }

        static func settingUpProfile() -> Self {
            var state = Self()
            state.entry = .setupFromMyPage
            state.step = .affiliation
            return state
        }
    }
    
    enum Action {
        case task
        case optionsLoaded(RecommendationDataset)
        case optionsFailed(String)
        case startButtonTapped
        case welcomeLaterButtonTapped

        case skipButtonTapped
        case alert(PresentationAction<Alert>)
        case skipNoticeConfirmed
        case parentSelected(String)
        case affiliationSelected(AffiliationPath)
        case nextButtonTapped
        case backButtonTapped
        case preferenceToggled(String)
        case finishButtonTapped
        case errorAlertDismissed
        case delegate(Delegate)
        
        @CasePathable
        enum Delegate: Equatable {
            case completed
            case skipped
        }

        @CasePathable
        enum Alert: Equatable {
            case skipConfirmed
        }
    }
    
    @Dependency(\.recommendationDatasetClient)
    var recommendationDatasetClient
    @Dependency(\.analyticsClient) private var analytics
    
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
                state.selectedPreferences = state.selectedPreferences.filter(dataset.preferenceNames.contains)
                return .none
                
            case let .optionsFailed(message):
                state.optionsErrorMessage = message
                return .none
                
            case .startButtonTapped:
                if state.entry == .firstRun, state.step == .welcome {
                    analytics.record(.init(.onboardingStarted))
                }
                state.step = .affiliation
                return .none

            case .welcomeLaterButtonTapped:
                return .run { _ in exit(0) }
                
            case .skipButtonTapped:
                state.alert = AlertState {
                    TextState("맞춤 정보 설정을 건너뛰시겠어요?")
                } actions: {
                    ButtonState(role: .cancel) {
                        TextState("설정하기")
                    }
                    ButtonState(role: .destructive, action: .skipConfirmed) {
                        TextState("건너뛰기")
                    }
                } message: {
                    TextState("소속과 학과, 책 취향을 알려주시면\n나에게 어울리는 책을\n추천받을 수 있어요.")
                }
                return .none

            case .alert(.presented(.skipConfirmed)):
                state.isSkipNoticePresented = true
                return .none

            case .skipNoticeConfirmed:
                state.$hasSkippedOnboarding.withLock { $0 = true }
                return .send(.delegate(.skipped))

            case .alert:
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
                
            case .nextButtonTapped:
                guard state.isAffiliationComplete else { return .none }
                state.step = .interests
                return .none

            case .backButtonTapped:
                guard let previous = Step(rawValue: state.step.rawValue - 1) else { return .none }
                state.step = previous
                return .none

            case let .preferenceToggled(name):
                if let index = state.selectedPreferences.firstIndex(of: name) {
                    state.selectedPreferences.remove(at: index)
                } else if state.preferenceNames.contains(name) {
                    state.selectedPreferences.append(name)
                }
                return .none
                
            case .finishButtonTapped where state.entry == .changeInterests:
                guard state.canFinish, let current = state.userProfile else { return .none }
                do {
                    let updated = try current.updatingInterests(state.selectedPreferences)
                    state.$userProfile.withLock { $0 = updated }
                    return .send(.delegate(.completed))
                } catch {
                    state.errorMessage = error.localizedDescription
                    return .none
                }

            case .finishButtonTapped:
                guard state.canFinish, let affiliation = state.selectedAffiliation else { return .none }
                do {
                    let profile = try UserProfile(
                        affiliationKey: affiliation.key,
                        departmentName: affiliation.name,
                        interests: state.selectedPreferences
                    )
                    state.$userProfile.withLock { $0 = profile }
                    state.isCompleted = true
                    if state.entry == .firstRun {
                        analytics.record(.init(.onboardingCompleted, [
                            .selectedCount: .integer(profile.interests.count)
                        ]))
                    }
                    return .send(.delegate(.completed))
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
        .ifLet(\.$alert, action: \.alert)
    }
}
