import Foundation

nonisolated enum IMDFImportPolicy: Sendable {
    case strict
    /// 원본 C5의 타입 간 UUID 중복만 허용하고 diagnostics로 보고한다.
    case c5Compatibility
}

/// 현재 렌더링 대상: venue, level, footprint, unit, fixture, opening, amenity.
/// 나머지 IMDF 파일은 원본 그대로 보관하며 필요한 기능에서 별도로 해석한다.
nonisolated struct IMDFMapper {
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
        for kind in [IndoorMapElement.Kind.footprint, .unit, .fixture, .opening, .amenity] {
            for feature in try required(kind.rawValue, in: collections) {
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

    private func required(
        _ file: String, in collections: [String: IMDFFeatureCollectionDTO]
    ) throws -> [IMDFFeatureDTO] {
        guard let collection = collections[file] else {
            throw IndoorMapLoadError.missingResource("\(file).geojson")
        }
        return collection.features
    }

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

    private func map(
        _ feature: IMDFFeatureDTO, kind: IndoorMapElement.Kind, floorID: UUID? = nil
    ) throws -> IndoorMapElement {
        IndoorMapElement(
            sourceID: feature.id, kind: kind, floorID: floorID,
            category: feature.properties.category, name: name(feature.properties.name),
            geometry: try geometry(feature.geometry, in: kind.rawValue)
        )
    }

    private func name(_ names: [String: String]?) -> String? {
        names?["ko"] ?? names?["en"] ?? names?.sorted(by: { $0.key < $1.key }).first?.value
    }

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
             ("fixture", .polygon(let rings)):
            return .polygon(try polygon(rings, in: file))
        case ("venue", .multiPolygon(let polygons)), ("level", .multiPolygon(let polygons)),
             ("footprint", .multiPolygon(let polygons)), ("unit", .multiPolygon(let polygons)),
             ("fixture", .multiPolygon(let polygons)):
            guard !polygons.isEmpty else { throw invalid(file, "MultiPolygon이 비어 있습니다.") }
            return .multiPolygon(try polygons.map { try polygon($0, in: file) })
        default:
            throw invalid(file, "이 feature에 맞지 않는 geometry 형식입니다.")
        }
    }

    private func coordinate(_ values: [Double], in file: String) throws -> IndoorMapCoordinate {
        guard (2...3).contains(values.count), values.allSatisfy(\.isFinite),
              (-180...180).contains(values[0]), (-90...90).contains(values[1]) else {
            throw invalid(file, "WGS 84 좌표는 [경도, 위도] 순서와 유효 범위를 지켜야 합니다.")
        }
        return IndoorMapCoordinate(latitude: values[1], longitude: values[0])
    }

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
