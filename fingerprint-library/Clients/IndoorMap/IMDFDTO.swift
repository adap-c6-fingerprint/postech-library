import Foundation

/// 도면 manifest에서 변환에 필요한 형식 버전만 읽는 전송 모델.
nonisolated struct IMDFManifestDTO: Decodable {
    let version: String
}

/// GeoJSON 파일의 최상위 타입과 Feature 목록을 보관한다. 의미 검증은 Mapper가 수행한다.
nonisolated struct IMDFFeatureCollectionDTO: Decodable {
    let type: String
    let features: [IMDFFeatureDTO]
}

/// 원본 Feature의 식별자·종류·속성·도형을 도메인 모델로 바꾸기 전까지 보관한다.
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

/// 층 연결과 표시를 위해 사용하는 IMDF 속성의 부분 집합.
///
/// 종류마다 필요한 속성이 달라 선택 값으로 읽고, 필수 여부와 참조 관계는 Mapper에서 검사한다.
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

/// 지원하는 GeoJSON 도형을 좌표 배열의 차원에 맞춰 읽는다.
///
/// 여기서는 JSON 구조만 해석한다. 좌표 순서·범위·ring 폐쇄 여부는 Mapper의 책임이다.
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
