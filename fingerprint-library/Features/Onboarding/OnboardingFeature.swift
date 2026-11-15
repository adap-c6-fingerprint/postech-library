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

    static func analyticsScreen(for step: Step, entry: Entry) -> AnalyticsScreen {
        // 단계와 진입 경로로 분석용 화면 이름을 고른다
        switch (entry, step) {
        case (.changeInterests, _): .myPageInterests
        // 마이페이지 → 관심 분야 변경에서 재사용할 때
        case (_, .welcome): .onboardingWelcome
        // 시작하기
        case (_, .affiliation): .onboardingAffiliation
        // 소속·학과 설정 (마이페이지에서 프로필 설정을 시작한 경우 포함)
        case (_, .interests): .onboardingInterests
        // 관심사 설정 (마이페이지에서 프로필 설정을 시작한 경우 포함)
        }
    }
    
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

        var analyticsScreen: AnalyticsScreen {
            OnboardingFeature.analyticsScreen(for: step, entry: entry)
        }
        // 지금 보이는 단계의 분석용 화면 이름
        
        var hasChangedInterests: Bool {
            Set(selectedPreferences) != Set(userProfile?.interests ?? [])
        }
        // 관심 분야 변경에서 처음 들어왔을 때와 선택이 달라졌는지 (순서는 보지 않는다)

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
            case continueSetupChosen
            // 건너뛰기 알림에서 "설정하기"를 고름
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
                analytics.record(.button(.later, on: state.analyticsScreen))
                // "다음에 할래요"
                state.alert = AlertState {
                    TextState("맞춤 정보 설정을 건너뛰시겠어요?")
                } actions: {
                    ButtonState(role: .cancel, action: .continueSetupChosen) {
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
                analytics.record(.button(.skipConfirmSkip, on: state.analyticsScreen))
                // 건너뛰기 알림 → "건너뛰기"
                state.isSkipNoticePresented = true
                return .none

            case .alert(.presented(.continueSetupChosen)):
                analytics.record(.button(.skipConfirmSetup, on: state.analyticsScreen))
                // 건너뛰기 알림 → "설정하기" (알림만 닫히고 소속 설정을 이어 간다)
                return .none

            case .skipNoticeConfirmed:
                state.$hasSkippedOnboarding.withLock { $0 = true }
                return .send(.delegate(.skipped))

            case .alert:
                return .none

            case let .parentSelected(parent):
                analytics.record(.button(.affiliationSelect, on: state.analyticsScreen, [.kind: .text(parent)]))
                // 소속 메뉴에서 고른 소속 (이미 고른 소속을 다시 골라도 기록)
                guard state.selectedParent != parent else { return .none }
                state.selectedParent = parent
                state.selectedAffiliation = nil
                return .none
                
            case let .affiliationSelected(path):
                guard state.affiliationChoices.contains(path) else { return .none }
                analytics.record(.button(.departmentSelect, on: state.analyticsScreen, [.kind: .text(path.name)]))
                // 학과 메뉴에서 고른 세부 소속
                state.selectedAffiliation = path
                return .none
                
            case .nextButtonTapped:
                guard state.isAffiliationComplete else { return .none }
                analytics.record(.button(.next, on: state.analyticsScreen))
                // 소속 선택이 끝난 뒤 "다음으로" 또는 왼쪽 스와이프
                state.step = .interests
                return .none

            case .backButtonTapped:
                guard let previous = Step(rawValue: state.step.rawValue - 1) else { return .none }
                analytics.record(.button(.back, on: state.analyticsScreen))
                // 뒤로가기 (step을 바꾸기 전이라 떠나는 단계의 화면 이름으로 기록)
                state.step = previous
                return .none

            case let .preferenceToggled(name):
                if let index = state.selectedPreferences.firstIndex(of: name) {
                    state.selectedPreferences.remove(at: index)
                    analytics.record(.button(.interestDeselect, on: state.analyticsScreen, [.kind: .text(name)]))
                    // 관심사 선택 해제 (kind = 해제한 관심사)
                } else if state.preferenceNames.contains(name) {
                    state.selectedPreferences.append(name)
                    analytics.record(.button(.interestSelect, on: state.analyticsScreen, [.kind: .text(name)]))
                    // 관심사 선택 (kind = 고른 관심사)
                }
                return .none
                
            case .finishButtonTapped where state.entry == .changeInterests:
                analytics.record(.button(.done, on: state.analyticsScreen))
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
                analytics.record(.button(.done, on: state.analyticsScreen))
                // 관심사 단계의 완료 버튼 (저장할 수 없는 상태에서 눌러도 누름은 기록)
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
