import Foundation

@main
struct VerifyNavigationProgressLabels {
    static let floorIDs = [2: UUID(), 3: UUID(), 4: UUID()]
    static var floors: [IndoorMapFloor] {
        floorIDs.map { ordinal, id in
            .init(id: id, ordinal: ordinal, name: "\(ordinal + 1)F",
                  geometry: .point(.init(latitude: 36, longitude: 129)))
        }
    }

    static func main() throws {
        var cases = 0
        for category in [RouteEdgeCategory.elevator, .stairs] {
            for books in 1...3 {
                for changes in 0...min(books, 2) {
                    var level = 2
                    var plans: [RouteGuidancePlan?] = []
                    for book in 0..<books {
                        if book < changes {
                            let next = level == 2 ? 3 : 2
                            plans.append(try plan(levels: [level, level, next, next],
                                categories: [.walkway, category, .walkway], distances: [0.1, 0.1, 100]))
                            level = next
                        } else {
                            plans.append(try plan(levels: [level, level], categories: [.walkway], distances: [40]))
                        }
                    }
                    let timeline = BookNavigationTimeline(plans: plans, bookCount: books)
                    let original = timeline
                    for width in [80, 280, 320, 370, 600] as [CGFloat] {
                        let layout = makeLayout(timeline, width: width)
                        verifyGeometry(layout, width: width)
                        let transitions = layout.items.filter { if case .transition = $0.content { true } else { false } }
                        precondition(transitions.count == changes)
                        for item in transitions {
                            guard case .transition(let segment) = item.content else { fatalError() }
                            precondition(item.text == timeline.transitionTitle(for: segment, floors: floors))
                            precondition(item.text?.hasSuffix("층으로") == true)
                        }
                        for segment in timeline.segments where segment.kind == .walk {
                            let rule = timeline.walkingLabel(for: segment, floors: floors)
                            let rendered = layout.items.first { $0.content == .walk(segment) }!
                            if rule.isRequired {
                                precondition(rendered.text == rule.fullText || rendered.text == rule.compactText)
                                precondition(rendered.text?.hasPrefix("3층에서 ") == true)
                                if width == 600 { precondition(rendered.text == rule.fullText) }
                            } else if width == 80 {
                                precondition(rendered.text == nil, "좁으면 선택 문구는 생략한다")
                            }
                        }
                        precondition(timeline == original, "표시 폭 때문에 거리·진행률 입력을 바꾸지 않는다")
                        precondition(abs(layout.completedWidth(timeline: timeline, stopIndex: books, progress: nil)
                            - layout.trackWidth) < 0.01, "완료 막대가 마커 아래에서도 끊기지 않는다")
                        cases += 1
                    }
                }
            }
        }

        let mixed = BookNavigationTimeline(plans: [try plan(levels: [2, 2, 3, 3, 2, 2],
            categories: [.walkway, .elevator, .walkway, .stairs, .walkway], distances: [1, 1, 1, 1, 100])], bookCount: 1)
        let required = mixed.segments.filter { $0.kind == .walk && mixed.walkingLabel(for: $0, floors: floors).isRequired }
        precondition(required.count == 2, "첫 계단과 첫 엘리베이터를 각각 보장한다")
        verifyGeometry(makeLayout(mixed, width: 80), width: 80)

        let startsAtElevator = BookNavigationTimeline(plans: [try plan(levels: [2, 3],
            categories: [.elevator], distances: [0])], bookCount: 1)
        let direct = makeLayout(startsAtElevator, width: 320)
        precondition(direct.items.contains { $0.text == "엘리베이터로 이동" || $0.text == "3층에서 엘리베이터로 이동" })
        precondition(direct.items.contains { $0.text == "4층으로" })
        verifyGeometry(direct, width: 320)
        let zeroStep = startsAtElevator.segments[0]
        let zeroProgress = RouteGuidanceProgress(stepIndex: 0, fraction: 0, distanceAlongRoute: 0,
            coordinate: .init(latitude: 36, longitude: 129), maneuver: .straight,
            distanceToManeuver: 0, remainingMeters: 0)
        precondition(startsAtElevator.completion(of: zeroStep, stopIndex: 0, progress: zeroProgress).isFinite)

        let laterFirstTransition = BookNavigationTimeline(plans: [
            try plan(levels: [2, 2], categories: [.walkway], distances: [10]),
            try plan(levels: [2, 3], categories: [.stairs], distances: [5])
        ], bookCount: 2)
        let laterItems = makeLayout(laterFirstTransition, width: 80).items
        let firstBook = laterItems.firstIndex { $0.content == .marker(.waypoint(1)) }!
        let approach = laterItems.firstIndex { $0.text == "3층에서 이동 시작" }!
        let destinationFloor = laterItems.firstIndex { $0.text == "4층으로" }!
        precondition(firstBook < approach && approach < destinationFloor,
            "다음 책의 경로가 곧바로 층 이동이어도 첫 안내 문구를 앞에 표시한다")

        let throughFloors = BookNavigationTimeline(plans: [try plan(levels: [2, 3, 4],
            categories: [.elevator, .elevator], distances: [5, 5])], bookCount: 1)
        precondition(throughFloors.segments.count == 1)
        precondition(throughFloors.transitionTitle(for: throughFloors.segments[0], floors: floors) == "5층으로")
        let reversing = BookNavigationTimeline(plans: [try plan(levels: [2, 3, 2],
            categories: [.stairs, .stairs], distances: [5, 5])], bookCount: 1)
        precondition(reversing.segments.count == 2)
        precondition(makeLayout(reversing, width: 320).items.compactMap(\.text).contains("3층으로"))

        let sameFloor = BookNavigationTimeline(plans: [
            try plan(levels: [2, 2], categories: [.walkway], distances: [10]),
            try plan(levels: [2, 2], categories: [.walkway], distances: [10])
        ], bookCount: 2)
        precondition(makeLayout(sameFloor, width: 600).items.contains { $0.text == "다음 서가로 이동" })
        let betweenBooks = makeLayout(sameFloor, width: 370)
        let firstMilestone = betweenBooks.items.first { $0.content == .marker(.waypoint(1)) }!
        let completedFirstBook = betweenBooks.completedWidth(timeline: sameFloor, stopIndex: 1, progress: nil)
        precondition(abs(completedFirstBook - (firstMilestone.x + firstMilestone.width / 2 - betweenBooks.trackStart)) < 0.01,
            "첫 책 완료 진행은 마커 중심 아래까지 이어진다")
        let halfway = RouteGuidanceProgress(stepIndex: 0, fraction: 0.5, distanceAlongRoute: 5,
            coordinate: .init(latitude: 36, longitude: 129), maneuver: .straight,
            distanceToManeuver: 5, remainingMeters: 5)
        let secondSpan = betweenBooks.segmentSpans[1]
        precondition(abs(betweenBooks.completedWidth(timeline: sameFloor, stopIndex: 1, progress: halfway)
            - (secondSpan.x + secondSpan.width / 2 - betweenBooks.trackStart)) < 0.01)
        let unknown = BookNavigationTimeline(plans: [nil], bookCount: 1)
        precondition(!unknown.hasCompleteDistances && makeLayout(unknown, width: 320).items.isEmpty)
        print("PASS: \(cases) combinations; floor-prefixed required labels and fallback, uninterrupted progress under milestones, partial/completed progress, mixed facilities and zero-distance floors.")
    }

    static func measure(_ text: String) -> CGFloat { CGFloat(text.count) * 7 }
    static func makeLayout(_ timeline: BookNavigationTimeline, width: CGFloat) -> BookNavigationProgressLayout {
        .init(timeline: timeline, floors: floors, availableWidth: width, measureText: measure)
    }
    static func verifyGeometry(_ layout: BookNavigationProgressLayout, width: CGFloat) {
        precondition(layout.width >= width && layout.width.isFinite)
        for item in layout.items {
            precondition(item.width >= 0 && item.width.isFinite && item.x.isFinite)
            precondition(item.x >= 0 && item.x + item.width <= layout.width + 0.01)
            if let text = item.text {
                let decoration: CGFloat = if case .transition = item.content {
                    layout.markerDiameter + layout.iconSpacing + layout.textPadding * 2
                } else {
                    layout.textPadding * 2
                }
                precondition(measure(text) + decoration <= item.width + 0.01, "문구가 잘리지 않는다")
            }
        }
        for (a, b) in zip(layout.items, layout.items.dropFirst()) {
            precondition(a.x + a.width <= b.x + 0.01, "마커와 문구가 겹치지 않는다")
        }
        let spans = layout.segmentSpans
        if let first = spans.first, let last = spans.last {
            precondition(abs(first.x - layout.trackStart) < 0.01)
            precondition(abs(last.x + last.width - layout.trackEnd) < 0.01)
            for (a, b) in zip(spans, spans.dropFirst()) {
                precondition(abs(a.x + a.width - b.x) < 0.01, "진행 구간 사이에 마커 폭의 빈칸을 두지 않는다")
            }
        }
    }
    static func plan(levels: [Int], categories: [RouteEdgeCategory], distances: [Double]) throws -> RouteGuidancePlan {
        let nodes = levels.enumerated().map { index, level in
            RouteNode(id: "node-\(index)", coordinate: .init(latitude: 36, longitude: 129 + Double(index) * 0.00001),
                      level: level, floorID: floorIDs[level]!, name: nil, category: nil)
        }
        let edges = categories.enumerated().map { index, category in
            RouteEdge(id: "edge-\(index)", fromNodeID: nodes[index].id, toNodeID: nodes[index + 1].id,
                direction: .undirected, category: category, accessible: true,
                coordinates: [nodes[index].coordinate, nodes[index + 1].coordinate], traversalSeconds: nil)
        }
        let route = IndoorRoute(destination: .init(datasetID: "test", value: "shelf"), nodeIDs: nodes.map(\.id),
            edgeIDs: edges.map(\.id), segments: [], floorChanges: [], distanceMeters: distances.reduce(0, +),
            usesEstimatedDistances: true, start: .init(actualCoordinate: nodes[0].coordinate,
                routeCoordinate: nodes[0].coordinate, floorID: nodes[0].floorID, distanceToGraphMeters: 0),
            edgeDistancesMeters: distances)
        return try RouteGuidancePlan(route: route, graph: .init(schemaVersion: 1, layoutVersion: "test",
            hardSearchRadiusMeters: 10, nodes: nodes, edges: edges))
    }
}
