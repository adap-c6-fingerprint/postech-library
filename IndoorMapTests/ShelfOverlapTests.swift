import CryptoKit
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct ShelfOverlapTests {
    nonisolated static let overlaps: [(String, [String])] = [
        ("BF637.C45.B5", ["S-3F-653-B", "S-3F-651-A"]),
        ("HD30.29.K5", ["S-3F-524-A", "S-3F-524-B"]),
        ("HG176.7.H5", ["S-3F-528-B", "S-3F-530-A"]),
        ("PL2489.논.독93", ["S-3F-558-B", "S-3F-560-A"]),
        ("QC174.12.R5", ["S-3F-644-A", "S-3F-642-B"])
    ]

    @Test("#73의 다섯 겹침을 모두 후보로 보존하고 경로 계산에 전달한다", arguments: overlaps)
    func resolvesConfirmedOverlaps(sample: (String, [String])) async throws {
        let fixture = try await Fixture.load()
        let candidate = try fixture.candidate(0, call: sample.0)
        #expect(Set(candidate.candidateShelves.map(\.fixtureNumber)) == Set(sample.1))
        let session = try await fixture.plan([candidate])
        let stop = try #require(session.stops.first)
        #expect(Set(stop.candidateShelves.map(\.fixtureNumber)) == Set(sample.1))
        #expect(stop.candidateShelves.contains(stop.shelf))
        #expect(session.legs.count == 1)
        #expect(session.route.destination.value == stop.shelf.fixtureNumber)
        let info = try #require(BookNavigationBookInfo(session: session, stopIndex: 0))
        #expect(info.callNumbers == [sample.0])
        #expect(info.candidateShelves == stop.candidateShelves)
        #expect(info.shelfText.hasPrefix("후보 서가:"))
    }

    @Test("한 권은 실제 이동거리가 짧은 후보를 고르고 후보 입력 순서에 의존하지 않는다")
    func choosesShortestReachableCandidate() async throws {
        let fixture = try await Fixture.load()
        let candidate = try fixture.candidate(0, call: "HD30.29.K5")
        let distances = try candidate.candidateShelves.map { try fixture.leg(to: $0).route.distanceMeters }
        let session = try await fixture.plan([candidate])
        let shortest = try #require(distances.min())
        #expect(abs(session.route.distanceMeters - shortest) < 0.000_001)
        let reversed = BookRouteCandidateStop(book: candidate.book, holdings: candidate.holdings,
            candidateShelves: candidate.candidateShelves.reversed())
        let again = try await fixture.plan([reversed])
        #expect(again.stops == session.stops)
        #expect(again.route == session.route)
    }

    @Test("서가 도착 노드가 같은 두 후보는 안정적으로 하나를 선택하고 둘 다 보존한다")
    func sharedArrivalNode() async throws {
        let fixture = try await Fixture.load()
        let candidate = try fixture.candidate(0, call: "HG176.7.H5")
        let paths = try candidate.candidateShelves.map { try fixture.leg(to: $0).route }
        #expect(paths[0].nodeIDs.last == paths[1].nodeIDs.last)
        let session = try await fixture.plan([candidate])
        #expect(session.stops[0].shelf == candidate.candidateShelves[0])
        #expect(session.stops[0].candidateShelves.count == 2)
    }

    @Test("세 책의 후보와 방문 순서를 독립적으로 열거한 최소 거리와 일치한다")
    func comparesAllCandidateRoutes() async throws {
        let fixture = try await Fixture.load()
        let candidates = try ["HD30.29.K5", "HG176.7.H5", "QC174.12.R5"].enumerated().map {
            try fixture.candidate($0.offset, call: $0.element)
        }
        var expected = Double.infinity
        // 구현의 조합 생성 함수·캐시와 독립적으로 8가지 후보와 6가지 순서를 검사한다.
        for mask in 0..<8 {
            let shelves = (0..<3).map { candidates[$0].candidateShelves[(mask >> $0) & 1] }
            for a in 0..<3 {
                for b in 0..<3 where b != a {
                    let c = 3 - a - b
                    let first = try fixture.leg(to: shelves[a])
                    let second = try fixture.leg(to: shelves[b], from: shelves[a])
                    let third = try fixture.leg(to: shelves[c], from: shelves[b])
                    expected = min(expected, first.route.distanceMeters + second.route.distanceMeters + third.route.distanceMeters)
                }
            }
        }
        let session = try await fixture.plan(candidates)
        #expect(abs(session.route.distanceMeters - expected) < 0.000_001)
        #expect(session.stops.count == 3 && session.legs.count == 3)
        #expect(session.matches(candidates: candidates))
        #expect(session.legs.map(\.destination.value) == session.stops.map(\.shelf.fixtureNumber))
    }

    @Test("한 후보의 길이 막히면 다른 후보를 사용하고 모두 막히면 실패한다")
    func skipsUnreachableCandidate() async throws {
        let fixture = try await Fixture.load()
        let candidate = try fixture.candidate(0, call: "HD30.29.K5")
        let paths = try candidate.candidateShelves.map { try fixture.leg(to: $0).route }
        let blocked = try #require(paths[0].nodeIDs.last)
        #expect(!paths[1].nodeIDs.contains(blocked))
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.copyItem(at: fixture.root, to: directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        try fixture.disconnect([blocked], in: directory)
        let session = try await fixture.plan([candidate], directory: directory)
        #expect(session.stops[0].shelf == candidate.candidateShelves[1])
        #expect(session.stops[0].candidateShelves == candidate.candidateShelves)
        try fixture.disconnect(Set(paths.compactMap { $0.nodeIDs.last }), in: directory)
        await #expect(throws: IndoorRoutingError.noRoute) {
            try await fixture.plan([candidate], directory: directory)
        }
    }

    @Test("현재 입력의 후보·소장 정보가 달라지면 이전 계산 결과를 사용할 수 없다")
    func preservesRequestIdentity() async throws {
        let fixture = try await Fixture.load()
        let candidate = try fixture.candidate(0, call: "HD30.29.K5")
        let session = try await fixture.plan([candidate])
        #expect(session.matches(candidates: [candidate]))
        let reduced = BookRouteCandidateStop(book: candidate.book, holdings: candidate.holdings,
            candidateShelves: [session.stops[0].shelf])
        #expect(!session.matches(candidates: [reduced]))
        let changed = BookRouteCandidateStop(book: candidate.book, holdings: [], candidateShelves: candidate.candidateShelves)
        #expect(!session.matches(candidates: [changed]))
    }

    @Test("층이 다르거나 확인되지 않은 인접 관계와 빈 후보를 임의로 묶지 않는다")
    func rejectsUnsupportedGroupsAndMissingLocations() async throws {
        let fixture = try await Fixture.load()
        let candidate = try fixture.candidate(0, call: "HD30.29.K5")
        let fourth = try #require(fixture.labels.first { $0.fixtureNumber == "S-4F-804-A" })
        let distant = try #require(fixture.labels.first { $0.fixtureNumber == "S-3F-657-A" })
        for shelves in [[], [candidate.candidateShelves[0], fourth], [candidate.candidateShelves[0], distant]] {
            #expect(!ShelfOverlapPolicy().allows(shelves))

        }
        let missing = BookHolding(holdingID: "missing", institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
            locationCode: nil, locationName: nil, callNumber: "AC1.G72", availability: "available")
        let resolution = BookHoldingShelfResolver().resolve([missing], on: fixture.map, labels: fixture.labels)
        #expect(resolution[0].outcome == .unsupportedLocation)
    }

    @Test("#73의 3·4층 겹침 8개 사례를 소장 위치의 층으로 제한한다", arguments: [
        ("AC1.G72", "S-3F-657-A", "S-4F-804-A"),
        ("BF18.K8.한167", "S-3F-653-A", "S-4F-804-B"),
        ("E171", "S-3F-512-A", "S-4F-794-A"),
        ("NX650.585.박14", "S-3F-544-A", "S-4F-724-B"),
        ("QA1.S8", "S-3F-665-A", "S-4F-814-B"),
        ("QH437.J66", "S-3F-624-B", "S-4F-692-B"),
        ("TK7867.I372", "S-3F-600-B", "S-4F-786-A"),
        ("TS670.E43", "S-3F-588-B", "S-4F-760-B")
    ])
    func filtersCrossFloorOverlap(sample: (String, String, String)) async throws {
        let fixture = try await Fixture.load()
        for (code, expected, ordinal) in [("c3b", sample.1, 2), ("c4b", sample.2, 3)] {
            let holding = BookHoldingTestData.holding(code: code, call: sample.0)
            let shelves = BookHoldingShelfResolver().resolve([holding], on: fixture.map, labels: fixture.labels).flatMap(\.shelves)
            #expect(shelves.contains { $0.fixtureNumber == expected })
            #expect(!shelves.isEmpty)
            #expect(shelves.allSatisfy { label in fixture.map.floors.first { $0.id == label.floorID }?.ordinal == ordinal })
        }
    }

    @MainActor
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

        func candidate(_ index: Int, call: String) throws -> BookRouteCandidateStop {
            let holding = BookHoldingTestData.holding(index, call: call)
            let shelves = BookHoldingShelfResolver().resolve([holding], on: map, labels: labels).flatMap(\.shelves)
            try #require(shelves.count == 2)
            return .init(book: BookHoldingTestData.book(index), holdings: [holding], candidateShelves: shelves)
        }

        func plan(_ candidates: [BookRouteCandidateStop], directory: URL? = nil) async throws -> BookNavigationSession {
            try await BookRoutePreviewTestRouteLoader().load(directory: directory ?? root, on: map, labels: labels, stops: candidates)
        }

        func leg(to shelf: IndoorShelfLabel, from previous: IndoorShelfLabel? = nil) throws -> BookRoutePreviewTestRoute {
            try BookRoutePreviewTestRouteLoader().build(on: map, labels: labels, destination: shelf,
                metadata: Data(contentsOf: root.appendingPathComponent("navigation.json")),
                graph: Data(contentsOf: root.appendingPathComponent("routing-graph.geojson")),
                links: Data(contentsOf: root.appendingPathComponent("navigation-feature-links.json")), origin: previous)
        }

        func disconnect(_ nodes: Set<String>, in directory: URL) throws {
            var graph = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("routing-graph.geojson"))) as? [String: Any])
            let features = try #require(graph["features"] as? [[String: Any]])
            graph["features"] = features.filter { feature in
                guard let p = feature["properties"] as? [String: Any] else { return true }
                return !nodes.contains(p["from"] as? String ?? "") && !nodes.contains(p["to"] as? String ?? "")
            }
            let data = try JSONSerialization.data(withJSONObject: graph)
            var metadata = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("navigation.json"))) as? [String: Any])
            metadata["routing_sha256"] = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            try data.write(to: directory.appendingPathComponent("routing-graph.geojson"))
            try JSONSerialization.data(withJSONObject: metadata).write(to: directory.appendingPathComponent("navigation.json"))
        }
    }
}
