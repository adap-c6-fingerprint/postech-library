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
            $0.recommendationDatasetClient.load = { await Self.dataset }
        }

        await store.send(.task)
        await store.receive(\.optionsLoaded) { $0.dataset = Self.dataset }
        #expect(store.state.parents == ["POSTECH 학부", "POSTECH 대학원"])
        #expect(store.state.preferenceNames == ["수학", "역사", "여행"])
    }

    @Test("소속 2단계(상위 소속·학과)와 선호 분류를 고르면 소속 경로·소속 이름·선호 분류 이름으로 함께 쓰는 프로필에 저장하고 완료를 알린다")
    func completesWithAffiliationPath() async throws {
        var initialState = OnboardingFeature.State()
        initialState.dataset = Self.dataset
        let store = TestStore(initialState: initialState) { OnboardingFeature() }

        await store.send(.startButtonTapped) { $0.step = .affiliation }
        await store.send(.parentSelected("POSTECH 대학원")) { $0.selectedParent = "POSTECH 대학원" }
        // 최종 소속을 고르기 전에는 다음 단계로 넘어가지 않는다.
        await store.send(.nextButtonTapped)
        await store.send(.affiliationSelected(Self.graduateMath)) { $0.selectedAffiliation = Self.graduateMath }
        await store.send(.nextButtonTapped) { $0.step = .interests }
        await store.send(.preferenceToggled("역사")) { $0.selectedPreferences = ["역사"] }
        await store.send(.preferenceToggled("수학")) { $0.selectedPreferences = ["역사", "수학"] }
        let expected = try UserProfile(
            affiliationKey: ["POSTECH 대학원", "일반대학원 학과", "수학과"],
            departmentName: "수학과",
            interests: ["역사", "수학"]
        )
        await store.send(.finishButtonTapped) {
            $0.$userProfile.withLock { $0 = expected }
        }
        await store.receive(\.delegate.completed)

        @Shared(.userProfile) var userProfile: UserProfile?
        #expect(userProfile == expected)
        // 다른 화면이 같은 키로 읽어도 온보딩에서 저장한 값과 같다.
    }

    @Test("상위 소속을 바꾸면 학과 선택을 지우고, 다른 상위 소속의 학과는 받지 않는다")
    func resetsLowerSelections() async {
        var initialState = OnboardingFeature.State()
        initialState.dataset = Self.dataset
        initialState.step = .affiliation
        let store = TestStore(initialState: initialState) { OnboardingFeature() }

        await store.send(.parentSelected("POSTECH 학부")) { $0.selectedParent = "POSTECH 학부" }
        #expect(store.state.groups == ["학과 및 학부"])
        #expect(store.state.affiliationChoices(in: "학과 및 학부") == [Self.undergraduateMath])
        // 학과 메뉴는 그룹을 묶음 제목으로 쓰고, 그 아래에 학과를 보여준다.
        // 같은 이름이어도 대학원 수학과는 학부의 선택지가 아니다.
        await store.send(.affiliationSelected(Self.graduateMath))
        await store.send(.affiliationSelected(Self.undergraduateMath)) {
            $0.selectedAffiliation = Self.undergraduateMath
        }
        await store.send(.parentSelected("POSTECH 대학원")) {
            $0.selectedParent = "POSTECH 대학원"
            $0.selectedAffiliation = nil
        }
        // 다른 상위 소속의 학과는 받지 않는다.
        await store.send(.affiliationSelected(Self.undergraduateMath))
    }

    @Test("선호 분류를 고르지 않으면 저장하지 않고, 다시 누르면 선택을 해제한다")
    func requiresPreference() async {
        var initialState = OnboardingFeature.State()
        initialState.dataset = Self.dataset
        initialState.step = .interests
        initialState.selectedParent = "POSTECH 학부"
        initialState.selectedAffiliation = Self.undergraduateMath
        let store = TestStore(initialState: initialState) { OnboardingFeature() }

        await store.send(.finishButtonTapped)
        // 선호 분류 없이 누르면 프로필을 저장하지 않는다(상태 변화 없음).
        await store.send(.preferenceToggled("여행")) { $0.selectedPreferences = ["여행"] }
        await store.send(.preferenceToggled("여행")) { $0.selectedPreferences = [] }
        // 선택지에 없는 이름은 받지 않는다.
        await store.send(.preferenceToggled("없는 분류"))
        await store.send(.finishButtonTapped)
    }

    @Test("프로필 규칙에 어긋나면 저장하지 않고 오류를 보여주며 온보딩에 머문다")
    func showsSaveFailure() async {
        let blankName = Path(parent: "POSTECH 학부", group: "학과 및 학부", name: " ")
        var initialState = OnboardingFeature.State()
        initialState.dataset = Self.dataset
        initialState.step = .interests
        initialState.selectedAffiliation = blankName
        initialState.selectedPreferences = ["수학"]
        let store = TestStore(initialState: initialState) { OnboardingFeature() }

        await store.send(.finishButtonTapped) {
            $0.errorMessage = UserProfileError.invalidAffiliation.localizedDescription
        }
        #expect(store.state.userProfile == nil)
        await store.send(.errorAlertDismissed) { $0.errorMessage = nil }
    }

    @Test("저장된 프로필이 없으면 온보딩을 띄우고, 마치면 닫고 첫 홈 표시로 표시한다")
    func appShowsOnboardingWithoutProfile() async {
        let store = TestStore(initialState: AppFeature.State()) { AppFeature() }

        await store.send(.profileCheckRequested)
        await store.receive(\.legacyProfileLoaded) {
            $0.hasCheckedProfile = true
            $0.onboarding = OnboardingFeature.State()
        }
        await store.send(.onboarding(.delegate(.completed))) {
            $0.onboarding = nil
            $0.home.isFirstVisitAfterOnboarding = true
        }
    }

    @Test("저장된 프로필이 있으면 온보딩 없이 탭 화면으로 간다")
    func appSkipsOnboardingWithProfile() async throws {
        @Shared(.userProfile) var userProfile: UserProfile?
        let profile = try UserProfile(affiliationKey: Self.undergraduateMath.key, departmentName: "수학과", interests: ["수학"])
        $userProfile.withLock { $0 = profile }
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.legacyUserProfileClient.load = {
                Issue.record("새 저장소에 프로필이 있으면 이전 저장소를 읽지 않습니다.")
                return nil
            }
        }

        await store.send(.profileCheckRequested) { $0.hasCheckedProfile = true }
    }

    @Test("새 저장소가 비어 있고 이전 저장소(SwiftData)에 프로필이 있으면 옮기고 온보딩을 건너뛴다")
    func appMigratesLegacyProfile() async throws {
        let profile = try UserProfile(affiliationKey: Self.graduateAI.key, departmentName: "인공지능대학원", interests: ["역사"])
        let store = TestStore(initialState: AppFeature.State()) {
            AppFeature()
        } withDependencies: {
            $0.legacyUserProfileClient.load = { profile }
        }

        await store.send(.profileCheckRequested)
        await store.receive(\.legacyProfileLoaded) {
            $0.hasCheckedProfile = true
            $0.$userProfile.withLock { $0 = profile }
        }
        #expect(store.state.onboarding == nil)
    }

    @Test("이전 저장소의 프로필은 새 모델로 바꾸고, 소속 경로가 없는 옛 형식은 옮기지 않는다 (Q7)")
    func convertsLegacyProfile() throws {
        let container = try ModelContainer(
            for: LegacyUserProfileStore.UserProfile.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = container.mainContext
        #expect(legacyUserProfile(in: context) == nil)

        context.insert(LegacyUserProfileStore.UserProfile(departmentName: "반도체공학과", interests: ["A", "P"]))
        try context.save()
        #expect(legacyUserProfile(in: context) == nil)
        // 소속 경로가 없는 옛 형식은 새 프로필 규칙을 통과하지 못해 온보딩을 다시 받는다.

        try context.delete(model: LegacyUserProfileStore.UserProfile.self)
        context.insert(LegacyUserProfileStore.UserProfile(
            departmentName: "인공지능대학원", interests: ["역사", "여행"], affiliationKey: Self.graduateAI.key
        ))
        try context.save()
        let expected = try UserProfile(
            affiliationKey: Self.graduateAI.key, departmentName: "인공지능대학원", interests: ["역사", "여행"]
        )
        #expect(legacyUserProfile(in: context) == expected)
    }

    @Test("소속 경로는 세 단계가 모두 있어야 하고, 관심 분야는 공백을 지우고 중복을 뺀다")
    func validatesProfile() throws {
        #expect(throws: UserProfileError.invalidAffiliation) {
            try UserProfile(affiliationKey: ["POSTECH 학부", "수학과"], departmentName: "수학과", interests: ["수학"])
        }
        #expect(throws: UserProfileError.emptyDepartmentName) {
            try UserProfile(affiliationKey: Self.undergraduateMath.key, departmentName: " ", interests: ["수학"])
        }
        let profile = try UserProfile(
            affiliationKey: Self.undergraduateMath.key, departmentName: " 수학과 ", interests: [" 수학", "수학", "역사"]
        )
        #expect(profile.departmentName == "수학과")
        #expect(profile.interests == ["수학", "역사"])

        let moved = try profile.updatingAffiliation(key: Self.graduateAI.key, departmentName: "인공지능대학원")
        #expect(moved.interests == ["수학", "역사"])
        // 소속만 바꾸면 관심 분야는 그대로 남는다.
        let retargeted = try profile.updatingInterests(["여행"])
        #expect(retargeted.affiliationKey == Self.undergraduateMath.key)
        // 관심 분야만 바꾸면 소속은 그대로 남는다.
    }
}
