import ComposableArchitecture
import Foundation
import SwiftData
import Testing
@testable import fingerprint_library

// ✅ 이슈 #237: 소속 3단계 선택과 선호 분류 20개 기준으로 다시 작성했다.
@MainActor
struct OnboardingFeatureTests {
    typealias Path = RecommendationDataset.AffiliationPath

    private static let undergraduateMath = Path(parent: "POSTECH 학부", group: "학과 및 학부", name: "수학과")
    private static let graduateMath = Path(parent: "POSTECH 대학원", group: "일반대학원 학과", name: "수학과")
    private static let graduateAI = Path(parent: "POSTECH 대학원", group: "독립 대학원 및 학부", name: "인공지능대학원")

    private static let dataset = RecommendationDataset(
        books: [:],
        affiliations: [(undergraduateMath, []), (graduateMath, []), (graduateAI, [])],
        preferences: [("수학", []), ("역사", []), ("여행", [])]
    )

    @Test("관심사 키워드는 총류(A)와 서지학(Z)을 뺀 LCC 대분류를 한 번씩 맵핑한다")
    func interestsCoverLCCClasses() {
        // 온보딩에서는 더 쓰지 않지만 기존 추천 코드(Q9: 호출만 끊음)가 남아 있으므로 유지한다.
        let mapped = UserInterest.allCases.flatMap(\.lccClasses)
        let expected = Set(LCCOutline.subclasses.keys).subtracting(["A", "Z"])
        #expect(Set(mapped) == expected)
        #expect(mapped.count == expected.count)
        #expect(UserInterest.history.lccClasses == ["D", "E", "F"])
    }

    @Test("선택지를 하드데이터에서 읽어 상위 소속을 원본 순서대로 보여준다")
    func loadsOptions() async {
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.recommendationDatasetClient.load = { Self.dataset }
        }

        await store.send(.task)
        await store.receive(\.optionsLoaded) { $0.dataset = Self.dataset }
        #expect(store.state.parents == ["POSTECH 학부", "POSTECH 대학원"])
        #expect(store.state.preferenceNames == ["수학", "역사", "여행"])
    }

    @Test("소속 3단계와 선호 분류를 고르면 소속 경로·소속 이름·선호 분류 이름으로 저장하고 완료를 알린다")
    func completesWithAffiliationPath() async {
        let saved = LockIsolated<([String], String, [String])?>(nil)
        var initialState = OnboardingFeature.State()
        initialState.dataset = Self.dataset
        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.userProfileClient.save = { key, name, preferences in saved.setValue((key, name, preferences)) }
        }

        await store.send(.startButtonTapped) { $0.step = .affiliation }
        await store.send(.parentSelected("POSTECH 대학원")) { $0.selectedParent = "POSTECH 대학원" }
        // 최종 소속을 고르기 전에는 다음 단계로 넘어가지 않는다.
        await store.send(.nextButtonTapped)
        await store.send(.groupSelected("일반대학원 학과")) { $0.selectedGroup = "일반대학원 학과" }
        await store.send(.affiliationSelected(Self.graduateMath)) { $0.selectedAffiliation = Self.graduateMath }
        await store.send(.nextButtonTapped) { $0.step = .interests }
        await store.send(.preferenceToggled("역사")) { $0.selectedPreferences = ["역사"] }
        await store.send(.preferenceToggled("수학")) { $0.selectedPreferences = ["역사", "수학"] }
        await store.send(.finishButtonTapped) { $0.isSaving = true }
        await store.receive(\.saveSucceeded) { $0.isSaving = false }
        await store.receive(\.delegate.completed)

        #expect(saved.value?.0 == ["POSTECH 대학원", "일반대학원 학과", "수학과"])
        #expect(saved.value?.1 == "수학과")
        #expect(saved.value?.2 == ["역사", "수학"])
    }

    @Test("상위 소속이나 그룹을 바꾸면 아래 단계 선택을 지우고, 다른 그룹의 항목은 받지 않는다")
    func resetsLowerSelections() async {
        var initialState = OnboardingFeature.State()
        initialState.dataset = Self.dataset
        initialState.step = .affiliation
        let store = TestStore(initialState: initialState) { OnboardingFeature() }

        await store.send(.parentSelected("POSTECH 학부")) { $0.selectedParent = "POSTECH 학부" }
        await store.send(.groupSelected("학과 및 학부")) { $0.selectedGroup = "학과 및 학부" }
        // 같은 이름이어도 대학원 수학과는 학부 그룹의 선택지가 아니다.
        await store.send(.affiliationSelected(Self.graduateMath))
        await store.send(.affiliationSelected(Self.undergraduateMath)) {
            $0.selectedAffiliation = Self.undergraduateMath
        }
        await store.send(.parentSelected("POSTECH 대학원")) {
            $0.selectedParent = "POSTECH 대학원"
            $0.selectedGroup = nil
            $0.selectedAffiliation = nil
        }
        // 다른 상위 소속의 그룹은 받지 않는다.
        await store.send(.groupSelected("학과 및 학부"))
    }

    @Test("선호 분류를 고르지 않으면 저장하지 않고, 다시 누르면 선택을 해제한다")
    func requiresPreference() async {
        var initialState = OnboardingFeature.State()
        initialState.dataset = Self.dataset
        initialState.step = .interests
        initialState.selectedParent = "POSTECH 학부"
        initialState.selectedGroup = "학과 및 학부"
        initialState.selectedAffiliation = Self.undergraduateMath
        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.userProfileClient.save = { _, _, _ in Issue.record("선호 분류 없이 저장하면 안 됩니다.") }
        }

        await store.send(.finishButtonTapped)
        await store.send(.preferenceToggled("여행")) { $0.selectedPreferences = ["여행"] }
        await store.send(.preferenceToggled("여행")) { $0.selectedPreferences = [] }
        // 선택지에 없는 이름은 받지 않는다.
        await store.send(.preferenceToggled("없는 분류"))
        await store.send(.finishButtonTapped)
    }

    @Test("저장에 실패하면 오류를 보여주고 온보딩에 머문다")
    func showsSaveFailure() async {
        var initialState = OnboardingFeature.State()
        initialState.dataset = Self.dataset
        initialState.step = .interests
        initialState.selectedAffiliation = Self.undergraduateMath
        initialState.selectedPreferences = ["수학"]
        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.userProfileClient.save = { _, _, _ in throw UserProfileError.emptyDepartmentName }
        }

        await store.send(.finishButtonTapped) { $0.isSaving = true }
        await store.receive(\.saveFailed) {
            $0.isSaving = false
            $0.errorMessage = UserProfileError.emptyDepartmentName.localizedDescription
        }
        await store.send(.errorAlertDismissed) { $0.errorMessage = nil }
    }

    @Test("저장된 프로필이 없으면 온보딩을 띄우고, 마치면 닫고 첫 홈 표시로 표시한다")
    func appShowsOnboardingWithoutProfile() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userProfileClient.hasProfile = { false }
        }

        await store.send(.profileCheckRequested)
        await store.receive(\.profileChecked) {
            $0.hasCheckedProfile = true
            $0.onboarding = OnboardingFeature.State()
        }
        await store.send(.onboarding(.delegate(.completed))) {
            $0.onboarding = nil
            $0.home.isFirstVisitAfterOnboarding = true
        }
    }

    @Test("저장된 프로필이 있으면 온보딩 없이 탭 화면으로 간다")
    func appSkipsOnboardingWithProfile() async {
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.userProfileClient.hasProfile = { true }
        }

        await store.send(.profileCheckRequested)
        await store.receive(\.profileChecked) { $0.hasCheckedProfile = true }
    }

    @Test("온보딩 저장은 기존 프로필을 덮어쓰고 프로필을 하나만 남긴다")
    func saveOverwritesSingleProfile() throws {
        let container = try ModelContainer(
            for: UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        #expect(try !UserProfile.exists(in: context))

        try UserProfile.save(
            affiliationKey: Self.undergraduateMath.key, departmentName: "수학과", interests: ["수학"], in: context
        )
        try UserProfile.save(
            affiliationKey: Self.graduateAI.key, departmentName: "인공지능대학원", interests: ["역사", "여행"],
            in: context
        )

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.snapshot == UserProfileSnapshot(
            departmentName: "인공지능대학원", interests: ["역사", "여행"], affiliationKey: Self.graduateAI.key
        ))
        #expect(try UserProfile.exists(in: context))
    }

    @Test("소속 경로가 없는 이전 형식의 프로필은 온보딩을 다시 받는다 (Q7)")
    func legacyProfileRequiresOnboarding() throws {
        let container = try ModelContainer(
            for: UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        context.insert(try UserProfile(departmentName: "반도체공학과", interests: ["A", "P"]))
        try context.save()

        #expect(try !UserProfile.exists(in: context))
    }

    @Test("소속 경로는 세 단계가 모두 있어야 저장한다")
    func rejectsIncompleteAffiliation() throws {
        let container = try ModelContainer(
            for: UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        #expect(throws: UserProfileError.invalidAffiliation) {
            try UserProfile.save(
                affiliationKey: ["POSTECH 학부", "수학과"], departmentName: "수학과", interests: ["수학"],
                in: container.mainContext
            )
        }
    }
}
