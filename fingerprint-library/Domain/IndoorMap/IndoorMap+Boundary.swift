import Foundation

nonisolated struct LibraryEntrance: Equatable, Sendable {
    let coordinate: IndoorMapCoordinate
    let floorOrdinal: Int
}

nonisolated extension IndoorMap {
    var groundFootprint: IndoorMapGeometry? {
        features.first { $0.kind == .footprint && $0.category == "ground" }?.geometry
    }

    var principalEntrances: [LibraryEntrance] {
        features.compactMap { element in
            guard element.kind == .opening, element.category == "pedestrian.principal",
                  let floor = floors.first(where: { $0.id == element.floorID }),
                  case let .lineString(points) = element.geometry,
                  let first = points.first, let last = points.last else { return nil }
            return LibraryEntrance(
                coordinate: .init(latitude: (first.latitude + last.latitude) / 2,
                                  longitude: (first.longitude + last.longitude) / 2),
                floorOrdinal: floor.ordinal)
        }
    }
}
