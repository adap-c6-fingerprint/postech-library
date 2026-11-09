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
        case terms
        case affiliation
        case interests
    }
    // 시작 → 약관 동의 → 소속 → 선호 분류 순서로 진행한다.
    

    enum Entry: Equatable {
        case firstRun
        // 앱을 처음 켰을 때: 시작 → 약관 동의 → 소속 → 선호 분류를 모두 거친다.
        case changeInterests
        // 마이페이지 "관심 분야 변경하기": 선호 분류 화면만 그대로 띄우고, 관심 분야만 바꿔 저장한다.
        case setupFromMyPage
        // 온보딩을 건너뛰어 프로필이 없을 때 마이페이지에서 들어온 경우: 소속 → 선호 분류를 거쳐 프로필을 새로 만든다.
    }

    typealias AffiliationPath = RecommendationDataset.AffiliationPath
    
    @ObservableState
    struct State: Equatable {
        var entry: Entry = .firstRun
        var step: Step = .welcome
        var dataset: RecommendationDataset = .empty
        // 소속 301개·선호 분류 20개 선택지. 앱에 넣은 하드데이터에서 읽는다.
        var optionsErrorMessage: String?
        var selectedParent: String?
        // 1단계: 상위 소속. 예: "POSTECH 학부"
        var selectedAffiliation: AffiliationPath?
        // 2단계: 최종 소속. 이름이 아니라 세 단계 경로(상위 소속·그룹·이름)로 보관해 학부·대학원의 같은 학과를 구분한다.
        // 그룹(예: "학과 및 학부")은 따로 고르지 않고, 학과 메뉴 안에서 학과들을 묶는 제목으로만 보여준다.
        var selectedPreferences: [String] = []
        // 고른 순서대로 보관하는 선호 분류 이름. 예: ["수학", "역사"]
        var errorMessage: String?
        var isCompleted = false
        // 프로필을 저장해 흐름을 마쳤는지. 마친 뒤 화면이 한꺼번에 닫힐 때 생기는 pop을 뒤로가기로 오해하지 않게 한다.
        @Shared(.userProfile) var userProfile: UserProfile?
        // 앱 전체가 함께 쓰는 프로필. 온보딩을 마치면 여기에 저장한다.
        @Shared(.hasSkippedOnboarding) var hasSkippedOnboarding: Bool
        @Presents var alert: AlertState<Action.Alert>?
        // "다음에 할래요"를 눌렀을 때 뜨는 건너뛰기 확인 팝업
        var isSkipNoticePresented = false
        // 건너뛴 뒤 "맞춤 정보 설정을 건너뛰었어요." 팝업. 시스템 알림창은 버튼 색을 바꿀 수 없어 화면에 직접 그린 팝업으로 띄운다.
        
        var parents: [String] { dataset.parents }
        
        var groups: [String] {
            selectedParent.map { dataset.groups(in: $0) } ?? []
        }
        // 학과 메뉴의 묶음 제목들. 고른 상위 소속에 속한 그룹을 원본 순서대로.

        func affiliationChoices(in group: String) -> [AffiliationPath] {
            guard let selectedParent else { return [] }
            return dataset.paths(in: selectedParent, group: group)
        }
        // 한 묶음 제목 아래에 보여줄 학과들

        var affiliationChoices: [AffiliationPath] {
            groups.flatMap(affiliationChoices(in:))
        }
        // 고른 상위 소속의 모든 학과
        
        var preferenceNames: [String] { dataset.preferenceNames }
        
        var isPreferenceLimitReached: Bool {
            selectedPreferences.count >= OnboardingFeature.maxPreferenceCount } // 관심사를 최대 개수(3개)까지 골랐는지 확인하는 Bool
        
        
        var isAffiliationComplete: Bool {
            selectedAffiliation != nil
        }
        
        var canFinish: Bool {
            switch entry {
            case .firstRun, .setupFromMyPage:
                isAffiliationComplete && !selectedPreferences.isEmpty
            case .changeInterests:
                !selectedPreferences.isEmpty && selectedPreferences != userProfile?.interests
                // 저장된 관심 분야와 같으면 저장하지 않는다.
            }
        }

        static func changingInterests() -> Self {
        // 마이페이지에서 선호 분류 화면으로 바로 들어갈 때의 상태.
            var state = Self()
            state.entry = .changeInterests
            state.step = .interests
            state.selectedPreferences = state.userProfile?.interests ?? []
            // 온보딩에서 저장한 관심 분야를 미리 골라 둔다.
            return state
        }

        static func settingUpProfile() -> Self {
        // 마이페이지에서 프로필을 처음 만들 때의 상태. 소속 화면부터 시작한다.
            var state = Self()
            state.entry = .setupFromMyPage
            state.step = .affiliation
            return state
        }
    }
    
    enum Action {
        case task
        // ✅ 화면이 뜨면 선택지를 읽는다.
        case optionsLoaded(RecommendationDataset)
        case optionsFailed(String)
        case startButtonTapped
        case termsAgreeButtonTapped
        // 약관 동의 화면의 "동의하고 계속하기"
        case termsDeclineButtonTapped
        // 약관 동의 화면의 "동의 안하고 종료하기"
        case skipButtonTapped
        // 소속 화면의 "다음에 할래요"
        case alert(PresentationAction<Alert>)
        case skipNoticeConfirmed
        // "맞춤 정보 설정을 건너뛰었어요." 팝업의 "확인했어요"
        case parentSelected(String)
        case affiliationSelected(AffiliationPath)
        case nextButtonTapped
        case backButtonTapped
        // ✅ 내비게이션 뒤로가기(버튼·스와이프)로 화면이 pop될 때
        case preferenceToggled(String)
        case finishButtonTapped
        case errorAlertDismissed
        case delegate(Delegate)
        
        @CasePathable
        enum Delegate: Equatable {
            case completed
            case skipped
            // 맞춤 정보 설정을 건너뛰었다. 앱은 온보딩을 닫고 홈으로 간다.
        }

        @CasePathable
        enum Alert: Equatable {
            case skipConfirmed
            // 건너뛰기 확인 팝업의 "건너뛰기"
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
                // 선택지에 없는 이름(예: 이전 형식의 관심사)은 칩이 없어 해제할 수 없으므로 뺀다.
                return .none
                
            case let .optionsFailed(message):
                state.optionsErrorMessage = message
                return .none
                
            case .startButtonTapped:
                if state.entry == .firstRun, state.step == .welcome {
                    analytics.record(.init(.onboardingStarted))
                }
                state.step = .terms
                return .none

            case .termsAgreeButtonTapped:
                guard state.step == .terms else { return .none }
                state.step = .affiliation
                return .none

            case .termsDeclineButtonTapped:
                // 피그마 주석 "앱 종료": 약관에 동의하지 않으면 앱을 종료한다. (사용자님 결정, 2026-11-06)
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
                // 피그마 "다음에 할래요 눌렀을 때 팝업". "설정하기"는 팝업만 닫고 소속 화면에 머문다.
                return .none

            case .alert(.presented(.skipConfirmed)):
                // 홈(지도)으로 넘어가면 위치 권한 팝업이 바로 뜨므로, 안내 팝업은 온보딩 화면에서 먼저 띄운다.
                // "확인했어요"를 누르기 전에는 홈으로 넘어가지 않는다.
                state.isSkipNoticePresented = true
                return .none

            case .skipNoticeConfirmed:
                state.$hasSkippedOnboarding.withLock { $0 = true }
                // 건너뛴 기록을 남겨 다음 실행 때 온보딩을 다시 띄우지 않는다.
                return .send(.delegate(.skipped))

            case .alert:
                return .none

            case let .parentSelected(parent):
                guard state.selectedParent != parent else { return .none }
                // 상위 소속을 바꾸면 아래 단계의 선택을 지운다.
                state.selectedParent = parent
                state.selectedAffiliation = nil
                return .none
                
            case let .affiliationSelected(path):
                // 지금 고른 상위 소속에 속한 항목만 받는다.
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
                
            case .finishButtonTapped where state.entry == .changeInterests:
                guard state.canFinish, let current = state.userProfile else { return .none }
                do {
                    let updated = try current.updatingInterests(state.selectedPreferences)
                    // 소속·학과는 그대로 두고 관심 분야만 바꾼다.
                    state.$userProfile.withLock { $0 = updated }
                    // 함께 쓰는 프로필을 바꾸면 홈의 '당신을 위한 추천' 등 이 값을 쓰는 모든 곳에 반영된다.
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
                    // 소속 경로·최종 소속 이름(홈 제목용)·선호 분류 이름으로 프로필을 만든다.
                    state.$userProfile.withLock { $0 = profile }
                    state.isCompleted = true
                    // 마이페이지에서 처음 설정한 경우, 곧 부모가 이 상태를 지우며 소속·선호 분류 화면을 함께 닫는다.
                    if state.entry == .firstRun {
                        analytics.record(.init(.onboardingCompleted, [
                            .selectedCount: .integer(profile.interests.count)
                        ]))
                    }
                    // 완료 이벤트는 처음 실행 온보딩에서만 기록한다. 마이페이지에서 처음 설정한 경우는 넣지 않는다.
                    // 앱 전체가 함께 쓰는 프로필에 저장한다. 파일 저장은 자동으로 된다.
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
