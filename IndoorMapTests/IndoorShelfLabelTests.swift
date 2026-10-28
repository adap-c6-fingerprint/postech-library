import CryptoKit
import Foundation
import MapKit
import Testing
@testable import fingerprint_library

@MainActor
struct IndoorShelfLabelTests {
    @Test("실제 308개 면을 fixture·층에 연결하고 범위·기타 분류·빈 서가를 보존한다")
    func loadsAllLibraryLabels() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        #expect(labels.count == 308)
        #expect(Set(labels.map(\.id)).count == 308)
        #expect(labels.filter { if case .callNumberRange = $0.content { true } else { false } }.count == 284)
        #expect(labels.filter { if case .category = $0.content { true } else { false } }.count == 20)
        #expect(labels.filter { $0.content == .emptyShelf }.count == 4)
        let first = try #require(labels.first { $0.fixtureNumber == "S-3F-657-A" })
        #expect(first.realNumber == "301")
        #expect(first.content == .callNumberRange(start: "AC1.G72", end: "AM79.K8"))
        #expect(map.features.first { $0.id == first.mapElementID }?.name == first.fixtureNumber)
        for floor in map.floors {
            #expect(labels.filter { $0.floorID == floor.id }.count == ([2, 3].contains(floor.ordinal) ? 154 : 0))
        }
        let root = try #require(Bundle.main.url(forResource: "IndoorMaps", withExtension: nil))
        let data = try Data(contentsOf: root.appendingPathComponent("POSTECHLibrary/shelfdata.json"))
        #expect(SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                == "972d397b5b68884c5fa48c971320cc400c422dea7914673d060a6c8b5f372e70")
    }

    enum Corruption: CaseIterable, Sendable { case unknownFixture, wrongFloor, wrongSide, duplicate, partialRange, mixedCategory, wrongType }

    @Test("서가 도형·층·면·중복·부분 범위·잘못된 필드를 거부한다", arguments: Corruption.allCases)
    func rejectsInvalidRecords(_ corruption: Corruption) async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let root = try #require(Bundle.main.url(forResource: "IndoorMaps", withExtension: nil))
        let data = try Data(contentsOf: root.appendingPathComponent("POSTECHLibrary/shelfdata.json"))
        let object = try JSONSerialization.jsonObject(with: data)
        var rows = try #require(object as? [[String: Any]])
        try #require(!rows.isEmpty)
        switch corruption {
        case .unknownFixture: rows[0]["fixtureNumber"] = "S-3F-unknown-A"
        case .wrongFloor: rows[0]["floor"] = "4F"
        case .wrongSide: rows[0]["side"] = "B"
        case .duplicate: rows.append(rows[0])
        case .partialRange: rows[0]["callEnd"] = ""
        case .mixedCategory: rows[0]["other"] = "기타 구역"
        case .wrongType: rows[0]["realNumber"] = 301
        }
        #expect(throws: ShelfLabelLoadError.self) {
            try BundledShelfLabelLoader().decode(JSONSerialization.data(withJSONObject: rows), on: map)
        }
    }

    @Test("실제 서가의 도형 중심에 읽을 수 있는 번호·범위와 기타 분류·빈 서가 문구를 놓는다")
    func rendersLabelsOnShelfGeometry() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        for label in labels {
            let annotation = IndoorShelfLabelAnnotation(label)
            #expect(label.geometry.contains(.init(latitude: annotation.coordinate.latitude, longitude: annotation.coordinate.longitude)))
            #expect(annotation.title == "\(label.realNumber)-\(label.side.rawValue)")
        }
        let first = try #require(labels.first)
        let annotation = IndoorShelfLabelAnnotation(first)
        let view = IndoorShelfLabelView(annotation: annotation, reuseIdentifier: IndoorShelfLabelView.reuseID)
        view.configure(annotation)
        #expect(annotation.title == "301-A")
        #expect(annotation.subtitle == "AC1.G72 ~ AM79.K8")
        #expect(view.bounds.height >= 30)
        #expect(view.image?.size == view.bounds.size)
        #expect(view.collisionMode == .rectangle)
        #expect(view.displayPriority == .defaultHigh)
        let empty = try #require(labels.first { $0.content == .emptyShelf })
        #expect(IndoorShelfLabelAnnotation(empty).subtitle == "빈 서가")
    }

    @Test("층 전환과 일반 상태 갱신은 레이블을 중복 생성하거나 카메라를 옮기지 않는다")
    func followsFloorWithoutMovingCamera() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        func parent(_ ordinal: Int) -> IndoorMapKitView {
            IndoorMapKitView(map: map, floor: map.floors.first { $0.ordinal == ordinal }!, selectedFeatureID: nil,
                            position: nil, showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
                            onSelect: { _ in }, onPlaceOrigin: { _ in }, shelfLabels: labels)
        }
        let coordinator = parent(2).makeCoordinator()
        let view = coordinator.makeMapView()
        defer { view.delegate = nil }
        view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        coordinator.moveCamera(.init(id: 1, target: .initialFloor(parent(2).floor.id)), in: view, animated: false)
        coordinator.update(parent: parent(2), in: view)
        let annotations = view.annotations.compactMap { $0 as? IndoorShelfLabelAnnotation }
        #expect(!annotations.isEmpty)
        let first = try #require(annotations.first)
        coordinator.update(parent: parent(2), in: view)
        #expect(view.annotations.contains { ($0 as AnyObject) === first })
        let camera = view.camera.copy() as! MKMapCamera
        for ordinal in [3, 0, 2] {
            coordinator.update(parent: parent(ordinal), in: view)
            let visible = view.annotations.compactMap { $0 as? IndoorShelfLabelAnnotation }
            #expect(ordinal == 0 ? visible.isEmpty : !visible.isEmpty)
            #expect(visible.allSatisfy { $0.label.floorID == parent(ordinal).floor.id })
            #expect(view.camera.centerCoordinate.latitude == camera.centerCoordinate.latitude)
            #expect(view.camera.centerCoordinate.longitude == camera.centerCoordinate.longitude)
            #expect(view.camera.centerCoordinateDistance == camera.centerCoordinateDistance)
            #expect(coordinator.pendingCameraRequest == nil)
        }
    }
}
