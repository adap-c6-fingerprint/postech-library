import ComposableArchitecture
import Foundation
import SwiftData
import Testing
@testable import fingerprint_library

@MainActor
struct OnboardingFeatureTests {
    @Test("관심사 키워드는 총류(A)와 서지학(Z)을 뺀 LCC 대분류를 한 번씩 맵핑한다")
    func interestsCoverLCCClasses() {
        let mapped = UserInterest.allCases.flatMap(\.lccClasses)
        let expected = Set(LCCOutline.subclasses.keys).subtracting(["A", "Z"])
        #expect(Set(mapped) == expected)
        #expect(mapped.count == expected.count)
        #expect(UserInterest.history.lccClasses == ["D", "E", "F"])
    }

    @Test("소속과 학과를 고른 뒤 관심사를 고르면 학과와 LCC 알파벳으로 저장하고 완료를 알린다")
    func completesWithDepartment() async {
        let saved = LockIsolated<(String, [String])?>(nil)
        let department = PostechDepartment.undergraduate(.semiconductorEngineering)
        let store = TestStore(initialState: OnboardingFeature.State()) {
            OnboardingFeature()
        } withDependencies: {
            $0.userProfileClient.save = { name, interests in saved.setValue((name, interests)) }
        }

        await store.send(.startButtonTapped) { $0.step = .affiliation }
        // 학과를 고르기 전에는 다음 단계로 넘어가지 않는다.
        await store.send(.statusSelected(.undergraduate)) { $0.status = .undergraduate }
        await store.send(.nextButtonTapped)
        await store.send(.departmentSelected(department)) { $0.department = department }
        await store.send(.nextButtonTapped) { $0.step = .interests }
        await store.send(.interestToggled(.science)) { $0.selectedInterests = [.science] }
        await store.send(.interestToggled(.history)) { $0.selectedInterests = [.science, .history] }
        await store.send(.finishButtonTapped) { $0.isSaving = true }
        await store.receive(\.saveSucceeded) { $0.isSaving = false }
        await store.receive(\.delegate.completed)

        #expect(saved.value?.0 == "반도체공학과")
        #expect(saved.value?.1 == ["Q", "D", "E", "F"])
    }

    @Test("학과가 없는 소속은 소속 이름을 학과 자리에 저장한다")
    func savesStatusNameWithoutDepartment() async {
        let savedName = LockIsolated<String?>(nil)
        var initialState = OnboardingFeature.State()
        initialState.step = .affiliation
        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.userProfileClient.save = { name, _ in savedName.setValue(name) }
        }

        await store.send(.statusSelected(.staff)) { $0.status = .staff }
        await store.send(.nextButtonTapped) { $0.step = .interests }
        await store.send(.interestToggled(.music)) { $0.selectedInterests = [.music] }
        await store.send(.finishButtonTapped) { $0.isSaving = true }
        await store.receive(\.saveSucceeded) { $0.isSaving = false }
        await store.receive(\.delegate.completed)

        #expect(savedName.value == "POSTECH 교직원")
    }

    @Test("소속을 바꾸면 이전 소속의 학과를 지우고, 다른 소속의 학과는 받지 않는다")
    func resetsDepartmentWhenStatusChanges() async {
        let undergraduate = PostechDepartment.undergraduate(.physics)
        var initialState = OnboardingFeature.State()
        initialState.step = .affiliation
        let store = TestStore(initialState: initialState) { OnboardingFeature() }

        await store.send(.statusSelected(.undergraduate)) { $0.status = .undergraduate }
        await store.send(.departmentSelected(undergraduate)) { $0.department = undergraduate }
        await store.send(.statusSelected(.graduate)) {
            $0.status = .graduate
            $0.department = nil
        }
        await store.send(.departmentSelected(undergraduate))
    }

    @Test("관심사를 고르지 않으면 저장하지 않고, 다시 누르면 선택을 해제한다")
    func requiresInterest() async {
        var initialState = OnboardingFeature.State()
        initialState.step = .interests
        initialState.status = .staff
        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.userProfileClient.save = { _, _ in Issue.record("관심사 없이 저장하면 안 됩니다.") }
        }

        await store.send(.finishButtonTapped)
        await store.send(.interestToggled(.law)) { $0.selectedInterests = [.law] }
        await store.send(.interestToggled(.law)) { $0.selectedInterests = [] }
        await store.send(.finishButtonTapped)
    }

    @Test("저장에 실패하면 오류를 보여주고 온보딩에 머문다")
    func showsSaveFailure() async {
        var initialState = OnboardingFeature.State()
        initialState.step = .interests
        initialState.status = .staff
        initialState.selectedInterests = [.law]
        let store = TestStore(initialState: initialState) {
            OnboardingFeature()
        } withDependencies: {
            $0.userProfileClient.save = { _, _ in throw UserProfileError.emptyDepartmentName }
        }

        await store.send(.finishButtonTapped) { $0.isSaving = true }
        await store.receive(\.saveFailed) {
            $0.isSaving = false
            $0.errorMessage = UserProfileError.emptyDepartmentName.localizedDescription
        }
        await store.send(.errorAlertDismissed) { $0.errorMessage = nil }
    }

    @Test("저장된 프로필이 없으면 온보딩을 띄우고, 마치면 닫는다")
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
        await store.send(.onboarding(.delegate(.completed))) { $0.onboarding = nil }
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

        try UserProfile.save(departmentName: "물리학과", interests: ["Q"], in: context)
        try UserProfile.save(departmentName: "POSTECH 교직원", interests: ["B", "K"], in: context)

        let profiles = try context.fetch(FetchDescriptor<UserProfile>())
        #expect(profiles.count == 1)
        #expect(profiles.first?.snapshot == UserProfileSnapshot(
            departmentName: "POSTECH 교직원", interests: ["B", "K"]
        ))
    }
}
