import CryptoKit
import Foundation

nonisolated struct BookRoutePreviewTestRoute: Equatable, Sendable {
    let origin: IndoorShelfLabel
    let destination: IndoorShelfLabel
    let start: IndoorPosition
    let route: IndoorRoute
    let guidance: RoutePreviewGuidance
}

/// navigation-only 묶음을 테스트 화면에만 연결한다. 원본 파일·기존 데이터셋 로더는 바꾸지 않는다.
nonisolated struct BookRoutePreviewTestRouteLoader {
    func load(on map: IndoorMap, labels: [IndoorShelfLabel], destination: IndoorShelfLabel,
              in bundle: Bundle = .main) async throws -> BookRoutePreviewTestRoute {
        guard let root = bundle.url(forResource: "IndoorMaps", withExtension: nil) else {
            throw IndoorMapLoadError.missingResource("IndoorMaps/POSTECHLibrary")
        }
        return try await load(directory: root.appendingPathComponent("POSTECHLibrary"),
                              on: map, labels: labels, destination: destination)
    }

    @concurrent
    func load(directory: URL, on map: IndoorMap, labels: [IndoorShelfLabel],
              destination: IndoorShelfLabel) async throws -> BookRoutePreviewTestRoute {
        let pinned = try await BundledIndoorMapLoader().load(directory: directory.appendingPathComponent("IMDFData"))
        guard pinned == map else { throw invalid("navigation.json", "현재 지도와 번들 도면이 다릅니다.") }
        return try build(on: map, labels: labels, destination: destination,
                         metadata: read("navigation.json", at: directory),
                         graph: read("routing-graph.geojson", at: directory),
                         links: read("navigation-feature-links.json", at: directory))
    }

    func build(on map: IndoorMap, labels: [IndoorShelfLabel], destination: IndoorShelfLabel,
               metadata: Data, graph graphData: Data, links linkData: Data) throws -> BookRoutePreviewTestRoute {
        try Task.checkCancellation()
        let descriptor: Descriptor = try decode(metadata, file: "navigation.json")
        guard descriptor.schemaVersion == 1, descriptor.kind == "navigation-only",
              descriptor.routingFile == "routing-graph.geojson",
              descriptor.featureLinksFile == "navigation-feature-links.json",
              hash(graphData) == descriptor.routingSHA256, hash(linkData) == descriptor.featureLinksSHA256 else {
            throw invalid("navigation.json", "파일 계약·버전·해시가 일치하지 않습니다.")
        }
        let rawGraph: RoutingGraphDTO = try decode(graphData, file: "routing-graph.geojson")
        let normalized = try normalize(rawGraph, descriptor: descriptor, on: map)
        let (graph, diagnostics) = try RoutingGraphMapper().map(normalized, on: map, layoutVersion: descriptor.layoutVersion)
        let links: FeatureLinks = try decode(linkData, file: "navigation-feature-links.json")
        let mapping = try featureNodes(links, graph: graph, map: map)
        let origins = labels.filter {
            $0.realNumber == "311" && $0.side == .b && $0.floorID == destination.floorID
        }
        guard origins.count == 1, let origin = origins.first,
              labels.contains(destination), map.floors.first(where: { $0.id == origin.floorID })?.ordinal == 2,
              let startNode = mapping[origin.mapElementID], let endNode = mapping[destination.mapElementID] else {
            throw invalid("navigation-feature-links.json", "3층 311-B와 목적지의 명시적 노드 연결이 필요합니다.")
        }
        let key = ShelfKey(datasetID: "postech-library-preview-test", value: destination.fixtureNumber)
        let shelf = ShelfDestination(key: key, name: "\(destination.realNumber)-\(destination.side.rawValue)",
                                     floorID: destination.floorID, mapElementID: destination.mapElementID,
                                     geometry: destination.geometry, arrivalNodeID: endNode.id,
                                     arrivalCoordinate: endNode.coordinate)
        // 출발은 서가 도형 중심이 아닌 sidecar가 지정한 통로 연결 노드다. 근접 노드 추정은 하지 않는다.
        let start = IndoorPosition(coordinate: startNode.coordinate, floorOrdinal: startNode.level,
                                   horizontalAccuracy: nil, timestamp: Date(), source: .manual)
        let navigation = IndoorNavigationData(
            graph: graph, shelves: .init(datasetID: key.datasetID, mode: .library, destinations: [shelf]),
            diagnostics: diagnostics
        )
        try Task.checkCancellation()
        let outcome = try IndoorRouteSearchEngine().search(.init(
            navigation: navigation, start: start, destination: key, preference: .shortestDistance
        ))
        guard case .route(let route) = outcome else { throw IndoorRoutingError.noRoute }
        return .init(origin: origin, destination: destination, start: start, route: route,
                     guidance: try RoutePreviewGuidance(route: route, graph: graph))
    }

    /// 이 묶음의 ordinal은 실제 층 번호다. UUID·descriptor와 대조한 노드만 현재 IMDF ordinal로 변환한다.
    private func normalize(_ graph: RoutingGraphDTO, descriptor: Descriptor, on map: IndoorMap) throws -> RoutingGraphDTO {
        guard Set(map.floors.map(\.id)).count == map.floors.count,
              Set(descriptor.levels.map(\.id)).count == descriptor.levels.count,
              Set(descriptor.levels.map(\.ordinal)).count == descriptor.levels.count,
              Set(descriptor.levels.map(\.id)) == Set(map.floors.map(\.id)),
              descriptor.layoutVersion == graph.layoutVersion else {
            throw invalid("navigation.json", "층 UUID·개정 정보가 현재 지도와 다릅니다.")
        }
        let floors = Dictionary(uniqueKeysWithValues: map.floors.map { ($0.id, $0) })
        let levels = Dictionary(uniqueKeysWithValues: descriptor.levels.map { ($0.id, $0.ordinal) })
        for floor in map.floors where levels[floor.id] != floor.ordinal + 1 {
            throw invalid("navigation.json", "이 테스트 묶음은 IMDF ordinal + 1의 층 번호 계약을 사용합니다.")
        }
        let features = try graph.features.map { feature -> RoutingGraphDTO.Feature in
            guard feature.properties.role == "node" else { return feature }
            let p = feature.properties
            guard let id = p.levelID, let floor = floors[id], p.level == levels[id] else {
                throw invalid("routing-graph.geojson", "노드의 층 UUID·번호가 descriptor와 다릅니다: \(feature.id)")
            }
            return .init(type: feature.type, id: feature.id, properties: .init(
                role: p.role, level: floor.ordinal, levelID: p.levelID, name: p.name, category: p.category,
                from: p.from, to: p.to, direction: p.direction, accessible: p.accessible,
                traversalSeconds: p.traversalSeconds, groupID: p.groupID
            ), geometry: feature.geometry)
        }
        return .init(type: graph.type, schemaVersion: graph.schemaVersion, layoutVersion: graph.layoutVersion,
                     routingConfig: graph.routingConfig, features: features)
    }

    private func featureNodes(_ links: FeatureLinks, graph: RoutingGraph,
                              map: IndoorMap) throws -> [IndoorMapElement.ID: RouteNode] {
        let file = "navigation-feature-links.json"
        guard links.schemaVersion == 1, links.layoutVersion == graph.layoutVersion,
              Set(map.features.map(\.id)).count == map.features.count,
              Set(links.nodes.map(\.nodeID)).count == links.nodes.count else {
            throw invalid(file, "버전 또는 중복 ID를 확인하세요.")
        }
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        let elements = Dictionary(uniqueKeysWithValues: map.features.map { ($0.id, $0) })
        var mapping: [IndoorMapElement.ID: RouteNode] = [:]
        var forward = Set<Association>()
        for link in links.features {
            try Task.checkCancellation()
            guard let kind = IndoorMapElement.Kind(rawValue: link.featureType), [.fixture, .unit].contains(kind),
                  let element = elements[.init(kind: kind, sourceID: link.featureID)],
                  element.floorID == link.levelID, let node = nodes[link.nodeID], node.floorID == link.levelID,
                  mapping[element.id] == nil else {
                throw invalid(file, "도형·층·노드가 다르거나 장소가 중복 배정됐습니다.")
            }
            mapping[element.id] = node
            forward.insert(.init(reference: link.reference, nodeID: link.nodeID))
        }
        let reverse = links.nodes.flatMap { node in
            node.features.map { Association(reference: $0, nodeID: node.nodeID) }
        }
        guard !forward.isEmpty, links.nodes.allSatisfy({ nodes[$0.nodeID] != nil && !$0.features.isEmpty }),
              Set(reverse).count == reverse.count, Set(reverse) == forward else {
            throw invalid(file, "장소→노드와 노드→장소 목록이 일치하지 않습니다.")
        }
        return mapping
    }

    private func read(_ file: String, at directory: URL) throws -> Data {
        do { return try Data(contentsOf: directory.appendingPathComponent(file)) }
        catch { throw invalid(file, error.localizedDescription) }
    }

    private func decode<T: Decodable>(_ data: Data, file: String) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: data) }
        catch { throw invalid(file, error.localizedDescription) }
    }

    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private func invalid(_ file: String, _ reason: String) -> IndoorMapLoadError { .invalidData(file: file, reason: reason) }

    private struct Descriptor: Decodable {
        let schemaVersion: Int
        let kind: String
        let layoutVersion: String
        let levels: [Level]
        let routingFile: String
        let routingSHA256: String
        let featureLinksFile: String
        let featureLinksSHA256: String
        struct Level: Decodable { let id: UUID; let ordinal: Int }
        enum CodingKeys: String, CodingKey {
            case kind, levels
            case schemaVersion = "schema_version", layoutVersion = "layout_version"
            case routingFile = "routing_file", routingSHA256 = "routing_sha256"
            case featureLinksFile = "feature_links_file", featureLinksSHA256 = "feature_links_sha256"
        }
    }
    private struct FeatureLinks: Decodable {
        let schemaVersion: Int
        let layoutVersion: String
        let features: [Link]
        let nodes: [Node]
        struct Link: Decodable {
            let featureType: String
            let featureID: UUID
            let levelID: UUID
            let nodeID: String
            var reference: Reference { .init(featureType: featureType, featureID: featureID, levelID: levelID) }
            enum CodingKeys: String, CodingKey {
                case featureType = "feature_type", featureID = "feature_id", levelID = "level_id", nodeID = "node_id"
            }
        }
        struct Node: Decodable {
            let nodeID: String
            let features: [Reference]
            enum CodingKeys: String, CodingKey { case features; case nodeID = "node_id" }
        }
        enum CodingKeys: String, CodingKey {
            case features, nodes
            case schemaVersion = "schema_version", layoutVersion = "layout_version"
        }
    }
    private struct Reference: Decodable, Hashable {
        let featureType: String
        let featureID: UUID
        let levelID: UUID
        enum CodingKeys: String, CodingKey { case featureType = "feature_type", featureID = "feature_id", levelID = "level_id" }
    }
    private struct Association: Hashable { let reference: Reference; let nodeID: String }
}
