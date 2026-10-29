import CryptoKit
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookRoutePreviewOptimalOrderTests {
    @Test("테스트모드는 지정된 세 책으로만 교체하고 외부 입력은 그대로 보존한다")
    func testModeSelection() {
        let books = [BookHoldingTestData.book()]
        var destination = BookRoutePreviewDestination(books: books)
        #expect(destination.books == books && !destination.isTestMode)
        destination.useTestMode()
        #expect(destination.isTestMode)
        #expect(destination.books.map(\.id) == ["primo:alma991000841739703286", "primo:alma991000972219703286", "primo:alma991000569859703286"])
        #expect(destination.books.allSatisfy { $0.controlNumber == $0.id })
        #expect(BookRoutePreviewSample.testItems.map(\.holding.callNumber) == ["Q141 .박54 2011", "BF637.S4 .안141 2016", "PL833.U73 .노29 1993"])
        #expect(books == [BookHoldingTestData.book()])
    }

    @Test("각 테스트 책을 실제 서가 한 곳으로 해석하고 여섯 순서 전체의 최소값과 대조한다")
    func optimalAgainstAllOrders() async throws {
        let fixture = try await Fixture.load()
        let stops = try fixture.sampleStops()
        var distances: [Double] = []
        for order in orders {
            var previous: IndoorShelfLabel?
            var distance = 0.0
            for index in order {
                let result = try fixture.leg(to: stops[index].shelf, from: previous)
                distance += result.route.distanceMeters
                previous = stops[index].shelf
            }
            distances.append(distance)
        }
        let session = try await fixture.load(stops)
        #expect(abs(session.route.distanceMeters - (try #require(distances.min()))) < 0.000_001)
        #expect(session.stops.count == 3 && session.legs.count == 3)
        #expect(session.stops.allSatisfy { stops.contains($0) })
        #expect(session.route.destination == session.legs.last?.destination)
        #expect(session.guidance == (try RoutePreviewGuidance(route: session.route, graph: session.graph)))
        print("PLI-96 6개 순서 거리(m): \(distances)")
        print("PLI-96 최단 방문: \(session.stops.map { $0.book.title }) / \(session.route.distanceMeters)m / \(session.guidance.stepCount)단계")
        for stop in stops { print("PLI-96 매칭: \(stop.book.title) → \(stop.shelf.realNumber)-\(stop.shelf.side.rawValue)") }
    }

    @Test("외부 배열의 순서가 달라도 같은 최단 거리를 구하고 도서·소장·서가 연결을 유지한다")
    func externalOrders() async throws {
        let fixture = try await Fixture.load()
        let stops = try fixture.sampleStops()
        let expected = try await fixture.load(stops)
        for order in orders {
            let input = order.map { stops[$0] }
            let destination = BookRoutePreviewDestination(books: input.map(\.book))
            #expect(!destination.isTestMode)
            let result = try await fixture.load(input)
            #expect(abs(result.route.distanceMeters - expected.route.distanceMeters) < 0.000_001)
            #expect(result.stops.allSatisfy { input.contains($0) })
            #expect(result.legs.map(\.destination.value) == result.stops.map(\.shelf.fixtureNumber))
            #expect(destination.books == input.map(\.book))
        }
        let pair = Array(stops.prefix(2))
        let result = try await fixture.load(pair)
        let forward = try fixture.leg(to: pair[0].shelf).route.distanceMeters
            + fixture.leg(to: pair[1].shelf, from: pair[0].shelf).route.distanceMeters
        let reverse = try fixture.leg(to: pair[1].shelf).route.distanceMeters
            + fixture.leg(to: pair[0].shelf, from: pair[1].shelf).route.distanceMeters
        #expect(abs(result.route.distanceMeters - min(forward, reverse)) < 0.000_001)
    }

    @Test("단방향 때문에 막힌 순서는 건너뛰고, 전부 막히면 일부 경로도 전달하지 않는다")
    func directedAndDisconnectedOrders() async throws {
        let fixture = try await Fixture.load()
        let sample = try #require(fixture.sampleStops().last)
        let reference = try fixture.leg(to: sample.shelf)
        let origin = reference.origin
        let received = [sample, BookNavigationStop(book: BookHoldingTestData.book(), holdings: [], shelf: origin)]
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixture.root, to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var graph = try fixture.json("routing-graph.geojson")
        let features = try #require(graph["features"] as? [[String: Any]])
        let nodes = features.filter { ($0["properties"] as? [String: Any])?["role"] as? String == "node" }
        var edges: [[String: Any]] = []
        for (index, id) in reference.route.edgeIDs.enumerated() {
            var edge = try #require(features.first { $0["id"] as? String == id })
            var properties = try #require(edge["properties"] as? [String: Any])
            if properties["from"] as? String != reference.route.nodeIDs[index] {
                var geometry = try #require(edge["geometry"] as? [String: Any])
                geometry["coordinates"] = Array(try #require(geometry["coordinates"] as? [[Double]]).reversed())
                edge["geometry"] = geometry
            }
            properties["from"] = reference.route.nodeIDs[index]
            properties["to"] = reference.route.nodeIDs[index + 1]
            properties["direction"] = "directed"
            edge["properties"] = properties
            edges.append(edge)
        }
        func write(_ features: [[String: Any]]) throws {
            graph["features"] = features
            let data = try JSONSerialization.data(withJSONObject: graph)
            var metadata = try fixture.json("navigation.json")
            metadata["routing_sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try data.write(to: directory.appendingPathComponent("routing-graph.geojson"))
            try JSONSerialization.data(withJSONObject: metadata).write(to: directory.appendingPathComponent("navigation.json"))
        }
        try write(nodes + edges)
        let session = try await BookRoutePreviewTestRouteLoader().load(directory: directory, on: fixture.map, labels: fixture.labels, stops: received)
        #expect(session.stops == [received[1], received[0]])
        #expect(session.route.edgeIDs == reference.route.edgeIDs)
        try write(nodes)
        await #expect(throws: IndoorRoutingError.noRoute) {
            try await BookRoutePreviewTestRouteLoader().load(directory: directory, on: fixture.map, labels: fixture.labels, stops: received)
        }
    }

    // 생성 코드와 독립적으로 중복 없는 세 인덱스를 열거한다.
    private var orders: [[Int]] {
        (0..<3).flatMap { a in (0..<3).flatMap { b in (0..<3).compactMap { c in
            Set([a, b, c]).count == 3 ? [a, b, c] : nil
        } } }
    }

    private struct Fixture {
        let root: URL
        let map: IndoorMap
        let labels: [IndoorShelfLabel]
        static func load() async throws -> Self {
            let root = try #require(Bundle.main.url(forResource: "IndoorMaps", withExtension: nil)).appendingPathComponent("POSTECHLibrary")
            let map = try await BundledIndoorMapLoader().load(directory: root.appendingPathComponent("IMDFData"))
            let labels = try BundledShelfLabelLoader().decode(Data(contentsOf: root.appendingPathComponent("shelfdata.json")), on: map)
            return .init(root: root, map: map, labels: labels)
        }
        func sampleStops() throws -> [BookNavigationStop] {
            try BookRoutePreviewSample.testItems.map { item in
                let shelves = BookHoldingShelfResolver().resolve([item.holding], on: map, labels: labels).flatMap(\.shelves)
                #expect(shelves.count == 1)
                return .init(book: item.book, holdings: [item.holding], shelf: try #require(shelves.first))
            }
        }
        func load(_ stops: [BookNavigationStop]) async throws -> BookNavigationSession {
            try await BookRoutePreviewTestRouteLoader().load(directory: root, on: map, labels: labels, stops: stops)
        }
        func json(_ file: String) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(file))) as? [String: Any])
        }
        func leg(to shelf: IndoorShelfLabel, from origin: IndoorShelfLabel? = nil) throws -> BookRoutePreviewTestRoute {
            try BookRoutePreviewTestRouteLoader().build(on: map, labels: labels, destination: shelf,
                metadata: Data(contentsOf: root.appendingPathComponent("navigation.json")),
                graph: Data(contentsOf: root.appendingPathComponent("routing-graph.geojson")),
                links: Data(contentsOf: root.appendingPathComponent("navigation-feature-links.json")), origin: origin)
        }
    }
}
