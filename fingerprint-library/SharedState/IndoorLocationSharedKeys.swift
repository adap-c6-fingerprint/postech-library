//
//  IndoorLocationSharedKeys.swift
//  fingerprint-library
//

import ComposableArchitecture
import Foundation

extension SharedReaderKey where Self == InMemoryKey<IndoorLocationSnapshot>.Default {
    /// LocationSessionFeature가 쓰는 현재 실내 위치 상태. 지도·길안내는 읽기만 한다.
    /// 앱을 다시 실행하면 비어 있는 상태로 시작한다.
    nonisolated static var indoorLocation: Self {
        Self[.inMemory("indoorLocation"), default: IndoorLocationSnapshot()]
    }
}
