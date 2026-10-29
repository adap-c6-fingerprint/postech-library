import Foundation
import Testing
@testable import fingerprint_library

@MainActor
enum BookNavigationDetailsTestFixture {
    static func session(holdings: [BookHolding]? = nil) throws -> BookNavigationSession {
        let nodes = [IndoorRoutingTestFactory.node("a", level: 2),
            IndoorRoutingTestFactory.node("b", x: 20, level: 2),
            IndoorRoutingTestFactory.node("c", x: 20, y: 20, level: 2)]
        let data = NavigationGuidanceTestFixture.make(nodes: nodes)
        let back = NavigationGuidanceTestFixture.make(nodes: nodes, reversed: true).route
        let floor = IndoorMapFloor(id: nodes[0].floorID, ordinal: 2, name: "3층", geometry: .point(nodes[0].coordinate))
        let map = IndoorMap(formatVersion: "test", venue: .init(sourceID: UUID(), kind: .venue, floorID: nil,
            category: nil, name: "도서관", geometry: floor.geometry), floors: [floor], features: [], diagnostics: [])
        func shelf(_ node: RouteNode, number: String, start: String, end: String) -> IndoorShelfLabel {
            .init(fixtureNumber: node.id, realNumber: number, side: .a, sequence: 0,
                floorID: floor.id, mapElementID: .init(kind: .fixture, sourceID: UUID()), geometry: .point(node.coordinate),
                content: .callNumberRange(start: start, end: end))
        }
        let origin = shelf(nodes[0], number: "368", start: "QA100", end: "QA199")
        let goal = shelf(nodes[2], number: "367", start: "QA1", end: "QA99")
        let first = holdings ?? [BookHoldingTestData.holding(call: "QA42 .A1 2020")]
        let stops = [BookNavigationStop(book: BookHoldingTestData.book(0), holdings: first, shelf: goal),
            BookNavigationStop(book: BookHoldingTestData.book(1),
                holdings: [BookHoldingTestData.holding(1, call: "QA150 .B1 2021")], shelf: origin)]
        return try .init(map: map, shelfLabels: [origin, goal], stops: stops, legs: [data.route, back],
            graph: data.graph, origin: origin, start: .init(coordinate: nodes[0].coordinate, floorOrdinal: 2,
                horizontalAccuracy: nil, timestamp: NavigationGuidanceTestFixture.now, source: .manual))
    }
}

@MainActor
struct BookNavigationBookInfoTests {
    @Test("현재 서가에 맞는 소장본의 위치·청구기호만 표시하고 중복·다른 층 소장본은 섞지 않는다")
    func filtersHoldings() throws {
        let session = try BookNavigationDetailsTestFixture.session(holdings: [
            BookHoldingTestData.holding(call: "QA42 .A1 2020"),
            BookHoldingTestData.holding(1, call: "QA42 .A1 2020"),
            BookHoldingTestData.holding(2, code: "c4b", call: "QA50 .B1 2021"),
            BookHoldingTestData.holding(3, call: "QA150 .B1 2021")
        ])
        let info = try #require(BookNavigationBookInfo(session: session, stopIndex: 0))
        #expect(info.book == session.stops[0].book)
        #expect(info.floorName == "3층" && info.shelf.realNumber == "367")
        #expect(info.callNumbers == ["QA42 .A1 2020"])
        #expect(info.locationNames == ["단행본3층"])
        let next = try #require(BookNavigationBookInfo(session: session, stopIndex: 1))
        #expect(next.book != info.book && next.callNumbers == ["QA150 .B1 2021"])
    }

    @Test("청구기호가 없거나 해당 서가와 맞지 않으면 첫 소장본 값을 임의로 선택하지 않는다")
    func handlesMissingInformation() throws {
        for holdings in [[], [BookHoldingTestData.holding(call: "")], [BookHoldingTestData.holding(call: "ZZ9999")]] {
            let session = try BookNavigationDetailsTestFixture.session(holdings: holdings)
            let info = try #require(BookNavigationBookInfo(session: session, stopIndex: 0))
            #expect(info.callNumbers.isEmpty)
            #expect(info.shelf.realNumber == "367" && info.floorName == "3층")
        }
    }

    @Test("범위를 벗어난 목적지는 잘못된 책 정보를 반환하지 않는다")
    func invalidIndex() throws {
        let session = try BookNavigationDetailsTestFixture.session()
        #expect(BookNavigationBookInfo(session: session, stopIndex: -1) == nil)
        #expect(BookNavigationBookInfo(session: session, stopIndex: 2) == nil)
    }
}
