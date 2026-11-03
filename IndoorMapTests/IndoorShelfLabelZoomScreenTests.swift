import MapKit
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorShelfLabelZoomScreenTests {
        @Test("지도 회전 시 군집은 수평을 유지하고 번호·A/B는 서가 방향을 따라 하트와 함께 표시된다", arguments: ["303", "335", "313"])
        func displaysThreeLevels(shelfNumber: String) async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            let floor = try #require(map.floors.first { $0.ordinal == 2 })
            let layout = IndoorShelfLabelLayout(labels: labels)
            let shelf = try #require(layout.numbers.first { $0.text == shelfNumber })
            let group = try #require(layout.groups.first { $0.members.contains { $0.realNumber == shelfNumber } })
            let coordinate = IndoorMapCoordinate(latitude: shelf.coordinate.latitude, longitude: shelf.coordinate.longitude)
            let marker = HomeMapMarker(id: "favorite-test", kind: .favorite, floorID: floor.id,
                coordinate: coordinate, title: "찜한 도서")
            let facility = HomeMapMarker(id: "facility-test", kind: .printer, floorID: floor.id,
                coordinate: .init(latitude: group.coordinate.latitude, longitude: group.coordinate.longitude), title: "프린터")
            let parent = IndoorMapKitView(map: map, floor: floor, selectedFeatureID: nil,
                position: nil, showsUserLocation: false, isPlacingOrigin: false, cameraRequest: nil,
                onSelect: { _ in }, onPlaceOrigin: { _ in }, shelfLabels: labels,
                appearance: .home, homeMarkers: [marker, facility])
            let coordinator = parent.makeCoordinator()
            let view = coordinator.makeMapView()
            view.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIViewController()
            window.rootViewController = host
            host.view.addSubview(view)
            window.makeKeyAndVisible()
            defer { coordinator.detachMapView(); window.isHidden = true; window.rootViewController = nil }
            coordinator.update(parent: parent, in: view)
            let pointsPerMeter = MKMapPointsPerMeterAtLatitude(shelf.coordinate.latitude)
            for (level, scale) in [(IndoorShelfLabelLevel.group, 0.25), (.number, 0.07), (.side, 0.025), (.side, 0.008)] {
                let width = 390 * scale * pointsPerMeter, height = 800 * scale * pointsPerMeter
                for heading in [0.0, 55.0] {
                    let northCamera = view.camera.copy() as! MKMapCamera
                    northCamera.heading = 0
                    view.setCamera(northCamera, animated: false)
                    view.setVisibleMapRect(.init(x: shelf.point.x - width / 2, y: shelf.point.y - height / 2,
                                                width: width, height: height), animated: false)
                    let camera = view.camera.copy() as! MKMapCamera
                    camera.heading = heading
                    view.setCamera(camera, animated: false)
                    coordinator.mapView(view, regionDidChangeAnimated: false)
                    try await Task.sleep(for: .milliseconds(600))
                    let shown = view.annotations.compactMap { $0 as? IndoorShelfLabelAnnotation }
                    if scale > 0.01 { #expect(!shown.isEmpty) }
                    #expect(shown.allSatisfy { level == .group ? $0.presentation.level == .group : $0.presentation.level != .group })
                    if level == .number { #expect(shown.contains { $0.title == shelfNumber }) }
                    if level == .side && scale > 0.01 {
                        #expect(shown.contains { $0.title == "\(shelfNumber)-A" })
                        #expect(shown.contains { $0.title == "\(shelfNumber)-B" })
                    }
                    let views = shown.compactMap { view.view(for: $0) as? IndoorShelfLabelView }
                        .filter { !$0.isHidden && $0.alpha > 0 }
                    if scale > 0.01 { #expect(!views.isEmpty) }
                    if level == .number || (level == .side && scale > 0.01) {
                        let expected = level == .number ? [shelfNumber] : ["\(shelfNumber)-A", "\(shelfNumber)-B"]
                        for text in expected {
                            #expect(shown.contains { $0.title == text && view.view(for: $0)?.isHidden == false
                                && (view.view(for: $0)?.alpha ?? 0) > 0 })
                        }
                    }
                    #expect(views.allSatisfy { $0.image == nil && $0.backgroundColor == .clear })
                    for annotation in shown where annotation.presentation.level == .group {
                        #expect(annotation.layoutOffset == .zero)
                    }
                    let groupAnnotation = shown.first { $0.presentation.id == group.id }
                    if level == .group {
                        #expect(groupAnnotation != nil)
                        #expect(groupAnnotation?.layoutOffset == .zero)
                    }
                    for labelView in views {
                        #expect(labelView.zPriority == .min)
                        let text = try #require(labelView.subviews.compactMap { $0 as? UILabel }.first)
                        let left = text.convert(CGPoint.zero, to: window)
                        let right = text.convert(CGPoint(x: text.bounds.width, y: 0), to: window)
                        if level == .group {
                            #expect(abs(left.y - right.y) < 0.01)
                        } else {
                            let annotation = try #require(labelView.annotation as? IndoorShelfLabelAnnotation)
                            let (a, b) = try #require(annotation.presentation.axis)
                            let p = view.convert(a.coordinate, toPointTo: view)
                            let q = view.convert(b.coordinate, toPointTo: view)
                            let axis = CGPoint(x: q.x - p.x, y: q.y - p.y)
                            let direction = CGPoint(x: right.x - left.x, y: right.y - left.y)
                            let cross = axis.x * direction.y - axis.y * direction.x
                            #expect(abs(cross) / (hypot(axis.x, axis.y) * hypot(direction.x, direction.y)) < 0.001)
                        }
                        #expect(right.x >= left.x - 0.01)
                    }
                    if scale < 0.01 && heading == 0 && shelfNumber != "313" {
                        // 양 끝의 원래 자리가 화면 밖이면 가운데로 끌어오지 않는다.
                        #expect(!shown.contains { $0.title == "\(shelfNumber)-A" || $0.title == "\(shelfNumber)-B" })
                    }
                    #expect(view.annotations.contains { $0 is HomeMapPointAnnotation })
                    for annotation in view.annotations.compactMap({ $0 as? HomeMapPointAnnotation }) {
                        if let icon = view.view(for: annotation) {
                            #expect(icon.centerOffset == .zero)
                            #expect(icon.zPriority.rawValue > MapAnnotationPriority.shelf.rawValue)
                            #expect(icon.zPriority.rawValue < MapAnnotationPriority.user.rawValue)
                            #expect(icon.displayPriority == .required)
                        }
                    }
                    let image = UIGraphicsImageRenderer(bounds: view.bounds).image { _ in
                        view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
                    }
                    try image.pngData()?.write(to: FileManager.default.temporaryDirectory
                        .appendingPathComponent("issue268-fixed-\(shelfNumber)-\(scale)-\(Int(heading)).png"))
                    if level == .side && scale > 0.01 {
                        func location(_ label: IndoorShelfLabelAnnotation) -> MKMapPoint {
                            let anchor = view.convert(label.coordinate, toPointTo: view)
                            let pixel = CGPoint(x: anchor.x + label.layoutOffset.x, y: anchor.y + label.layoutOffset.y)
                            return MKMapPoint(view.convert(pixel, toCoordinateFrom: view))
                        }
                        let fixed = Dictionary(uniqueKeysWithValues: shown.map { ($0.presentation.id, location($0)) })
                        let shifted = view.camera.copy() as! MKMapCamera
                        let center = MKMapPoint(shifted.centerCoordinate)
                        shifted.centerCoordinate = MKMapPoint(x: center.x + view.visibleMapRect.width * 0.4, y: center.y).coordinate
                        view.setCamera(shifted, animated: false)
                        coordinator.mapView(view, regionDidChangeAnimated: false)
                        try await Task.sleep(for: .milliseconds(100))
                        for label in view.annotations.compactMap({ $0 as? IndoorShelfLabelAnnotation }) {
                            if let original = fixed[label.presentation.id] {
                                #expect(location(label).distance(to: original) < 0.02)
                            }
                        }
                        view.setCamera(camera, animated: false)
                        coordinator.mapView(view, regionDidChangeAnimated: false)
                    }
                }
            }
        }
    }
}
