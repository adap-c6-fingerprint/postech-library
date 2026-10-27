import Foundation

/// IMDF 전송 형식과 MapKit에 의존하지 않는 지도 모델.
///
/// Clients에서 원본을 검증한 뒤 만들며 Features는 이 값을 이용해 층별 도형을 표시한다.
/// 길찾기 노드와 도서 정보는 이 모델에 포함하지 않는다.
nonisolated struct IndoorMap: Equatable, Sendable {
    /// IMDF 형식 버전. 같은 버전의 파일이라도 지도 내용이나 개정은 다를 수 있다.
    let formatVersion: String
    /// 건물 전체를 대표하는 하나의 venue 요소.
    let venue: IndoorMapElement
    /// 원본 ordinal과 ID를 보존한 층 목록. Mapper가 ordinal 순으로 정렬한다.
    let floors: [IndoorMapFloor]
    /// 층별 표시 요소와 층이 지정되지 않는 footprint 요소.
    let features: [IndoorMapElement]
    /// 호환 정책으로 허용한 원본 자료 문제. 성공 로딩이 모든 원본 문제의 부재를 뜻하지 않는다.
    let diagnostics: [IndoorMapDiagnostic]
}

/// 하나의 층을 식별하고 표시 이름·외곽 도형을 보관한다.
nonisolated struct IndoorMapFloor: Identifiable, Equatable, Sendable {
    let id: UUID
    /// IMDF의 층 순서 값. 화면에 표시할 층 이름은 `name`을 사용한다.
    let ordinal: Int
    let name: String
    let geometry: IndoorMapGeometry
}

/// 지도 위에 표시할 구역·가구·출입구·시설 등의 도형과 원본 식별 정보.
/// 서가처럼 보여도 별도 도착 지점 매핑 없이는 길찾기 목적지로 취급하지 않는다.
nonisolated struct IndoorMapElement: Identifiable, Equatable, Sendable {
    /// 도형의 해석과 MapKit 표시 순서·스타일을 구분하는 원본 요소 종류.
    enum Kind: String, Hashable, Sendable {
        case venue, footprint, unit, section, fixture, opening, amenity
    }

    /// 화면에서 종류가 다른 요소를 구분하기 위한 복합 식별자.
    struct ID: Hashable, Sendable {
        let kind: Kind
        let sourceID: UUID
    }

    /// C5 원본에 타입 간 UUID 충돌이 있어 원본 ID와 feature 종류를 함께 사용한다.
    var id: ID { ID(kind: kind, sourceID: sourceID) }
    let sourceID: UUID
    let kind: Kind
    /// 연결된 원본 층 ID. 건물 외곽 footprint처럼 층을 지정하지 않는 요소는 nil이다.
    let floorID: UUID?
    let category: String?
    let name: String?
    let geometry: IndoorMapGeometry
}

/// 호환 로딩에서 보존한 원본 자료의 진단 정보.
nonisolated enum IndoorMapDiagnostic: Equatable, Sendable {
    case duplicateSourceID(UUID, featureTypes: [String])
}

/// 미터 단위 화면 좌표가 아닌 WGS 84 위도·경도 좌표.
nonisolated struct IndoorMapCoordinate: Hashable, Sendable {
    let latitude: Double
    let longitude: Double
}

/// Polygon의 첫 ring은 외곽선, 나머지는 내부 구멍이다.
/// MultiPolygon은 서로 분리된 여러 Polygon을 원본 구조대로 보관한다.
nonisolated enum IndoorMapGeometry: Hashable, Sendable {
    case point(IndoorMapCoordinate)
    case lineString([IndoorMapCoordinate])
    case polygon([[IndoorMapCoordinate]])
    case multiPolygon([[[IndoorMapCoordinate]]])
}
