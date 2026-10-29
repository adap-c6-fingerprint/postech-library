import CryptoKit
import Foundation
import MapKit
import Testing

@testable import fingerprint_library

@MainActor
struct BookRoutePreviewTestRouteTests {
    @Test("테스트 출발 311-B와 동물농장 서가를 명시적 노드로 연결해 실제 경로를 만든다")
    func computesBundledRoute() async throws {
        let fixture = try await Fixture.load()
        let result = try await BookRoutePreviewTestRouteLoader().load(
            directory: fixture.root, on: fixture.map, labels: fixture.labels, destination: fixture.destination)
        #expect(result.origin.fixtureNumber == "S-3F-512-B")
        #expect(result.origin.realNumber == "311" && result.origin.side == .b)
        #expect(result.destination.fixtureNumber == "S-3F-564-A")
        #expect(result.start.source == .manual && result.start.floorOrdinal == 2)
        #expect(result.route.nodeIDs.first == "6d22ecc9-b697-4d48-a9d8-4771a6d36bcb")
        #expect(result.route.nodeIDs.last == "68ed0070-4842-4488-b381-3cf387733b51")
        #expect(result.route.edgeIDs.count == 33)
        #expect((58...60).contains(result.route.distanceMeters))
        #expect(result.route.start.distanceToGraphMeters == 0)
        #expect(result.route.floorChanges.isEmpty)
        #expect(abs(result.guidance.walkingSeconds - 42.22028465) < 0.000_001)
        #expect(result.guidance.stepCount == 3)
        #expect(result.guidance.groupTransitionNodes.map(\.id) == [
            "e43c6135-24a2-43a9-ba62-a9d6cf03cb76", "6ec3f119-b41f-40e8-afe0-3c3aaccc55bd"
        ])

        let floor = try #require(fixture.map.floors.first { $0.id == result.origin.floorID })
        var parent = IndoorMapKitView(
            map: fixture.map, floor: floor, selectedFeatureID: nil, position: result.start,
            showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
            onSelect: { _ in }, onPlaceOrigin: { _ in }, route: result.route,
            groupTransitionNodes: result.guidance.groupTransitionNodes,
            shelfLabels: fixture.labels, highlightedFeatureIDs: [result.destination.mapElementID])
        let coordinator = parent.makeCoordinator()
        let view = coordinator.makeMapView()
        defer { view.delegate = nil }
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 340)
        coordinator.update(parent: parent, in: view)
        let markers = view.annotations.compactMap { $0 as? MKPointAnnotation }
        #expect(markers.count == 2)
        for node in result.guidance.groupTransitionNodes {
            let marker = try #require(markers.first {
                abs($0.coordinate.latitude - node.coordinate.latitude) < 0.000_001
                    && abs($0.coordinate.longitude - node.coordinate.longitude) < 0.000_001
            })
            let badge = try #require(coordinator.mapView(view, viewFor: marker))
            #expect(badge.image?.size == CGSize(width: 24, height: 24))
            #expect(badge.zPriority == .max)
            #expect(badge.displayPriority == .required)
            #expect(badge.accessibilityIdentifier == "route-group-transition-\(node.id)")
        }
        let segment = try #require(result.route.segments.first)
        let path = try #require(view.overlays.compactMap { $0 as? MKPolyline }.first {
            $0.pointCount == segment.coordinates.count
                && abs($0.points()[0].coordinate.latitude - segment.coordinates[0].latitude) < 0.000_001
                && abs($0.points()[0].coordinate.longitude - segment.coordinates[0].longitude) < 0.000_001
        })
        for (index, coordinate) in segment.coordinates.enumerated() {
            #expect(abs(path.points()[index].coordinate.latitude - coordinate.latitude) < 0.000_001)
            #expect(abs(path.points()[index].coordinate.longitude - coordinate.longitude) < 0.000_001)
        }
        #expect(coordinator.moveCamera(.init(id: 1, target: .route(result.route,
            featureIDs: [result.origin.mapElementID, result.destination.mapElementID])), in: view, animated: false))
        let coordinates = result.route.segments.flatMap(\.coordinates)
            + result.origin.geometry.coordinates + result.destination.geometry.coordinates
        for coordinate in coordinates {
            let point = view.convert(CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
                                     toPointTo: view)
            #expect(view.bounds.insetBy(dx: 16, dy: 16).contains(point))
        }
        // 동일 경로에서 그룹 표시만 바뀌어도 이전 원을 정리한다.
        parent.groupTransitionNodes = []
        coordinator.update(parent: parent, in: view)
        #expect(view.annotations.compactMap { $0 as? MKPointAnnotation }.isEmpty)
        parent.groupTransitionNodes = result.guidance.groupTransitionNodes
        coordinator.update(parent: parent, in: view)
        #expect(view.annotations.compactMap { $0 as? MKPointAnnotation }.count == 2)
        parent.route = nil
        coordinator.update(parent: parent, in: view)
        #expect(view.overlays.compactMap { $0 as? MKCircle }.isEmpty)
        #expect(view.annotations.compactMap { $0 as? MKPointAnnotation }.isEmpty)
    }

    enum Corruption: CaseIterable { case hash, level, missingOrigin, reverseLinks, disconnected }

    @Test("시트 가림 높이가 달라도 지도 크기는 유지하고 남은 영역에 전체 경로를 맞춘다")
    func fitsRouteAboveNativeSheet() async throws {
        let fixture = try await Fixture.load()
        let result = try await BookRoutePreviewTestRouteLoader().load(
            directory: fixture.root, on: fixture.map, labels: fixture.labels, destination: fixture.destination)
        let floor = try #require(fixture.map.floors.first { $0.id == result.origin.floorID })
        var parent = IndoorMapKitView(map: fixture.map, floor: floor, selectedFeatureID: nil,
            position: result.start, showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
            onSelect: { _ in }, onPlaceOrigin: { _ in }, route: result.route)
        let coordinator = parent.makeCoordinator()
        let view = coordinator.makeMapView()
        defer { view.delegate = nil }
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 874)
        for bottom in [250.0, 435, 560, 250] {
            parent.viewportInsets = .init(top: 60, left: 0, bottom: bottom, right: 0)
            coordinator.update(parent: parent, in: view)
            #expect(coordinator.moveCamera(.init(id: Int(bottom), target: .route(result.route,
                featureIDs: [result.origin.mapElementID, result.destination.mapElementID])), in: view, animated: false))
            let visible = view.bounds.inset(by: .init(top: 76, left: 16, bottom: bottom + 16, right: 16))
            let coordinates = result.route.segments.flatMap(\.coordinates)
                + result.origin.geometry.coordinates + result.destination.geometry.coordinates
            let points = coordinates.map { view.convert($0.clCoordinate, toPointTo: view) }
            #expect(points.allSatisfy { visible.contains($0) })
            #expect((try #require(points.map(\.y).max())) - (try #require(points.map(\.y).min())) > 40)
            #expect(view.bounds.size == CGSize(width: 390, height: 874))
        }
    }

    @Test("손상·잘못된 층·미연결 자료에서는 임의 노드나 직선으로 대체하지 않는다", arguments: Corruption.allCases)
    func rejectsInvalidData(_ corruption: Corruption) async throws {
        let fixture = try await Fixture.load()
        var metadata = try fixture.object("navigation.json")
        var graph = try fixture.object("routing-graph.geojson")
        var links = try fixture.object("navigation-feature-links.json")
        var features = try #require(graph["features"] as? [[String: Any]])
        switch corruption {
        case .hash: metadata["routing_sha256"] = "invalid"
        case .level:
            let index = try #require(features.firstIndex { ($0["properties"] as? [String: Any])?["role"] as? String == "node" })
            var properties = try #require(features[index]["properties"] as? [String: Any])
            properties["level"] = 99
            features[index]["properties"] = properties
            graph["features"] = features
        case .disconnected:
            graph["features"] = features.filter { ($0["properties"] as? [String: Any])?["role"] as? String == "node" }
        case .missingOrigin, .reverseLinks:
            var nodes = try #require(links["nodes"] as? [[String: Any]])
            if corruption == .missingOrigin {
                let origin = "782218de-2ed5-46c4-9d38-a847d26063c4"
                links["features"] = try #require(links["features"] as? [[String: Any]])
                    .filter { $0["feature_id"] as? String != origin }
                for index in nodes.indices {
                    nodes[index]["features"] = try #require(nodes[index]["features"] as? [[String: Any]])
                        .filter { $0["feature_id"] as? String != origin }
                }
                nodes.removeAll { ($0["features"] as? [Any])?.isEmpty == true }
            } else { nodes[0]["features"] = [] }
            links["nodes"] = nodes
        }
        let graphData = try JSONSerialization.data(withJSONObject: graph)
        let linkData = try JSONSerialization.data(withJSONObject: links)
        if corruption != .hash { metadata["routing_sha256"] = hash(graphData) }
        metadata["feature_links_sha256"] = hash(linkData)
        do {
            _ = try BookRoutePreviewTestRouteLoader().build(
                on: fixture.map, labels: fixture.labels, destination: fixture.destination,
                metadata: JSONSerialization.data(withJSONObject: metadata), graph: graphData, links: linkData)
            Issue.record("잘못된 자료를 경로로 만들었습니다: \(corruption)")
        } catch let error as IndoorRoutingError {
            #expect(corruption == .disconnected && error == .noRoute)
        } catch is IndoorMapLoadError {
            #expect(corruption != .disconnected)
        }
    }

    private func hash(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    @MainActor
    private struct Fixture {
        let root: URL
        let map: IndoorMap
        let labels: [IndoorShelfLabel]
        let destination: IndoorShelfLabel

        static func load() async throws -> Self {
            let root = try #require(Bundle.main.url(forResource: "IndoorMaps", withExtension: nil))
                .appendingPathComponent("POSTECHLibrary")
            let map = try await BundledIndoorMapLoader().load(directory: root.appendingPathComponent("IMDFData"))
            let labels = try BundledShelfLabelLoader().decode(Data(contentsOf: root.appendingPathComponent("shelfdata.json")), on: map)
            let goals = BookHoldingShelfResolver().resolve([BookRoutePreviewSample.holding], on: map, labels: labels).flatMap(\.shelves)
            #expect(goals.count == 1)
            return .init(root: root, map: map, labels: labels, destination: try #require(goals.first))
        }

        func object(_ file: String) throws -> [String: Any] {
            try #require(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent(file))) as? [String: Any])
        }
    }
}
