//
//  LegacyUserProfileClient.swift
//  fingerprint-library
//
//  이전 버전이 SwiftData에 저장한 사용자 프로필을 새 저장소로 한 번만 옮길 때 쓴다.
//

import ComposableArchitecture
import Foundation

nonisolated struct LegacyUserProfileClient: Sendable {
    var load: @Sendable () async -> UserProfile?
}

extension LegacyUserProfileClient: DependencyKey {
    static let liveValue = Self(load: {
        await MainActor.run { loadLegacyUserProfile() }
    })

    static let testValue = Self(load: { nil })
}

nonisolated extension DependencyValues {
    var legacyUserProfileClient: LegacyUserProfileClient {
        get { self[LegacyUserProfileClient.self] }
        set { self[LegacyUserProfileClient.self] = newValue }
    }
}
