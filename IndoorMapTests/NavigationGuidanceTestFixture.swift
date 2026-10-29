import Foundation
@testable import fingerprint_library

enum NavigationGuidanceTestFixture {
    static let now = IndoorRoutingTestFactory.now

    static func position(x: Double, y: Double = 0, level: Int? = 0,
                         accuracy: Double = 0, seconds: Double = 0) -> IndoorPosition {
        .init(coordinate: IndoorRoutingTestFactory.node("position", x: x, y: y).coordinate,
              floorOrdinal: level, horizontalAccuracy: accuracy, timestamp: now.addingTimeInterval(seconds), source: .simulation)
    }

    static func make(nodes: [RouteNode]? = nil, groups: [UUID?] = [],
                     shapes: [[IndoorMapCoordinate]] = [], categories: [RouteEdgeCategory] = [],
                     reversed: Bool = false, projectedStart: IndoorMapCoordinate? = nil)
        -> (route: IndoorRoute, graph: RoutingGraph) {
        let nodes = nodes ?? [IndoorRoutingTestFactory.node("a"),
            IndoorRoutingTestFactory.node("b", x: 20), IndoorRoutingTestFactory.node("c", x: 20, y: 20)]
        var edges: [RouteEdge] = []
        for index in 0..<max(0, nodes.count - 1) {
            var edge = IndoorRoutingTestFactory.edge("e\(index)", nodes[index], nodes[index + 1],
                category: categories.indices.contains(index) ? categories[index] : .walkway,
                coordinates: shapes.indices.contains(index) ? shapes[index] : nil)
            edge.groupID = groups.indices.contains(index) ? groups[index] : nil
            edges.append(edge)
        }
        let graph = IndoorRoutingTestFactory.graph(nodes, edges)
        let orderedNodes = reversed ? Array(nodes.reversed()) : nodes
        let orderedEdges = reversed ? Array(edges.reversed()) : edges
        var segments: [RoutePolylineSegment] = []
        var changes: [RouteFloorChange] = []
        var total = 0.0
        for (index, edge) in orderedEdges.enumerated() {
            let from = orderedNodes[index], to = orderedNodes[index + 1]
            var coordinates = reversed ? Array(edge.coordinates.reversed()) : edge.coordinates
            if index == 0, let projectedStart { coordinates = [projectedStart] + coordinates.dropFirst() }
            if from.floorID != to.floorID {
                total += 6
                changes.append(.init(edgeIDs: [edge.id], category: edge.category, fromFloorID: from.floorID,
                    toFloorID: to.floorID, fromCoordinate: from.coordinate, toCoordinate: to.coordinate))
            } else {
                total += RoutingGeometry.polylineLengthMeters(coordinates)
                segments.append(.init(floorID: from.floorID, coordinates: coordinates))
            }
        }
        let first = orderedNodes[0], last = orderedNodes[orderedNodes.count - 1]
        let route = IndoorRoute(destination: .init(datasetID: "guidance-tests", value: last.id),
            nodeIDs: projectedStart == nil ? orderedNodes.map(\.id) : Array(orderedNodes.dropFirst().map(\.id)),
            edgeIDs: orderedEdges.map(\.id), segments: segments, floorChanges: changes,
            distanceMeters: total, usesEstimatedDistances: false,
            start: .init(actualCoordinate: projectedStart ?? first.coordinate, routeCoordinate: projectedStart ?? first.coordinate,
                         floorID: first.floorID, distanceToGraphMeters: 0))
        return (route, graph)
    }

    @MainActor
    static func session() throws -> BookNavigationSession {
        let (route, graph) = make()
        let back = make(reversed: true).route
        let first = graph.nodes[0], last = graph.nodes[graph.nodes.count - 1]
        let floor = IndoorMapFloor(id: first.floorID, ordinal: first.level, name: "1층", geometry: .point(first.coordinate))
        let map = IndoorMap(formatVersion: "test", venue: .init(sourceID: UUID(), kind: .venue, floorID: nil,
            category: nil, name: "테스트 도서관", geometry: .point(first.coordinate)), floors: [floor], features: [], diagnostics: [])
        func shelf(_ node: RouteNode) -> IndoorShelfLabel {
            .init(fixtureNumber: node.id, realNumber: node.id, side: .a, sequence: 0,
                floorID: node.floorID, mapElementID: .init(kind: .fixture, sourceID: UUID()),
                geometry: .point(node.coordinate), content: .emptyShelf)
        }
        let origin = shelf(first), goal = shelf(last)
        let stops = [goal, origin].enumerated().map { index, shelf in
            BookNavigationStop(book: BookHoldingTestData.book(index), holdings: [BookHoldingTestData.holding(index)], shelf: shelf)
        }
        return try .init(map: map, shelfLabels: [origin, goal], stops: stops, legs: [route, back], graph: graph,
            origin: origin, start: .init(coordinate: first.coordinate, floorOrdinal: first.level,
                                       horizontalAccuracy: 0, timestamp: now, source: .simulation))
    }
}
