//
//  RoutingGeometry.swift
//  Fingerprint
//
//  Created by Codex on 9/29/26.
//

import Foundation

nonisolated enum RoutingGeometry {
    private static let earthRadiusMeters = 6_371_008.8

    static func isValid(_ coordinate: IndoorMapCoordinate) -> Bool {
        coordinate.latitude.isFinite
            && coordinate.longitude.isFinite
            && (-90.0...90.0).contains(coordinate.latitude)
            && (-180.0...180.0).contains(coordinate.longitude)
    }

    /// Great-circle distance in meters using the haversine formula.
    static func distanceMeters(
        from start: IndoorMapCoordinate,
        to end: IndoorMapCoordinate
    ) -> Double {
        let startLatitude = start.latitude.degreesToRadians
        let endLatitude = end.latitude.degreesToRadians
        let latitudeDelta = (end.latitude - start.latitude).degreesToRadians
        let longitudeDelta = (end.longitude - start.longitude).degreesToRadians

        let latitudeComponent = sin(latitudeDelta / 2)
        let longitudeComponent = sin(longitudeDelta / 2)
        let haversine = latitudeComponent * latitudeComponent
            + cos(startLatitude) * cos(endLatitude)
            * longitudeComponent * longitudeComponent
        let centralAngle = 2 * atan2(sqrt(haversine), sqrt(max(0, 1 - haversine)))

        return earthRadiusMeters * centralAngle
    }

    static func polylineLengthMeters(_ coordinates: [IndoorMapCoordinate]) -> Double {
        zip(coordinates, coordinates.dropFirst()).reduce(0) { length, pair in
            length + distanceMeters(from: pair.0, to: pair.1)
        }
    }
}

private extension Double {
    nonisolated var degreesToRadians: Double {
        self * .pi / 180
    }
}
