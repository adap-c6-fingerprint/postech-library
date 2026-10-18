import CryptoKit
import Foundation

nonisolated struct BundledIndoorNavigationLoader {
    static let mapFiles = ["manifest.json", "venue.geojson", "level.geojson", "footprint.geojson",
                           "unit.geojson", "fixture.geojson", "opening.geojson", "amenity.geojson"]

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

    /// 해시가 맞는 리소스 묶음만 해석한다. IMDF 형식 버전을 지도 개정 번호로 사용하지 않는다.
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
                distances[entry.edgeID] = .init(meters: entry.meters, source: entry.source)
            }
        }
        try Task.checkCancellation()
        return IndoorNavigationData(graph: graph, shelves: shelves, diagnostics: diagnostics, transitionDistances: distances)
    }

    private func read(_ file: String, at directory: URL) throws -> Data {
        do { return try Data(contentsOf: directory.appendingPathComponent(file)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile {
            throw IndoorMapLoadError.missingResource(file)
        } catch { throw invalid(file, error.localizedDescription) }
    }

    private func verified(_ file: String, at directory: URL, hash: String) throws -> Data {
        let data = try read(file, at: directory)
        let actual = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == hash else { throw invalid(file, "데이터셋에 기록된 SHA-256과 다릅니다. 묶음을 다시 가져오세요.") }
        return data
    }

    private func decode<T: Decodable>(_ data: Data, file: String) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw invalid(file, error.localizedDescription) }
    }

    private func invalid(_ file: String, _ reason: String) -> IndoorMapLoadError {
        .invalidData(file: file, reason: reason)
    }

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

    private struct DistanceManifest: Decodable {
        let schemaVersion: Int
        let datasetID: String
        let layoutVersion: String
        let edges: [Entry]
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
