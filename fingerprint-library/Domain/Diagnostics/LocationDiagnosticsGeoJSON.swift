import Foundation

/// 진단 기록을 geojson.io·QGIS에서 열 수 있는 GeoJSON FeatureCollection으로 바꾼다.
nonisolated enum LocationDiagnosticsGeoJSON {
    static func featureCollection(_ records: [LocationDiagnosticsRecord]) -> [String: Any] {
        var features: [[String: Any]] = []
        var rawByFloor: [Int?: [[Double]]] = [:]
        var displayedByFloor: [Int?: [[Double]]] = [:]
        var previous: LocationDiagnosticsRecord.LocationSample?

        for record in records {
            switch record {
            case let .location(sample):
                rawByFloor[sample.floorLevel, default: []].append([sample.longitude, sample.latitude])
                var properties: [String: Any] = [
                    "kind": "raw", "time": iso(sample.timestamp), "accuracy": sample.horizontalAccuracy
                ]
                if let floor = sample.floorLevel { properties["floor"] = floor }
                if let previous, sample.timestamp > previous.timestamp {
                    let jump = LocationJump(
                        meters: RoutingGeometry.distanceMeters(from: previous.coordinate, to: sample.coordinate),
                        seconds: sample.timestamp.timeIntervalSince(previous.timestamp))
                    properties["jumpMeters"] = jump.meters
                    properties["isJump"] = jump.isJump
                }
                features.append(point(sample.longitude, sample.latitude, properties))
                previous = sample
            case let .guidance(sample):
                if let latitude = sample.displayedLatitude, let longitude = sample.displayedLongitude {
                    displayedByFloor[sample.floorOrdinal, default: []].append([longitude, latitude])
                }
            case let .marker(marker):
                guard let latitude = marker.latitude, let longitude = marker.longitude else { continue }
                var properties: [String: Any] = ["kind": "marker-\(marker.kind.rawValue)", "time": iso(marker.at)]
                if let floor = marker.floorOrdinal { properties["floor"] = floor }
                if let label = marker.label { properties["label"] = label }
                features.append(point(longitude, latitude, properties))
            case let .route(route):
                for segment in route.segments where segment.coordinates.count >= 2 {
                    features.append(line(segment.coordinates.map { [$0[1], $0[0]] }, [
                        "kind": "route", "stopIndex": route.stopIndex, "reason": route.reason,
                        "floor": segment.floorOrdinal, "time": iso(route.at)
                    ]))
                }
            case .heading, .motion, .activity, .event:
                continue
            }
        }
        for (floor, coordinates) in rawByFloor where coordinates.count >= 2 {
            features.append(line(coordinates, ["kind": "raw-track", "floor": floor.map { $0 as Any } ?? NSNull()]))
        }
        for (floor, coordinates) in displayedByFloor where coordinates.count >= 2 {
            features.append(line(coordinates, ["kind": "displayed-track", "floor": floor.map { $0 as Any } ?? NSNull()]))
        }
        return ["type": "FeatureCollection", "features": features]
    }

    private static func point(_ longitude: Double, _ latitude: Double, _ properties: [String: Any]) -> [String: Any] {
        ["type": "Feature", "geometry": ["type": "Point", "coordinates": [longitude, latitude]], "properties": properties]
    }

    private static func line(_ coordinates: [[Double]], _ properties: [String: Any]) -> [String: Any] {
        ["type": "Feature", "geometry": ["type": "LineString", "coordinates": coordinates], "properties": properties]
    }

    private static func iso(_ date: Date) -> String {
        date.formatted(.iso8601.year().month().day().time(includingFractionalSeconds: true))
    }
}
