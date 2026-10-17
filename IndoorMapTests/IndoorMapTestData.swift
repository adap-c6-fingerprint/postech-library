import Foundation
@testable import fingerprint_library

enum IndoorMapTestData {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)
    static let groundID = UUID(uuidString: "00000000-0000-4000-8000-000000000010")!
    static let upperID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
    static let point = IndoorMapCoordinate(latitude: 36.001, longitude: 129.001)
    static let square: [IndoorMapCoordinate] = [
        .init(latitude: 36, longitude: 129), .init(latitude: 36, longitude: 129.01),
        .init(latitude: 36.01, longitude: 129.01), .init(latitude: 36.01, longitude: 129),
        .init(latitude: 36, longitude: 129)
    ]
    static let hole: [IndoorMapCoordinate] = [
        .init(latitude: 36.004, longitude: 129.004), .init(latitude: 36.004, longitude: 129.006),
        .init(latitude: 36.006, longitude: 129.006), .init(latitude: 36.006, longitude: 129.004),
        .init(latitude: 36.004, longitude: 129.004)
    ]

    static func map() -> IndoorMap {
        IndoorMap(
            formatVersion: "1.0.0",
            venue: IndoorMapElement(sourceID: UUID(), kind: .venue, floorID: nil, category: nil,
                                    name: "테스트 건물", geometry: .polygon([square])),
            floors: [
                IndoorMapFloor(id: groundID, ordinal: 0, name: "1층", geometry: .polygon([square, hole])),
                IndoorMapFloor(id: upperID, ordinal: 4, name: "5층", geometry: .polygon([square, hole]))
            ], features: [], diagnostics: []
        )
    }

    static func position(floor: Int? = 4, age: TimeInterval = 0, accuracy: Double = 3) -> IndoorPosition {
        IndoorPosition(coordinate: point, floorOrdinal: floor, horizontalAccuracy: accuracy,
                       timestamp: now.addingTimeInterval(-age), source: .sensor)
    }
}
