import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookNavigationSessionTests {
    @Test("일반 도서도 목데이터 ID에 의존하지 않고 311-B에서 즉시 계산한다")
    func receivedBookRoute() async throws {
        let fixture = try await Fixture.load()
        let stop = fixture.stop(0, shelf: fixture.goal)
        let session = try await fixture.load([stop])
        let original = try await BookRoutePreviewTestRouteLoader().load(
            directory: fixture.root, on: fixture.map, labels: fixture.labels, destination: fixture.goal)
        #expect(stop.book.id != BookRoutePreviewSample.book.id)
        #expect(session.stops == [stop])
        #expect(session.origin.realNumber == "311" && session.origin.side == .b)
        #expect(session.route == original.route)
        #expect(session.guidance == original.guidance)
        #expect(session.graph == original.graph)
        #expect(session.map == fixture.map && session.shelfLabels == fixture.labels)
        #expect(session.legs.count == 1)
    }

    @Test("세 책은 입력 순서대로 이어지고 출발점·도서·구간별 경로를 함께 전달한다")
    func orderedBooks() async throws {
        let fixture = try await Fixture.load()
        let stops = [fixture.stop(0, shelf: fixture.goal), fixture.stop(1, shelf: fixture.origin),
                     fixture.stop(2, shelf: fixture.goal)]
        let session = try await fixture.load(stops)
        #expect(session.stops == stops)
        #expect(session.legs.count == 3)
        #expect(session.legs[0].nodeIDs.last == session.legs[1].nodeIDs.first)
        #expect(session.legs[1].nodeIDs.last == session.legs[2].nodeIDs.first)
        #expect(session.legs.map(\.destination.value) == stops.map(\.shelf.fixtureNumber))
        #expect(session.route.distanceMeters == session.legs.reduce(0) { $0 + $1.distanceMeters })
        #expect(session.route.edgeIDs == session.legs.flatMap(\.edgeIDs))
        #expect(session.route.segments == session.legs.flatMap(\.segments))
        #expect(session.start.coordinate == session.route.start.actualCoordinate)
        #expect(session.guidance == (try RoutePreviewGuidance(route: session.route, graph: session.graph)))
        #expect(abs(session.guidance.walkingSeconds - session.route.distanceMeters * 0.72) < 0.000_001)
    }

    @Test("같은 서가의 여러 책은 0거리 구간을 보존하되 가짜 단계는 추가하지 않는다")
    func sharedShelf() async throws {
        let fixture = try await Fixture.load()
        let session = try await fixture.load((0..<3).map { fixture.stop($0, shelf: fixture.goal) })
        #expect(session.stops.count == 3)
        #expect(session.legs.dropFirst().allSatisfy { $0.distanceMeters == 0 && $0.edgeIDs.isEmpty })
        #expect(session.route.nodeIDs == session.legs[0].nodeIDs)
        #expect(session.route.distanceMeters == session.legs[0].distanceMeters)
        #expect(session.guidance.stepCount == 3)
        #expect(session.guidance.groupTransitionNodes.count == 2)
    }

    @Test("빈 입력·중복 도서·상한 초과는 일부 도서의 경로로 대체하지 않는다")
    func rejectsInvalidSelection() async throws {
        let fixture = try await Fixture.load()
        let one = fixture.stop(0, shelf: fixture.goal)
        for stops in [[], [one, one], (0..<4).map { fixture.stop($0, shelf: fixture.goal) }] {
            await #expect(throws: IndoorRoutingError.invalidDestination) { try await fixture.load(stops) }
        }
    }

    @Test("두 번째 책의 서가가 잘못되면 첫 번째 경로만 전달하지 않는다")
    func rejectsPartialRoute() async throws {
        let fixture = try await Fixture.load()
        let missing = IndoorShelfLabel(fixtureNumber: "missing", realNumber: "missing", side: .a, sequence: 0,
            floorID: fixture.goal.floorID, mapElementID: .init(kind: .fixture, sourceID: UUID()),
            geometry: fixture.goal.geometry, content: .emptyShelf)
        await #expect(throws: IndoorMapLoadError.self) {
            try await fixture.load([fixture.stop(0, shelf: fixture.goal), fixture.stop(1, shelf: missing)])
        }
    }

    private struct Fixture {
        let root: URL
        let map: IndoorMap
        let labels: [IndoorShelfLabel]
        let origin: IndoorShelfLabel
        let goal: IndoorShelfLabel

        static func load() async throws -> Self {
            let root = try #require(Bundle.main.url(forResource: "IndoorMaps", withExtension: nil))
                .appendingPathComponent("POSTECHLibrary")
            let map = try await BundledIndoorMapLoader().load(directory: root.appendingPathComponent("IMDFData"))
            let labels = try BundledShelfLabelLoader().decode(Data(contentsOf: root.appendingPathComponent("shelfdata.json")), on: map)
            return .init(root: root, map: map, labels: labels,
                origin: try #require(labels.first { $0.fixtureNumber == "S-3F-512-B" }),
                goal: try #require(labels.first { $0.fixtureNumber == "S-3F-564-A" }))
        }

        func stop(_ index: Int, shelf: IndoorShelfLabel) -> BookNavigationStop {
            .init(book: BookHoldingTestData.book(index), holdings: [BookRoutePreviewSample.holding], shelf: shelf)
        }

        func load(_ stops: [BookNavigationStop]) async throws -> BookNavigationSession {
            try await BookRoutePreviewTestRouteLoader().load(directory: root, on: map, labels: labels, stops: stops)
        }
    }
}
