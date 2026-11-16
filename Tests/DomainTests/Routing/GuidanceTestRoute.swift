import Foundation
@testable import fingerprint_library

/// 길안내 계산 테스트용 U자 경로.
/// A(0,0) → B(북 20m) → C(동 6m) → D(남 20m). 나란한 두 통로가 6m 떨어져 있어 실제 서가 사이 통로처럼 후보가 겹친다.
enum GuidanceTestRoute {
    static let floorID = UUID(uuidString: "00000000-0000-0000-0000-0000000000F2")!
    static let level = 2
    static let origin = IndoorMapCoordinate(latitude: 36.0, longitude: 129.0)
    static let start = Date(timeIntervalSinceReferenceDate: 10_000)

    static func point(east: Double, north: Double) -> IndoorMapCoordinate {
        .init(latitude: origin.latitude + north / 111_195,
              longitude: origin.longitude + east / (111_195 * cos(origin.latitude * .pi / 180)))
    }

    static func node(_ id: String, east: Double, north: Double) -> RouteNode {
        RouteNode(id: id, coordinate: point(east: east, north: north), level: level, floorID: floorID,
                  name: nil, category: nil)
    }

    static func makeEngine() throws -> GuidanceEngine {
        let nodes = [node("A", east: 0, north: 0), node("B", east: 0, north: 20),
                     node("C", east: 6, north: 20), node("D", east: 6, north: 0)]
        let edges = zip(nodes, nodes.dropFirst()).enumerated().map { index, pair in
            RouteEdge(id: "e\(index)", fromNodeID: pair.0.id, toNodeID: pair.1.id, direction: .undirected,
                      category: .walkway, accessible: true, coordinates: [pair.0.coordinate, pair.1.coordinate],
                      traversalSeconds: nil)
        }
        let length = edges.map { RoutingGeometry.polylineLengthMeters($0.coordinates) }.reduce(0, +)
        let route = IndoorRoute(
            destination: ShelfKey(datasetID: "test", value: "D"), nodeIDs: nodes.map(\.id), edgeIDs: edges.map(\.id),
            segments: [.init(floorID: floorID, coordinates: nodes.map(\.coordinate))], floorChanges: [],
            distanceMeters: length, usesEstimatedDistances: false,
            start: .init(actualCoordinate: nodes[0].coordinate, routeCoordinate: nodes[0].coordinate,
                         floorID: floorID, distanceToGraphMeters: 0))
        let graph = RoutingGraph(schemaVersion: 1, layoutVersion: "test", hardSearchRadiusMeters: 10,
                                 nodes: nodes, edges: edges)
        return try GuidanceEngine(route: route, graph: graph)
    }

    static func position(east: Double, north: Double, accuracy: Double = 4, at seconds: Double,
                         level: Int? = level) -> IndoorPosition {
        IndoorPosition(coordinate: point(east: east, north: north), floorOrdinal: level,
                       horizontalAccuracy: accuracy, timestamp: start.addingTimeInterval(seconds), source: .sensor)
    }

    static func time(_ seconds: Double) -> Date { start.addingTimeInterval(seconds) }
}
