import Foundation

/// 원본 IMDF의 타입 간 UUID 중복을 처리하는 정책.
nonisolated enum IMDFImportPolicy: Sendable {
    /// 같은 파일 내부와 서로 다른 타입 사이의 UUID 중복을 모두 거부한다.
    case strict
    /// 기존 C5 회귀 데이터의 타입 간 UUID 중복을 허용하고 진단으로 남긴다.
    /// 같은 파일 내부의 UUID 중복은 이 정책에서도 오류다.
    case c5Compatibility
}

/// 현재 렌더링 대상: venue, level, footprint, unit, section, fixture, opening, amenity.
/// 나머지 IMDF 파일은 원본 그대로 보관하며 필요한 기능에서 별도로 해석한다.
/// 좌표·도형·참조를 검증하는 변환기이며 전체 IMDF 규격 인증이나 통행 가능성 검사는 수행하지 않는다.
nonisolated struct IMDFMapper {
    /// 디코딩한 FeatureCollection을 순수 지도 모델로 변환한다.
    ///
    /// Feature의 타입·UUID, 층 참조, 도형의 좌표와 ring을 검사한다.
    /// 시설의 층은 `level_id` 또는 연결된 unit에서 확인하며, 모순되면 임의로 선택하지 않는다.
    /// - Parameters:
    ///   - version: 로더에서 확인한 IMDF 형식 버전. 지도 개정 번호와는 다르다.
    ///   - collections: 확장자를 제외한 파일명으로 구분한 DTO 묶음.
    ///   - policy: 타입 간 UUID 충돌 처리 정책.
    /// - Returns: 지도·층별 요소·호환 진단을 포함하는 ``IndoorMap``.
    /// - Throws: 누락되거나 잘못된 자료의 파일명을 포함하는 ``IndoorMapLoadError``.
    func map(
        version: String,
        collections: [String: IMDFFeatureCollectionDTO],
        policy: IMDFImportPolicy = .strict
    ) throws -> IndoorMap {
        var ids: [UUID: [String]] = [:]
        for file in collections.keys.sorted() {
            guard let collection = collections[file], collection.type == "FeatureCollection" else {
                throw invalid(file, "FeatureCollection 형식이 아닙니다.")
            }
            var fileIDs = Set<UUID>()
            for feature in collection.features {
                guard feature.type == "Feature", feature.featureType == file else {
                    throw invalid(file, "Feature와 feature_type을 확인하세요: \(feature.id)")
                }
                guard fileIDs.insert(feature.id).inserted else {
                    throw invalid(file, "동일 파일에 중복 ID가 있습니다: \(feature.id)")
                }
                ids[feature.id, default: []].append(file)
            }
        }
        let duplicates = ids.filter { $0.value.count > 1 }.sorted { $0.key.uuidString < $1.key.uuidString }
        if policy == .strict, let duplicate = duplicates.first {
            throw IndoorMapLoadError.invalidData(
                file: duplicate.value.map { "\($0).geojson" }.joined(separator: ", "),
                reason: "타입 간 중복 ID가 있습니다: \(duplicate.key)"
            )
        }
        let diagnostics = duplicates.map { IndoorMapDiagnostic.duplicateSourceID($0.key, featureTypes: $0.value) }

        let floors = try required("level", in: collections).map { feature in
            guard let ordinal = feature.properties.ordinal else {
                throw invalid("level", "층 ordinal이 없습니다: \(feature.id)")
            }
            return IndoorMapFloor(
                id: feature.id,
                ordinal: ordinal,
                name: name(feature.properties.name) ?? String(ordinal),
                geometry: try geometry(feature.geometry, in: "level")
            )
        }.sorted { ($0.ordinal, $0.id.uuidString) < ($1.ordinal, $1.id.uuidString) }
        guard !floors.isEmpty else { throw invalid("level", "층이 없습니다.") }
        let floorIDs = Set(floors.map(\.id))
        var unitFloors: [UUID: UUID] = [:]
        for unit in try required("unit", in: collections) {
            guard let floorID = unit.properties.levelID, floorIDs.contains(floorID) else {
                throw invalid("unit", "존재하는 level_id가 필요합니다: \(unit.id)")
            }
            unitFloors[unit.id] = floorID
        }
        let venues = try required("venue", in: collections)
        guard venues.count == 1, let venue = venues.first else {
            throw invalid("venue", "하나의 venue가 필요합니다.")
        }

        var features: [IndoorMapElement] = []
        for kind in [IndoorMapElement.Kind.footprint, .unit, .section, .fixture, .opening, .amenity] {
            let elements: [IMDFFeatureDTO]
            if kind == .amenity || kind == .section {
                elements = collections[kind.rawValue]?.features ?? []
            } else {
                elements = try required(kind.rawValue, in: collections)
            }
            for feature in elements {
                let floorID: UUID?
                if kind == .amenity {
                    floorID = try amenityFloor(feature, unitFloors: unitFloors, floorIDs: floorIDs)
                } else if kind != .footprint {
                    guard let value = feature.properties.levelID, floorIDs.contains(value) else {
                        throw invalid(kind.rawValue, "존재하는 level_id가 필요합니다: \(feature.id)")
                    }
                    floorID = value
                } else {
                    floorID = nil
                }
                features.append(try map(feature, kind: kind, floorID: floorID))
            }
        }
        return IndoorMap(
            formatVersion: version, venue: try map(venue, kind: .venue),
            floors: floors, features: features, diagnostics: diagnostics
        )
    }

    /// 필요한 컬렉션이 전달됐는지 확인한다. 선택 파일의 부재 처리는 호출부에서 구분한다.
    private func required(
        _ file: String, in collections: [String: IMDFFeatureCollectionDTO]
    ) throws -> [IMDFFeatureDTO] {
        guard let collection = collections[file] else {
            throw IndoorMapLoadError.missingResource("\(file).geojson")
        }
        return collection.features
    }

    /// 시설이 참조하는 모든 unit과 명시된 level이 하나의 층을 가리킬 때만 그 층을 반환한다.
    ///
    /// 알 수 없는 참조·층 정보 누락·서로 다른 층의 혼합은 모두 자료 오류다.
    private func amenityFloor(
        _ feature: IMDFFeatureDTO, unitFloors: [UUID: UUID], floorIDs: Set<UUID>
    ) throws -> UUID {
        var candidates = Set<UUID>()
        for unitID in feature.properties.unitIDs ?? [] {
            guard let floorID = unitFloors[unitID] else {
                throw invalid("amenity", "알 수 없는 unit_ids 참조입니다: \(unitID)")
            }
            candidates.insert(floorID)
        }
        if let explicit = feature.properties.levelID {
            guard floorIDs.contains(explicit) else {
                throw invalid("amenity", "알 수 없는 level_id입니다: \(explicit)")
            }
            candidates.insert(explicit)
        }
        guard candidates.count == 1, let floorID = candidates.first else {
            throw invalid("amenity", "level_id와 unit_ids에서 하나의 층을 확인할 수 없습니다: \(feature.id)")
        }
        return floorID
    }

    /// 검증할 원본 Feature의 ID·종류·층·표시 정보를 보존하고 도형을 변환한다.
    private func map(
        _ feature: IMDFFeatureDTO, kind: IndoorMapElement.Kind, floorID: UUID? = nil
    ) throws -> IndoorMapElement {
        IndoorMapElement(
            sourceID: feature.id, kind: kind, floorID: floorID,
            category: feature.properties.category, name: name(feature.properties.name),
            geometry: try geometry(feature.geometry, in: kind.rawValue)
        )
    }

    /// 한국어, 영어, 언어 키 정렬 순으로 표시 이름을 선택한다.
    private func name(_ names: [String: String]?) -> String? {
        names?["ko"] ?? names?["en"] ?? names?.sorted(by: { $0.key < $1.key }).first?.value
    }

    /// 요소 종류에 허용된 geometry만 변환하고 Polygon의 내부 ring과 MultiPolygon을 보존한다.
    private func geometry(_ dto: IMDFGeometryDTO?, in file: String) throws -> IndoorMapGeometry {
        guard let dto else { throw invalid(file, "geometry가 없습니다.") }
        switch (file, dto) {
        case ("amenity", .point(let value)):
            return .point(try coordinate(value, in: file))
        case ("opening", .lineString(let values)):
            guard values.count >= 2 else { throw invalid(file, "LineString에는 두 좌표 이상이 필요합니다.") }
            return .lineString(try values.map { try coordinate($0, in: file) })
        case ("venue", .polygon(let rings)), ("level", .polygon(let rings)),
             ("footprint", .polygon(let rings)), ("unit", .polygon(let rings)),
             ("section", .polygon(let rings)), ("fixture", .polygon(let rings)):
            return .polygon(try polygon(rings, in: file))
        case ("venue", .multiPolygon(let polygons)), ("level", .multiPolygon(let polygons)),
             ("footprint", .multiPolygon(let polygons)), ("unit", .multiPolygon(let polygons)),
             ("section", .multiPolygon(let polygons)), ("fixture", .multiPolygon(let polygons)):
            guard !polygons.isEmpty else { throw invalid(file, "MultiPolygon이 비어 있습니다.") }
            return .multiPolygon(try polygons.map { try polygon($0, in: file) })
        default:
            throw invalid(file, "이 feature에 맞지 않는 geometry 형식입니다.")
        }
    }

    /// GeoJSON의 `[경도, 위도, 선택적 고도]`를 유효 범위 검사 후 지도 좌표로 변환한다.
    ///
    /// 현재 평면 지도 모델에는 위도와 경도만 저장하며 고도는 사용하지 않는다.
    private func coordinate(_ values: [Double], in file: String) throws -> IndoorMapCoordinate {
        guard (2...3).contains(values.count), values.allSatisfy(\.isFinite),
              (-180...180).contains(values[0]), (-90...90).contains(values[1]) else {
            throw invalid(file, "WGS 84 좌표는 [경도, 위도] 순서와 유효 범위를 지켜야 합니다.")
        }
        return IndoorMapCoordinate(latitude: values[1], longitude: values[0])
    }

    /// 각 ring의 최소 좌표 수와 폐쇄 여부를 검사한다. 첫 ring은 외곽, 이후 ring은 구멍이다.
    private func polygon(_ rings: [[[Double]]], in file: String) throws -> [[IndoorMapCoordinate]] {
        guard !rings.isEmpty else { throw invalid(file, "Polygon이 비어 있습니다.") }
        return try rings.map { ring in
            let coordinates = try ring.map { try coordinate($0, in: file) }
            guard coordinates.count >= 4, coordinates.first == coordinates.last else {
                throw invalid(file, "Polygon ring은 네 좌표 이상이어야 하며 닫혀 있어야 합니다.")
            }
            return coordinates
        }
    }

    private func invalid(_ file: String, _ reason: String) -> IndoorMapLoadError {
        .invalidData(file: "\(file).geojson", reason: reason)
    }
}
