//
//  LegacyUserProfileClient.swift
//  fingerprint-library
//
//  이전 버전이 SwiftData에 저장한 사용자 프로필을 새 저장소로 한 번만 옮길 때 쓴다.
//

import ComposableArchitecture
import Foundation

// MARK: - 이전 저장소(SwiftData)에서 한 번만 옮기기

nonisolated struct LegacyUserProfileClient: Sendable {
    var load: @Sendable () async -> UserProfile?
    // 이전 버전이 SwiftData에 저장한 프로필을 읽는다. 없거나 읽지 못하면 nil.
    // 앱 시작 시 새 저장소가 비어 있을 때만 한 번 부른다. 이전 저장소는 지우지 않는다.
}

extension LegacyUserProfileClient: DependencyKey {
    static let liveValue = Self(load: {
        await MainActor.run { loadLegacyUserProfile() }
        // SwiftData의 mainContext는 메인 스레드에서만 쓸 수 있다.
    })

    static let testValue = Self(load: { nil })
}

extension DependencyValues {
    var legacyUserProfileClient: LegacyUserProfileClient {
        get { self[LegacyUserProfileClient.self] }
        set { self[LegacyUserProfileClient.self] = newValue }
    }
}
