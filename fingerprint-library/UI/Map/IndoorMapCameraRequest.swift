//
//  IndoorMapCameraRequest.swift
//  fingerprint-library
//

import Foundation

nonisolated struct IndoorMapCameraRequest: Equatable, Sendable {
    enum Target: Equatable, Sendable {
        case initialFloor(UUID)
        case floor(UUID)
        case position(IndoorMapCoordinate, revealsShelfNumbers: Bool)
        case features([IndoorMapElement.ID])
        case route(IndoorRoute, featureIDs: [IndoorMapElement.ID])
        case navigation(BookNavigationCameraFocus)
    }
    let id: Int
    let target: Target
}

nonisolated struct BookNavigationCameraFocus: Equatable, Sendable {
    let floorID: UUID
    let coordinates: [IndoorMapCoordinate]
    let minimumSpanMeters: Double
}
