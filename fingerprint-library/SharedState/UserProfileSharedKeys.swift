//
//  UserProfileSharedKeys.swift
//  fingerprint-library
//
//  사용자 프로필의 단일 저장 위치.
//  어느 화면이든 `@Shared(.userProfile) var userProfile`로 선언하면 모두 같은 값 하나를 가리킨다.
//  한 곳에서 `$userProfile.withLock { $0 = ... }`로 바꾸면 다른 화면에도 바로 반영되고, 파일에도 자동으로 저장된다.
//

import ComposableArchitecture
import Foundation

extension SharedKey where Self == FileStorageKey<UserProfile?>.Default {
    nonisolated static var userProfile: Self {
        Self[.fileStorage(.documentsDirectory.appending(component: "user-profile.json")), default: nil]
    }
}

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    nonisolated static var hasSkippedOnboarding: Self {
        Self[.appStorage("hasSkippedOnboarding"), default: false]
    }
}
