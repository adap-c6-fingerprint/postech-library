//
//  LegacyUserProfileStore.swift
//  fingerprint-library
//
//  Created by 이시온 on 10/27/26.
//
//  이전 버전의 프로필 저장소(SwiftData). 새 저장소(SharedState/UserProfileSharedKeys.swift)로 값을 한 번 옮길 때만 읽는다.
//  이미 온보딩을 마친 기기가 업데이트 후 온보딩을 다시 하지 않게 하려는 것이다.
//  TODO: 모든 테스트 기기가 새 버전으로 한 번 이상 실행된 뒤 이 파일을 지운다.
//

import Foundation
import SwiftData

enum LegacyUserProfileStore {
    @Model
    final class UserProfile {
    // 이전 버전과 같은 클래스 이름·속성이어야 기존 저장소를 읽을 수 있다. 이름과 속성을 바꾸지 않는다.
    // 새 프로필 모델(Domain/User/UserProfile.swift)과 이름이 겹쳐 이 enum 안에 둔다.
        var departmentName: String
        var interests: [String]
        var affiliationKey: [String] = []

        init(departmentName: String, interests: [String], affiliationKey: [String] = []) {
            self.departmentName = departmentName
            self.interests = interests
            self.affiliationKey = affiliationKey
        }
    }
}

@MainActor
func loadLegacyUserProfile() -> UserProfile? {
// 여기(파일 최상위)의 UserProfile은 새 모델이고, 옛 클래스는 LegacyUserProfileStore.UserProfile로 부른다.
// 이전 버전 기본 저장소(default.store)의 프로필을 새 모델로 바꿔 돌려준다. 없거나 읽지 못하면 nil.
    let configuration = ModelConfiguration()
    guard FileManager.default.fileExists(atPath: configuration.url.path()) else { return nil }
    // 파일이 없을 때 ModelContainer를 만들면 빈 저장소 파일이 새로 생기므로 먼저 확인한다.
    guard let container = try? ModelContainer(
        for: LegacyUserProfileStore.UserProfile.self, configurations: configuration
    ) else { return nil }
    return legacyUserProfile(in: container.mainContext)
}

@MainActor
func legacyUserProfile(in context: ModelContext) -> UserProfile? {
// 저장소에서 프로필 하나를 읽어 새 모델로 바꾼다. 테스트는 메모리 저장소의 context를 넘긴다.
    var descriptor = FetchDescriptor<LegacyUserProfileStore.UserProfile>()
    descriptor.fetchLimit = 1
    guard let stored = try? context.fetch(descriptor).first else { return nil }
    return try? UserProfile(
        affiliationKey: stored.affiliationKey,
        departmentName: stored.departmentName,
        interests: stored.interests
    )
    // 검사를 통과하지 못하는 값(예: 소속 경로가 없는 옛 형식)은 옮기지 않는다. 이 경우 온보딩을 다시 받는다.
}
