import CryptoKit
import Foundation

/// 도면과 함께 사용할 길찾기 그래프·서가 목적지·층간 거리 자료를 읽고 일치 여부를 검사한다.
///
/// 지도 표시 로딩과 분리되어 있으므로 이 자료가 없어도 도면과 층 선택은 유지할 수 있다.
nonisolated struct BundledIndoorNavigationLoader {
    /// 현재 지원하는 schema 1 데이터셋에서 해시로 고정하는 지도 파일 목록.
    /// 도서관의 새 export 자료를 받으면 해당 계약과의 호환성을 별도로 확인해야 한다.
    static let mapFiles = ["manifest.json", "venue.geojson", "level.geojson", "footprint.geojson",
                           "unit.geojson", "fixture.geojson", "opening.geojson", "amenity.geojson"]

    /// 현재 화면의 도서관 지도와 연결할 번들 길찾기 자료를 읽는다.
    ///
    /// `dataset.json`이 아직 없으면 다른 건물의 자료로 대체하지 않고 준비 전 상태를 반환한다.
    /// 파일 확인과 후속 로딩은 MainActor 밖에서 실행한다.
    /// - Parameters:
    ///   - map: 이미 화면에 표시 중인 도서관 지도.
    ///   - bundle: `IndoorMaps/POSTECHLibrary`를 포함하는 번들.
    /// - Returns: 화면 지도와 일치하는 그래프·서가·거리 자료.
    /// - Throws: ``IndoorNavigationLoadError/notPrepared``, 자료 오류 또는 `CancellationError`.
    @concurrent
    func loadLibrary(on map: IndoorMap, in bundle: Bundle = .main) async throws -> IndoorNavigationData {
        try Task.checkCancellation()
        guard let root = bundle.url(forResource: "IndoorMaps", withExtension: nil) else {
            throw IndoorMapLoadError.missingResource("IndoorMaps/POSTECHLibrary")
        }
        let directory = root.appendingPathComponent("POSTECHLibrary", isDirectory: true)
        guard FileManager.default.fileExists(atPath: directory.appendingPathComponent("dataset.json").path) else {
            throw IndoorNavigationLoadError.notPrepared
        }
        return try await load(directory: directory, on: map)
    }

    /// 기존 개발 도면의 목업 길찾기 자료를 회귀 검증용으로 읽는다.
    ///
    /// 호환 정책과 시연 데이터셋 식별자를 함께 검사한다. 앱 기본 의존성은 이 진입점을 사용하지 않는다.
    /// - Parameters:
    ///   - map: 함께 검증할 기존 개발 지도.
    ///   - bundle: C5 데이터셋을 포함하는 번들.
    /// - Returns: `c5-demo`의 목업 서가와 경로 자료.
    /// - Throws: 파일·해시·참조·데이터셋 모드 오류 또는 작업 취소 오류.
    func loadC5(on map: IndoorMap, in bundle: Bundle = .main) async throws -> IndoorNavigationData {
        guard let root = bundle.url(forResource: "IndoorMaps", withExtension: nil) else {
            throw IndoorMapLoadError.missingResource("IndoorMaps/C5/dataset.json")
        }
        let data = try await load(directory: root.appendingPathComponent("C5"), on: map, policy: .c5Compatibility)
        guard data.shelves.datasetID == "c5-demo", data.shelves.mode == .mock else {
            throw IndoorMapLoadError.invalidData(file: "shelves.json", reason: "C5는 시연용 목업 매핑만 사용합니다.")
        }
        return data
    }

    /// 해시·지도 내용·개정 식별자가 일치하는 데이터셋만 해석한다.
    ///
    /// 파일 해시를 확인한 뒤 고정된 도면을 다시 읽어 `map`과 비교하고, 그래프와 서가 참조를 검사한다.
    /// 층간 거리 자료가 있으면 모든 층간 연결의 거리·출처·근거도 확인한다.
    /// 해시 일치는 실제 보행 가능성이나 실측 정확도를 보증하지 않으며, IMDF 형식 버전도 지도 개정 번호가 아니다.
    /// - Parameters:
    ///   - directory: `dataset.json`, `IMDFData`, 그래프·서가 파일을 포함하는 데이터셋 폴더.
    ///   - map: 데이터셋 도면과 비교할 화면 지도.
    ///   - policy: 고정된 IMDF를 읽을 때 적용할 UUID 충돌 정책.
    /// - Returns: 탐색과 서가 조회에 사용할 검증된 ``IndoorNavigationData``.
    /// - Throws: 파일·해시·참조·거리 자료 오류 또는 `CancellationError`.
    @concurrent
    func load(directory: URL, on map: IndoorMap, policy: IMDFImportPolicy = .strict) async throws -> IndoorNavigationData {
        try Task.checkCancellation()
        let manifest: Manifest = try decode(read("dataset.json", at: directory), file: "dataset.json")
        guard manifest.schemaVersion == 1, Set(manifest.mapFilesSHA256.keys) == Set(Self.mapFiles) else {
            throw invalid("dataset.json", "지원하지 않는 데이터셋 schema 또는 지도 파일 목록입니다.")
        }
        for name in Self.mapFiles {
            try Task.checkCancellation()
            _ = try verified("IMDFData/" + name, at: directory, hash: manifest.mapFilesSHA256[name]!)
        }
        let graphData = try verified("routing-graph.geojson", at: directory, hash: manifest.routingSHA256)
        let shelfData = try verified("shelves.json", at: directory, hash: manifest.shelvesSHA256)
        let pinnedMap = try await BundledIndoorMapLoader().load(
            directory: directory.appendingPathComponent("IMDFData"), policy: policy
        )
        guard pinnedMap == map else { throw invalid("dataset.json", "화면 지도와 고정된 데이터셋이 다릅니다.") }
        try Task.checkCancellation()
        let graphDTO: RoutingGraphDTO = try decode(graphData, file: "routing-graph.geojson")
        let (graph, diagnostics) = try RoutingGraphMapper().map(graphDTO, on: map, layoutVersion: manifest.layoutVersion)
        let shelfDTO: ShelfDirectoryDTO = try decode(shelfData, file: "shelves.json")
        let shelves = try ShelfDirectoryMapper().map(shelfDTO, on: map, graph: graph, datasetID: manifest.datasetID)
        var distances: [String: RouteEdgeDistance] = [:]
        if let hash = manifest.crossFloorDistancesSHA256 {
            let file = "cross-floor-distances.json"
            let dto: DistanceManifest = try decode(verified(file, at: directory, hash: hash), file: file)
            let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
            let edges = Dictionary(uniqueKeysWithValues: graph.edges.map { ($0.id, $0) })
            let crossFloorIDs = Set(graph.edges.filter { nodes[$0.fromNodeID]?.floorID != nodes[$0.toNodeID]?.floorID }.map(\.id))
            guard dto.schemaVersion == 1, dto.datasetID == manifest.datasetID,
                  dto.layoutVersion == graph.layoutVersion,
                  Set(dto.edges.map(\.edgeID)) == crossFloorIDs,
                  Set(dto.edges.map(\.edgeID)).count == dto.edges.count else {
                throw invalid(file, "거리 자료의 버전·층간 연결 ID가 일치하지 않습니다.")
            }
            for entry in dto.edges {
                guard entry.meters.isFinite, entry.meters > 0, !entry.basis.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                    throw invalid(file, "층간 거리와 근거를 확인하세요.")
                }
                guard let edge = edges[entry.edgeID], let from = nodes[edge.fromNodeID], let to = nodes[edge.toNodeID],
                      entry.meters >= RoutingGeometry.distanceMeters(from: from.coordinate, to: to.coordinate) else {
                    throw invalid(file, "층간 이동거리는 양 끝점의 수평 직선거리 이상이어야 합니다.")
                }
                distances[entry.edgeID] = .init(meters: entry.meters, source: entry.source)
            }
        }
        try Task.checkCancellation()
        return IndoorNavigationData(graph: graph, shelves: shelves, diagnostics: diagnostics, transitionDistances: distances)
    }

    /// 파일을 읽고 누락과 그 밖의 읽기 실패를 파일명과 함께 구분한다.
    private func read(_ file: String, at directory: URL) throws -> Data {
        do { return try Data(contentsOf: directory.appendingPathComponent(file)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw IndoorMapLoadError.missingResource(file)
        } catch { throw invalid(file, error.localizedDescription) }
    }

    /// 파일의 SHA-256이 manifest에 기록한 값과 같을 때만 원본 바이트를 반환한다.
    private func verified(_ file: String, at directory: URL, hash: String) throws -> Data {
        let data = try read(file, at: directory)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == hash else { throw invalid(file, "데이터셋에 기록된 SHA-256과 다릅니다. 묶음을 다시 가져오세요.") }
        return data
    }

    /// DTO 해석 실패를 원본 파일의 자료 오류로 변환한다.
    private func decode<T: Decodable>(_ data: Data, file: String) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw invalid(file, error.localizedDescription) }
    }

    private func invalid(_ file: String, _ reason: String) -> IndoorMapLoadError {
        .invalidData(file: file, reason: reason)
    }

    /// 도면·그래프·서가·선택적 층간 거리 파일을 하나의 데이터셋으로 묶는 manifest.
    private struct Manifest: Decodable {
        let schemaVersion: Int
        let datasetID: String
        let layoutVersion: String
        let mapFilesSHA256: [String: String]
        let routingSHA256: String
        let shelvesSHA256: String
        let crossFloorDistancesSHA256: String?

        enum CodingKeys: String, CodingKey {
            case schemaVersion = "schema_version"
            case datasetID = "dataset_id"
            case layoutVersion = "layout_version"
            case mapFilesSHA256 = "map_files_sha256"
            case routingSHA256 = "routing_sha256"
            case shelvesSHA256 = "shelves_sha256"
            case crossFloorDistancesSHA256 = "cross_floor_distances_sha256"
        }
    }

    /// 층간 연결별 거리와 측정·추정 출처를 보관하는 별도 자료.
    private struct DistanceManifest: Decodable {
        let schemaVersion: Int
        let datasetID: String
        let layoutVersion: String
        let edges: [Entry]
        /// 그래프의 한 층간 연결에 대응하는 거리·출처·근거.
        struct Entry: Decodable {
            let edgeID: String
            let meters: Double
            let source: RouteEdgeDistance.Source
            let basis: String
            enum CodingKeys: String, CodingKey { case meters, source, basis; case edgeID = "edge_id" }
        }
        enum CodingKeys: String, CodingKey {
            case edges
            case schemaVersion = "schema_version"
            case datasetID = "dataset_id"
            case layoutVersion = "layout_version"
        }
    }
}
