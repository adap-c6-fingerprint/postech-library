//
//  IndoorLocationSharedKeys.swift
//  fingerprint-library
//

import ComposableArchitecture
import Foundation

extension SharedReaderKey where Self == InMemoryKey<IndoorLocationSnapshot>.Default {
    nonisolated static var indoorLocation: Self {
        Self[.inMemory("indoorLocation"), default: IndoorLocationSnapshot()]
    }
}
