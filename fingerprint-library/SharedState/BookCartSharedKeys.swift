//
//  BookCartSharedKeys.swift
//  fingerprint-library
//

import ComposableArchitecture
import Foundation

extension SharedKey where Self == AppStorageKey<[BookCartItem]>.Default {
    nonisolated static var bookCart: Self {
        Self[.appStorage("bookCartItems"), default: []]
    }
}

extension SharedKey where Self == AppStorageKey<Bool>.Default {
    nonisolated static var hasShownCartGuidanceLimitAlert: Self {
        Self[.appStorage("hasShownCartGuidanceLimitAlert"), default: false]
    }
}
