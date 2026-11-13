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
    let configuration = ModelConfiguration()
    guard FileManager.default.fileExists(atPath: configuration.url.path()) else { return nil }
    guard let container = try? ModelContainer(
        for: LegacyUserProfileStore.UserProfile.self, configurations: configuration
    ) else { return nil }
    return legacyUserProfile(in: container.mainContext)
}

@MainActor
func legacyUserProfile(in context: ModelContext) -> UserProfile? {
    var descriptor = FetchDescriptor<LegacyUserProfileStore.UserProfile>()
    descriptor.fetchLimit = 1
    guard let stored = try? context.fetch(descriptor).first else { return nil }
    return try? UserProfile(
        affiliationKey: stored.affiliationKey,
        departmentName: stored.departmentName,
        interests: stored.interests
    )
}
