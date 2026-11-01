import ComposableArchitecture
import MapKit
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookNavigationCameraScreenTests {
        private typealias F = NavigationGuidanceTestFixture

        @Test("실제 안내 화면에서 위치 스트림이 단계를 진행시키면 카메라 중심과 확대 범위가 바뀐다",
              arguments: [(false, Duration.zero), (true, .zero), (true, .milliseconds(300))])
        func followsProgressOnScreen(winding: Bool, subscriptionDelay: Duration) async throws {
            let session = try winding ? F.windingSession() : F.session()
            let coordinate = LockIsolated(F.position(x: 0).coordinate)
            let stream = AsyncStream<IndoorLocationEvent>.makeStream(bufferingPolicy: .bufferingNewest(10))
            let store = Store(initialState: BookNavigationFeature.State(session: session)) {
                BookNavigationFeature()
            } withDependencies: {
                $0.indoorLocationClient = .init(events: {
                    do { try await Task.sleep(for: subscriptionDelay) }
                    catch { return AsyncStream { $0.finish() } }
                    stream.continuation.yield(.authorization(.authorized(precise: true)))
                    return stream.stream
                }, requestPermission: {})
                $0.continuousClock = ContinuousClock()
                $0.date = .init { Date() }
            }
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: BookNavigationView(store: store).environment(\.scenePhase, .active))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                stream.continuation.finish()
                store.send(.disappeared)
                window.isHidden = true
                window.rootViewController = nil
            }
            // 구독과 권한 처리가 끝나기 전에는 위치 이벤트로 버퍼를 채우지 않는다.
            try await waitUntil { store.authorization == .authorized(precise: true) }
            let producer = Task { @MainActor in
                while !Task.isCancelled {
                    stream.continuation.yield(.position(.init(coordinate: coordinate.value,
                        floorOrdinal: session.start.floorOrdinal, horizontalAccuracy: 0,
                        timestamp: Date(), source: .simulation)))
                    do { try await Task.sleep(for: .milliseconds(20)) } catch { break }
                }
            }
            defer { producer.cancel() }
            try await waitUntil {
                guard let map = self.map(in: host.view), let coordinator = map.delegate as? IndoorMapKitView.Coordinator,
                      case .navigation = coordinator.lastCameraRequest?.target else { return false }
                return store.progress != nil
            }
            try await Task.sleep(for: .milliseconds(700))
            let map = try #require(map(in: host.view))
            let firstWidth = map.visibleMapRect.width
            let firstCenter = map.centerCoordinate
            let firstRequest = store.cameraRequest.id
            let positions: [(Double, Double)] = winding
                ? [(0, 4), (0, 8), (0, 12), (0, 16), (0, 20), (4, 20), (8, 20), (12, 20), (16, 20)]
                : [(4, 0), (8, 0), (12, 0), (16, 0), (20, 0), (20, 4), (20, 8), (20, 12), (20, 16), (20, 18)]
            for (x, y) in positions {
                coordinate.setValue(F.position(x: x, y: y).coordinate)
                try await waitUntil { store.latestPosition?.coordinate == coordinate.value }
                try await Task.sleep(for: .milliseconds(350))
            }
            try await Task.sleep(for: .milliseconds(700))
            #expect(store.progress?.stepIndex == 1)
            #expect(store.statusMessage == nil)
            #expect(store.followsNavigationCamera, "자동 카메라 이동이 사용자 조작으로 오인되면 안 됩니다")
            #expect(store.cameraRequest.id > firstRequest)
            let coordinator = try #require(map.delegate as? IndoorMapKitView.Coordinator)
            #expect(coordinator.lastCameraRequest == store.cameraRequest, "SwiftUI 갱신과 배치를 거쳐 최신 요청을 적용해야 합니다")
            #expect(map.visibleMapRect.width < firstWidth * 0.8,
                    "안내 화면의 실제 지도가 접근에 따라 확대되어야 합니다")
            let moved = RoutingGeometry.distanceMeters(
                from: .init(latitude: firstCenter.latitude, longitude: firstCenter.longitude),
                to: .init(latitude: map.centerCoordinate.latitude, longitude: map.centerCoordinate.longitude))
            #expect(moved > 2, "현재 위치와 다음 구간에 맞춰 포커스가 이동해야 합니다")
        }

        private func map(in view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            return view.subviews.lazy.compactMap { map(in: $0) }.first
        }

        private func waitUntil(_ condition: () -> Bool) async throws {
            let deadline = Date().addingTimeInterval(8)
            while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
            try #require(condition(), "위치·안내·지도 카메라가 같은 진행 상태를 반영해야 합니다")
        }
    }
}
