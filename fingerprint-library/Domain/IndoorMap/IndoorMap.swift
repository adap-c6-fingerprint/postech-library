import Foundation

/// IMDF 전송 형식과 MapKit에 의존하지 않는 지도 모델.
nonisolated struct IndoorMap: Sendable {
    let formatVersion: String
    let venue: IndoorMapFeature
    let floors: [IndoorMapFloor]
    let features: [IndoorMapFeature]
    let diagnostics: [IndoorMapDiagnostic]
}

nonisolated struct IndoorMapFloor: Identifiable, Sendable {
    let id: UUID
    let ordinal: Int
    let name: String
    let geometry: IndoorMapGeometry
}

nonisolated struct IndoorMapFeature: Identifiable, Sendable {
    enum Kind: String, Hashable, Sendable {
        case venue, footprint, unit, fixture, opening, amenity
    }

    struct ID: Hashable, Sendable {
        let kind: Kind
        let sourceID: UUID
    }

    /// C5 원본에 타입 간 UUID 충돌이 있어 원본 ID와 feature 종류를 함께 사용한다.
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

/// Polygon의 첫 ring은 외곽선, 나머지는 내부 구멍이다.
nonisolated enum IndoorMapGeometry: Hashable, Sendable {
    case point(IndoorMapCoordinate)
    case lineString([IndoorMapCoordinate])
    case polygon([[IndoorMapCoordinate]])
    case multiPolygon([[[IndoorMapCoordinate]]])
}
