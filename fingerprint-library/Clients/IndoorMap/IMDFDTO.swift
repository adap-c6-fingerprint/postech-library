import Foundation

nonisolated struct IMDFManifestDTO: Decodable {
    let version: String
}

nonisolated struct IMDFFeatureCollectionDTO: Decodable {
    let type: String
    let features: [IMDFFeatureDTO]
}

nonisolated struct IMDFFeatureDTO: Decodable {
    let type: String
    let id: UUID
    let featureType: String
    let properties: IMDFPropertiesDTO
    let geometry: IMDFGeometryDTO?

    enum CodingKeys: String, CodingKey {
        case type, id, properties, geometry
        case featureType = "feature_type"
    }
}

nonisolated struct IMDFPropertiesDTO: Decodable {
    let ordinal: Int?
    let levelID: UUID?
    let unitIDs: [UUID]?
    let name: [String: String]?
    let category: String?

    enum CodingKeys: String, CodingKey {
        case ordinal, name, category
        case levelID = "level_id"
        case unitIDs = "unit_ids"
    }
}

nonisolated enum IMDFGeometryDTO: Decodable {
    case point([Double])
    case lineString([[Double]])
    case polygon([[[Double]]])
    case multiPolygon([[[[Double]]]])

    private enum CodingKeys: String, CodingKey {
        case type, coordinates
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(String.self, forKey: .type) {
        case "Point":
            self = .point(try container.decode([Double].self, forKey: .coordinates))
        case "LineString":
            self = .lineString(try container.decode([[Double]].self, forKey: .coordinates))
        case "Polygon":
            self = .polygon(try container.decode([[[Double]]].self, forKey: .coordinates))
        case "MultiPolygon":
            self = .multiPolygon(try container.decode([[[[Double]]]].self, forKey: .coordinates))
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: container, debugDescription: "지원하지 않는 지도 geometry 형식"
            )
        }
    }
}
