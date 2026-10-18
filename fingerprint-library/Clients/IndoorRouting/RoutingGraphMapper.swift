import Foundation

/// 원본 ID·방향·좌표를 유지한다. 누락된 층간 비용이나 버전을 추정하지 않는다.
nonisolated struct RoutingGraphMapper {
    func map(_ dto: RoutingGraphDTO, on map: IndoorMap, layoutVersion: String) throws -> (RoutingGraph, RoutingGraphDiagnostics) {
        guard dto.type == "FeatureCollection", dto.schemaVersion == 1,
              !layoutVersion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              dto.layoutVersion == layoutVersion,
              dto.routingConfig.hardSearchRadiusMeters.isFinite,
              dto.routingConfig.hardSearchRadiusMeters > 0 else {
            throw invalid("지원하지 않는 schema·layout_version 또는 탐색 반경입니다.")
        }
        guard Set(map.floors.map(\.ordinal)).count == map.floors.count else {
            throw invalid("지도 층 ordinal이 중복됩니다.")
        }
        var ids = Set<String>()
        for feature in dto.features {
            guard feature.type == "Feature", !feature.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  ids.insert(feature.id).inserted,
                  ["node", "edge"].contains(feature.properties.role) else {
                throw invalid("Feature의 type·ID·role이 올바르지 않습니다: \(feature.id)")
            }
        }
        let floors = Dictionary(uniqueKeysWithValues: map.floors.map { ($0.id, $0) })
        let nodes = try dto.features.filter { $0.properties.role == "node" }.map { feature in
            let p = feature.properties
            guard case .point(let values) = feature.geometry,
                  let id = p.levelID, let floor = floors[id], floor.ordinal == p.level else {
                throw invalid("노드 geometry·층 ID·ordinal이 지도와 다릅니다: \(feature.id)")
            }
            return RouteNode(id: feature.id, coordinate: try coordinate(values), level: floor.ordinal,
                             floorID: id, name: p.name, category: p.category)
        }
        guard !nodes.isEmpty else { throw invalid("노드가 없습니다.") }
        let nodesByID = Dictionary(uniqueKeysWithValues: nodes.map { ($0.id, $0) })
        let edges = try dto.features.filter { $0.properties.role == "edge" }.map { feature in
            let p = feature.properties
            guard case .lineString(let values) = feature.geometry, values.count >= 2,
                  let fromID = p.from, let from = nodesByID[fromID],
                  let toID = p.to, let to = nodesByID[toID], fromID != toID,
                  let direction = p.direction, let category = p.category.flatMap(RouteEdgeCategory.init(rawValue:)),
                  let accessible = p.accessible else {
                throw invalid("연결 geometry·끝점·방향·카테고리·접근성을 확인하세요: \(feature.id)")
            }
            let points = try values.map(coordinate)
            guard points.first == from.coordinate, points.last == to.coordinate else {
                throw invalid("LineString 끝점이 참조 노드의 좌표와 다릅니다: \(feature.id)")
            }
            guard !(accessible && (category == .stairs || category == .escalator)) else {
                throw invalid("계단·에스컬레이터는 accessible일 수 없습니다: \(feature.id)")
            }
            if from.level == to.level {
                guard p.traversalSeconds == nil, points.contains(where: { $0 != points[0] }) else {
                    throw invalid("동일 층 연결은 양의 길이가 필요하며 traversal_seconds를 사용하지 않습니다: \(feature.id)")
                }
            } else if category == .walkway {
                throw invalid("층간 연결에 walkway를 사용할 수 없습니다: \(feature.id)")
            }
            if let seconds = p.traversalSeconds, !seconds.isFinite || seconds <= 0 {
                throw invalid("traversal_seconds는 양의 유한값이어야 합니다: \(feature.id)")
            }
            return RouteEdge(id: feature.id, fromNodeID: fromID, toNodeID: toID, direction: direction,
                             category: category, accessible: accessible, coordinates: points,
                             traversalSeconds: p.traversalSeconds)
        }
        let graph = RoutingGraph(schemaVersion: dto.schemaVersion, layoutVersion: dto.layoutVersion,
                                 hardSearchRadiusMeters: dto.routingConfig.hardSearchRadiusMeters,
                                 nodes: nodes, edges: edges)
        return (graph, diagnostics(graph, floors: floors))
    }

    private func coordinate(_ values: [Double]) throws -> IndoorMapCoordinate {
        guard (2...3).contains(values.count), values.allSatisfy(\.isFinite) else {
            throw invalid("WGS 84 좌표는 [경도, 위도] 순서의 유한값이어야 합니다.")
        }
        let point = IndoorMapCoordinate(latitude: values[1], longitude: values[0])
        guard point.isValid else { throw invalid("WGS 84 좌표 범위를 벗어났습니다.") }
        return point
    }

    private func diagnostics(_ graph: RoutingGraph, floors: [UUID: IndoorMapFloor]) -> RoutingGraphDiagnostics {
        var neighbors = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, Set<String>()) })
        let nodes = Dictionary(uniqueKeysWithValues: graph.nodes.map { ($0.id, $0) })
        for edge in graph.edges {
            neighbors[edge.fromNodeID, default: []].insert(edge.toNodeID)
            neighbors[edge.toNodeID, default: []].insert(edge.fromNodeID)
        }
        var remaining = Set(neighbors.keys)
        var components: [[String]] = []
        while let first = remaining.min() {
            var stack = [first]
            var component: [String] = []
            remaining.remove(first)
            while let current = stack.popLast() {
                component.append(current)
                for next in neighbors[current, default: []] where remaining.remove(next) != nil {
                    stack.append(next)
                }
            }
            components.append(component.sorted())
        }
        return RoutingGraphDiagnostics(
            isolatedNodeIDs: neighbors.filter { $0.value.isEmpty }.keys.sorted(),
            connectedComponents: components,
            outsideFloorNodeIDs: graph.nodes.filter { floors[$0.floorID]?.geometry.contains($0.coordinate) != true }.map(\.id).sorted(),
            crossFloorEdgeIDs: graph.edges.filter { nodes[$0.fromNodeID]?.level != nodes[$0.toNodeID]?.level }.map(\.id).sorted()
        )
    }

    private func invalid(_ reason: String) -> IndoorMapLoadError {
        .invalidData(file: "routing-graph.geojson", reason: reason)
    }
}
