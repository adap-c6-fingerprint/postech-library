import Foundation

nonisolated struct IndoorMap: Equatable, Sendable {
    let formatVersion: String
    let venue: IndoorMapElement
    let floors: [IndoorMapFloor]
    let features: [IndoorMapElement]
    let diagnostics: [IndoorMapDiagnostic]
}

nonisolated struct IndoorMapFloor: Identifiable, Equatable, Sendable {
    let id: UUID
    let ordinal: Int
    let name: String
    let geometry: IndoorMapGeometry
}

nonisolated struct IndoorMapElement: Identifiable, Equatable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case venue, footprint, unit, section, fixture, opening, amenity
    }

    struct ID: Hashable, Sendable {
        let kind: Kind
        let sourceID: UUID
    }

    var id: ID { ID(kind: kind, sourceID: sourceID) }
    let sourceID: UUID
    let kind: Kind
    let floorID: UUID?
    let category: String?
    let name: String?
    let geometry: IndoorMapGeometry
}

nonisolated enum IndoorMapDiagnostic: Equatable, Sendable {
    case duplicateSourceID(UUID, featureTypes: [String])
}

nonisolated struct IndoorMapCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

nonisolated enum IndoorMapGeometry: Hashable, Sendable {
    case point(IndoorMapCoordinate)
    case lineString([IndoorMapCoordinate])
    case polygon([[IndoorMapCoordinate]])
    case multiPolygon([[[IndoorMapCoordinate]]])
}
