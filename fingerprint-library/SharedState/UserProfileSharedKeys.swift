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
    // nil이면 아직 온보딩을 마치지 않았다는 뜻이다.
    // 테스트에서는 실제 파일 대신 메모리에 저장된다(swift-sharing 기본 동작).
}

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    nonisolated static var hasSkippedOnboarding: Self {
        Self[.appStorage("hasSkippedOnboarding"), default: false]
    }
    // 온보딩 소속 화면에서 "다음에 할래요 → 건너뛰기"를 골랐는지. true면 프로필이 없어도 온보딩을 다시 띄우지 않는다.
}
