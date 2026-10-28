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
    // 시작 → 소속·학과 → 관심사 순서로 진행한다.

    @ObservableState
    struct State: Equatable {
        var step: Step = .welcome
        var status: PostechStatus?
        var department: PostechDepartment?
        var selectedInterests: [UserInterest] = []
        // 고른 순서대로 보관한다.
        var isSaving = false
        var errorMessage: String?

        var isAffiliationComplete: Bool {
            guard let status else { return false }
            return !status.requiresDepartment || department?.status == status
        }
        // 학과가 필요 없는 소속(교직원·아카데미)은 소속만 고르면 완료다.

        var departmentName: String? {
            guard isAffiliationComplete, let status else { return nil }
            return department?.koreanName ?? status.koreanName
        }
        // 학과가 없는 소속은 소속 이름을 학과 자리에 저장한다. 예: "POSTECH 교직원"

        var canFinish: Bool {
            !selectedInterests.isEmpty && !isSaving
        }
    }

    enum Action {
        case startButtonTapped
        case statusSelected(PostechStatus)
        case departmentSelected(PostechDepartment)
        case nextButtonTapped
        case interestToggled(UserInterest)
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

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .startButtonTapped:
                state.step = .affiliation
                return .none

            case let .statusSelected(status):
                if state.department?.status != status {
                    state.department = nil
                }
                // 다른 소속으로 바꾸면 이전 소속의 학과는 지운다.
                state.status = status
                return .none

            case let .departmentSelected(department):
                guard department.status == state.status else { return .none }
                state.department = department
                return .none

            case .nextButtonTapped:
                guard state.isAffiliationComplete else { return .none }
                state.step = .interests
                return .none

            case let .interestToggled(interest):
                if let index = state.selectedInterests.firstIndex(of: interest) {
                    state.selectedInterests.remove(at: index)
                } else {
                    state.selectedInterests.append(interest)
                }
                return .none

            case .finishButtonTapped:
                guard state.canFinish, let departmentName = state.departmentName else { return .none }
                state.isSaving = true
                let interests = UserInterest.lccClasses(for: state.selectedInterests)
                return .run { [userProfileClient] send in
                    do {
                        try await userProfileClient.save(departmentName, interests)
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
