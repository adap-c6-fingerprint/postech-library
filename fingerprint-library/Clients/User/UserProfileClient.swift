import Foundation
import SwiftData
import ComposableArchitecture

nonisolated struct UserProfileClient: Sendable {
    var load: @Sendable () async throws -> UserProfileSnapshot
    // 저장된 프로필을 복사본으로 돌려준다. 없으면 임시값으로 만든 뒤 돌려준다.
    var hasProfile: @Sendable () async throws -> Bool
    // 온보딩을 마쳐 프로필이 저장돼 있는지 확인한다.
    var save: @Sendable (_ departmentName: String, _ interests: [String]) async throws -> Void
    // 온보딩에서 입력한 학과(소속)와 관심사 알파벳을 저장한다.
}

extension UserProfileClient: DependencyKey {
    static let liveValue = Self(
        load: {
            try await MainActor.run {
                try UserProfile.fetchOrCreate(in: UserProfile.sharedContainer.mainContext).snapshot
            }
            // mainContext는 메인 스레드에서만 쓸 수 있어서 MainActor에서 읽는다.
        },
        hasProfile: {
            try await MainActor.run {
                try UserProfile.exists(in: UserProfile.sharedContainer.mainContext)
            }
        },
        save: { departmentName, interests in
            try await MainActor.run {
                try UserProfile.save(
                    departmentName: departmentName,
                    interests: interests,
                    in: UserProfile.sharedContainer.mainContext
                )
            }
        }
    )

    static let testValue = Self(
        load: { UserProfileSnapshot(departmentName: "", interests: []) },
        hasProfile: { true },
        save: { _, _ in }
    )
}

extension DependencyValues {
    var userProfileClient: UserProfileClient {
        get { self[UserProfileClient.self] }
        set { self[UserProfileClient.self] = newValue }
    }
}

extension UserProfile {
    static let sharedContainer: ModelContainer = {
        do {
            return try ModelContainer(for: UserProfile.self)
        } catch {
            fatalError("UserProfile 저장소를 만들지 못했습니다: \(error)")
        }
    }()
    // 앱 화면(MyApp)과 UserProfileClient가 같은 저장소를 쓰도록 하나만 만든다.
}
