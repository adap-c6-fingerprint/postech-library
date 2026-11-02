import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookDetailDestinationTests {
    private let floorID = UUID(uuidString: "00000000-0000-4000-8000-000000000004")!
    private let fixtureID = UUID(uuidString: "00000000-0000-4000-8000-000000000337")!
    private var point: IndoorMapCoordinate { .init(latitude: 36, longitude: 129) }
    private var holding: BookHolding {
        .init(holdingID: "copy-4", institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
              locationCode: "c4b", locationName: "단행본4층", callNumber: "QA1", availability: "available")
    }
    private var book: Book {
        .init(id: "book", isbn: nil, controlNumber: "record", title: "선택한 책", author: "저자",
              publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
    }
    private var label: IndoorShelfLabel {
        .init(fixtureNumber: "S-4F-337-A", realNumber: "337", side: .a, sequence: 1, floorID: floorID,
              mapElementID: .init(kind: .fixture, sourceID: fixtureID), geometry: .point(point),
              content: .callNumberRange(start: "QA1", end: "QA2"))
    }
    private func context(position: Bool = true) -> BookDetailMapContext {
        let venue = IndoorMapElement(sourceID: UUID(), kind: .venue, floorID: nil,
                                     category: nil, name: nil, geometry: .point(point))
        let floor = IndoorMapFloor(id: floorID, ordinal: 3, name: "4F", geometry: .point(point))
        let map = IndoorMap(formatVersion: "1", venue: venue, floors: [floor], features: [], diagnostics: [])
        let key = ShelfKey(datasetID: "library-test", value: label.fixtureNumber)
        let destination = ShelfDestination(key: key, name: "337", floorID: floorID,
            mapElementID: label.mapElementID, geometry: .point(point), arrivalNodeID: "goal", arrivalCoordinate: point)
        let navigation = IndoorNavigationData(
            graph: .init(schemaVersion: 1, layoutVersion: "test", hardSearchRadiusMeters: 25, nodes: [], edges: []),
            shelves: .init(datasetID: key.datasetID, mode: .library, destinations: [destination]),
            diagnostics: .init(isolatedNodeIDs: [], connectedComponents: [], outsideFloorNodeIDs: [], crossFloorEdgeIDs: []))
        return .init(map: map, navigation: navigation, labels: [label], position: position
            ? .init(coordinate: point, floorOrdinal: 3, horizontalAccuracy: nil, timestamp: .distantPast, source: .manual)
            : nil, preference: .shortestDistance)
    }
    private func route(in context: BookDetailMapContext, distance: Double = 310,
                       changes: [RouteFloorChange] = []) -> IndoorRoute {
        .init(destination: context.navigation!.shelves.destinations[0].key, nodeIDs: [], edgeIDs: [],
              segments: [], floorChanges: changes, distanceMeters: distance, usesEstimatedDistances: false,
              start: .init(actualCoordinate: point, routeCoordinate: point, floorID: floorID, distanceToGraphMeters: 0))
    }

    @Test("대출 상태·청구기호·실제 서가 번호를 같은 소장본에서 표시한다")
    func consistentHolding() throws {
        let unavailable = BookHolding(holdingID: "other", institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
            locationCode: "c3b", locationName: "3층", callNumber: "OTHER", availability: "unavailable")
        let result = try #require(BookDetailDestinationPresentation.resolve(holdings: [unavailable, holding], context: context()))
        #expect(result.holding == holding)
        #expect(result.locationText == "4층 337번 서가")
        #expect(result.shelves == [label])
    }

    @Test("지원하지 않는 소장 위치를 임의의 서가에 배정하지 않는다")
    func unmappedLocation() throws {
        let other = BookHolding(holdingID: "special", institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
            locationCode: "special", locationName: "별치 자료", callNumber: "QA1", availability: "available")
        let result = try #require(BookDetailDestinationPresentation.resolve(holdings: [other], context: context()))
        #expect(result.shelves.isEmpty)
        #expect(result.locationText == "별치 자료")
    }

    @Test("층 이동 횟수는 경로 결과를 사용하고 잘못된 거리는 거부한다")
    func routeSummary() throws {
        let change = RouteFloorChange(edgeIDs: ["lift"], category: .elevator,
            fromFloorID: UUID(), toFloorID: floorID, fromCoordinate: point, toCoordinate: point)
        let result = try #require(BookDetailRoutePresentation(route: route(in: context(), changes: [change])))
        #expect(result.text == "310m · 층 이동 1회")
        #expect(BookDetailRoutePresentation(route: route(in: context(), distance: .nan)) == nil)
        #expect(BookDetailRoutePresentation(route: route(in: context(), distance: -1)) == nil)
    }

    @Test("현재 위치에서 선택한 소장본의 서가로 계산한 경로만 반영한다")
    func connectsRoute() async throws {
        let context = context()
        let result = route(in: context)
        let summary = try #require(BookDetailRoutePresentation(route: result))
        let destination = BookDetailDestinationPresentation.resolve(holdings: [holding], context: context)
        var initial = BookDetailFeature.State(book: book)
        initial.holdingsState = .loaded([holding])
        let store = TestStore(initialState: initial) { BookDetailFeature() } withDependencies: {
            $0.indoorRouteClient.search = { request in
                #expect(request.destination == result.destination)
                #expect(request.start == context.position)
                return .route(result)
            }
        }
        await store.send(.mapContextChanged(context)) {
            $0.mapContext = context
            $0.destinationPresentation = destination
            $0.destinationRouteRequestID = 1
            $0.destinationRouteState = .loading
        }
        await store.receive(\.destinationRouteLoaded) { $0.destinationRouteState = .loaded(summary) }
        await store.send(.destinationRouteFailed(requestID: 0))
        await store.send(.mapContextChanged(context))
        await store.finish()
    }

    @Test("위치를 모르면 0m·층 이동 0회를 만들거나 탐색하지 않는다")
    func missingPosition() async {
        let context = context(position: false)
        let destination = BookDetailDestinationPresentation.resolve(holdings: [holding], context: context)
        var initial = BookDetailFeature.State(book: book)
        initial.holdingsState = .loaded([holding])
        let store = TestStore(initialState: initial) { BookDetailFeature() } withDependencies: {
            $0.indoorRouteClient.search = { _ in
                Issue.record("위치가 없으면 경로를 요청하면 안 됩니다.")
                throw IndoorRoutingError.invalidPosition
            }
        }
        await store.send(.mapContextChanged(context)) {
            $0.mapContext = context
            $0.destinationPresentation = destination
            $0.destinationRouteRequestID = 1
            $0.destinationRouteState = .unavailable
        }
        await store.finish()
    }
}
