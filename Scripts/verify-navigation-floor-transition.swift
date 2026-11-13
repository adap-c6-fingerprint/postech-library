import Foundation

@main
struct VerifyNavigationFloorTransition {
    static func main() throws {
        let elevator = try plan(levels: [2, 2, 3, 3], categories: [.walkway, .elevator, .walkway])
        let first = BookNavigationFloorTransition.next(in: elevator, after: nil)!
        precondition(first.buttonTitle == "엘리베이터로 층 이동 시 눌러주세요")
        precondition(first.instructionText == "엘리베이터로 이동")
        precondition(first.to.level == 3 && first.steps == 1..<2)
        let manual = first.displayedProgress(in: elevator, liveProgress: nil)!
        precondition(manual.stepIndex == 2 && manual.fraction == 0)
        precondition(manual.remainingMeters == 10)
        precondition(BookNavigationFloorTransition.next(in: elevator, after: manual) == nil)

        // 권한 거부·수신 중단처럼 센서 진행이 없어져도 확인한 이동은 유지한다.
        precondition(first.displayedProgress(in: elevator, liveProgress: nil) == manual)
        let oldFloor = progress(in: elevator, step: 0, fraction: 0.5)
        precondition(!first.isReached(by: oldFloor))
        precondition(first.displayedProgress(in: elevator, liveProgress: oldFloor) == manual)
        let currentFloor = progress(in: elevator, step: 2, fraction: 0.5)
        precondition(first.isReached(by: currentFloor))
        precondition(first.displayedProgress(in: elevator, liveProgress: currentFloor) == currentFloor)
        let alreadyCrossed = progress(in: elevator, step: 1, fraction: 1)
        precondition(BookNavigationFloorTransition.next(in: elevator, after: alreadyCrossed) == nil)

        let stairs = try plan(levels: [2, 3, 3], categories: [.stairs, .walkway])
        precondition(BookNavigationFloorTransition.next(in: stairs, after: nil)?.buttonTitle == "계단으로 층 이동 시 눌러주세요")
        precondition(BookNavigationFloorTransition.next(in: stairs, after: nil)?.instructionText == "계단으로 이동")
        let sameFloor = try plan(levels: [2, 2, 2], categories: [.walkway, .stairs])
        precondition(BookNavigationFloorTransition.next(in: sameFloor, after: nil) == nil)

        // 중간 층에서 내리지 않는 연속 탑승은 한 번에 최종 층으로 넘긴다.
        let multiple = try plan(levels: [2, 2, 3, 4, 4], categories: [.walkway, .elevator, .elevator, .walkway])
        let ride = BookNavigationFloorTransition.next(in: multiple, after: nil)!
        precondition(ride.steps == 1..<3 && ride.to.level == 4)
        let afterRide = ride.displayedProgress(in: multiple, liveProgress: nil)!
        precondition(afterRide.stepIndex == 3)
        precondition(BookNavigationFloorTransition.next(in: multiple, after: afterRide) == nil)
        let descending = try plan(levels: [4, 3, 2], categories: [.stairs, .stairs])
        let descent = BookNavigationFloorTransition.next(in: descending, after: nil)!
        precondition(descent.steps == 0..<2 && descent.to.level == 2)
        let terminal = descent.displayedProgress(in: descending, liveProgress: nil)!
        precondition(terminal.fraction == 1 && terminal.remainingMeters == 0)
        precondition(BookNavigationFloorTransition.next(in: descending, after: terminal) == nil)

        let reverse = try plan(levels: [4, 3, 4], categories: [.stairs, .stairs])
        let down = BookNavigationFloorTransition.next(in: reverse, after: nil)!
        precondition(down.to.level == 3 && down.steps == 0..<1)
        let up = BookNavigationFloorTransition.next(in: reverse,
            after: down.displayedProgress(in: reverse, liveProgress: nil))!
        precondition(up.to.level == 4 && up.steps == 1..<2)

        let mixed = try plan(levels: [2, 3, 3, 4, 4], categories: [.stairs, .walkway, .elevator, .walkway], measured: false)
        let firstChange = BookNavigationFloorTransition.next(in: mixed, after: nil)!
        let between = firstChange.displayedProgress(in: mixed, liveProgress: nil)!
        precondition(between.remainingMeters == nil, "Unknown transition distances must stay unknown")
        let secondChange = BookNavigationFloorTransition.next(in: mixed, after: between)!
        precondition(secondChange.category == .elevator && secondChange.to.level == 4)
        precondition(BookNavigationFloorTransition.next(in: mixed,
            after: secondChange.displayedProgress(in: mixed, liveProgress: nil)) == nil)
        print("PASS: elevator/stairs labels, no-position/manual progress, delayed old-floor position, live recovery, completed/absent transitions, consecutive floors, descending/reversing and unknown distances")
    }

    private static func progress(in plan: GuidanceEngine, step: Int, fraction: Double) -> RouteGuidanceProgress {
        let value = plan.steps[step]
        return .init(stepIndex: step, fraction: fraction,
                     distanceAlongRoute: value.startDistance + (value.meters ?? 0) * fraction,
                     coordinate: value.to.coordinate, maneuver: .straight, distanceToManeuver: nil, remainingMeters: 5)
    }

    private static func plan(levels: [Int], categories: [RouteEdgeCategory], measured: Bool = true) throws -> GuidanceEngine {
        let floors = Dictionary(uniqueKeysWithValues: Set(levels).map { ($0, UUID()) })
        let nodes = levels.enumerated().map { index, level in
            RouteNode(id: "node-\(index)", coordinate: .init(latitude: 36, longitude: 129 + Double(index) * 0.00001),
                      level: level, floorID: floors[level]!, name: nil, category: nil)
        }
        let edges = categories.enumerated().map { index, category in
            RouteEdge(id: "edge-\(index)", fromNodeID: nodes[index].id, toNodeID: nodes[index + 1].id,
                      direction: .undirected, category: category, accessible: true,
                      coordinates: [nodes[index].coordinate, nodes[index + 1].coordinate], traversalSeconds: nil)
        }
        let distances = categories.map { $0 == .walkway ? 10.0 : 5.0 }
        let route = IndoorRoute(destination: .init(datasetID: "test", value: "shelf"), nodeIDs: nodes.map(\.id),
            edgeIDs: edges.map(\.id), segments: [], floorChanges: [], distanceMeters: distances.reduce(0, +),
            usesEstimatedDistances: true, start: .init(actualCoordinate: nodes[0].coordinate,
                routeCoordinate: nodes[0].coordinate, floorID: nodes[0].floorID, distanceToGraphMeters: 0),
            edgeDistancesMeters: measured ? distances : nil)
        let graph = RoutingGraph(schemaVersion: 1, layoutVersion: "test", hardSearchRadiusMeters: 10,
                                 nodes: nodes, edges: edges)
        return try GuidanceEngine(route: route, graph: graph)
    }
}
