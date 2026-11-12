//
//  BookCartSharedKeys.swift
//  fingerprint-library
//

import ComposableArchitecture
import Foundation

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    /// 책바구니에서 한 번에 안내할 수 있는 권수 한도 알림을 이미 보여 줬는지. 한 번 보여 주면 다시 띄우지 않는다.
    nonisolated static var hasShownCartGuidanceLimitAlert: Self {
        Self[.appStorage("hasShownCartGuidanceLimitAlert"), default: false]
    }
}
