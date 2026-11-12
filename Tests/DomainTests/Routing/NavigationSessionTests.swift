import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct NavigationSessionTests {
    static func makePlan() async throws -> RoutePlan {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let thirdFloor = try #require(map.floors.first { $0.ordinal == 2 })
        let shelves = try ["343", "320"].map { number in
            try #require(labels.first {
                $0.floorID == thirdFloor.id && $0.realNumber == number && $0.side == .a
            })
        }
        let start = IndoorPosition(
            coordinate: .init(latitude: 36.0127633, longitude: 129.3251348), floorOrdinal: 2,
            horizontalAccuracy: 3, timestamp: Date(), source: .manual
        )
        let stops = shelves.enumerated().map { index, shelf in
            RouteCandidateStop(book: makeBook(index), holdings: [], candidateShelves: [shelf])
        }
        return try await RoutePlanningLoader().load(on: map, labels: labels, start: start, stops: stops)
    }

    @Test func 다음_방문지로는_남은_방문지가_있을_때만_넘어간다() async throws {
        var session = NavigationSession(routePlan: try await Self.makePlan())
        #expect(session.currentStopIndex == 0)
        #expect(session.hasNextStop)
        let result1 = session.advance()
        #expect(result1)
        #expect(session.currentStopIndex == 1)
        #expect(!session.hasNextStop)
        let result2 = session.advance()
        #expect(!result2)
        #expect(session.currentStopIndex == 1)
    }

    @Test func 이전_방문지로_돌아가면_도착을_다시_확인한다() async throws {
        var session = NavigationSession(routePlan: try await Self.makePlan())
        let result3 = session.markArrived()
        #expect(result3)
        let result4 = session.markArrived()
        #expect(!result4)
        session.advance()
        let result5 = session.move(to: 0)
        #expect(result5)
        #expect(!session.arrivedStopIndices.contains(0))
        let result6 = session.markArrived()
        #expect(result6)
    }

    @Test func 다른_서가로_가는_경로는_구간에_넣지_않는다() async throws {
        let plan = try await Self.makePlan()
        var session = NavigationSession(routePlan: plan)
        let result7 = session.replaceLeg(at: 0, with: plan.legs[1])
        #expect(!result7)
        #expect(session.currentLeg == plan.legs[0])
        let result8 = session.replaceLeg(at: 1, with: plan.legs[1])
        #expect(result8)
        #expect(session.leg(at: 1) == plan.legs[1])
    }

    @Test func 마친_안내는_결과와_방문지를_바꾸지_않는다() async throws {
        var session = NavigationSession(routePlan: try await Self.makePlan())
        session.finish(.cancelled)
        session.finish(.completed)
        #expect(session.outcome == .cancelled)
        #expect(!session.isActive)
        let result9 = session.advance()
        #expect(!result9)
        let result10 = session.move(to: 1)
        #expect(!result10)
    }
}
