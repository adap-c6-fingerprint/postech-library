import ComposableArchitecture
import MapKit
import SwiftUI
import Testing
import UIKit
import Vision
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookNavigationDesignScreenTests {
        @Test("현재 책의 경로를 표시하고 시트를 올리면 현재 도서 정보를 보여준다", arguments: [false, true])
        func collapsedAndExpandedSheet(expanded: Bool) async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
            let candidates = BookRoutePreviewSample.testItems.prefix(expanded ? 3 : 1).map { item in
                BookRouteCandidateStop(book: item.book, holdings: [item.holding], candidateShelves:
                    BookHoldingShelfResolver().resolve([item.holding], on: map, labels: labels).flatMap(\.shelves))
            }
            let session = try await BookRoutePreviewTestRouteLoader().load(on: map, labels: labels,
                start: try await bookRouteTestStart(on: map, labels: labels), stops: candidates)
            var initial = BookNavigationFeature.State(session: session)
            let position = IndoorPosition(coordinate: session.start.coordinate, floorOrdinal: session.start.floorOrdinal,
                horizontalAccuracy: 0, timestamp: Date(), source: .simulation)
            initial.isActive = true
            initial.authorization = .authorized(precise: true)
            initial.rawPosition = position
            initial.latestPosition = position
            initial.progress = try initial.currentPlan?.progress(for: position, at: position.timestamp)
            initial.statusMessage = nil
            initial.arrivalSpines = Dictionary(uniqueKeysWithValues: session.stops.indices.map { ($0, .unavailable) })
            let store = Store(initialState: initial) { BookNavigationFeature() } withDependencies: {
                $0.date = .constant(position.timestamp)
                $0.indoorLocationClient = .testValue
            }
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let host = UIHostingController(rootView: BookNavigationView(store: store).environment(\.scenePhase, .active))
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { host.dismiss(animated: false); store.send(.disappeared); window.isHidden = true; window.rootViewController = nil }
            try await waitUntil { findMap(host.view)?.window != nil }
            #expect(host.presentedViewController == nil, "안내 시트는 모달 대신 지도 위 오버레이로 표시해야 합니다")
            if expanded {
                store.send(.sheetExpansionChanged(true))
            }
            try await Task.sleep(for: .milliseconds(500))
            let surface = try #require(findMap(host.view))
            let destinations = surface.annotations.compactMap { $0 as? BookNavigationDestinationAnnotation }
            #expect(destinations.count == 1)
            #expect(destinations.first?.destination.book == session.stops[0].book)
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory
                .appendingPathComponent(expanded ? "issue307-navigation-expanded.png" : "issue307-navigation-collapsed.png"))
            if let cgImage = image.cgImage {
                let request = VNRecognizeTextRequest()
                request.recognitionLanguages = ["ko-KR", "en-US"]
                request.recognitionLevel = .accurate
                try VNImageRequestHandler(cgImage: cgImage).perform([request])
                let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
                let showsCurrentBook = text.contains("현재 책") || text.contains("현재책")
                #expect(showsCurrentBook == expanded, "현재 책 정보는 펼친 상태에서만 보여야 합니다: \(text)")
                if expanded {
                    #expect(text.contains("층 이동") || text.contains("층이동"), "거리와 층 이동 횟수가 잘리지 않아야 합니다: \(text)")
                }
            }
            store.send(.cancelTapped)
            try await waitUntil { host.presentedViewController is UIAlertController }
            let pause = try #require(host.presentedViewController as? UIAlertController)
            #expect(pause.actions.contains { $0.title == "돌아가기" })
            #expect(pause.actions.contains { $0.title == "안내 종료하기" })
            #expect(pause.actions.contains { $0.title == "다음 책 찾기" } == expanded)
            store.send(.cancelDismissed)
            try await waitUntil { host.presentedViewController == nil }
            if expanded {
                store.send(.arrivalTestTapped)
                try await waitUntil {
                    host.presentedViewController == nil
                        && navigation(host)?.viewControllers.count == 2
                        && navigation(host)?.transitionCoordinator == nil
                }
                store.send(.continueFromArrival(stopIndex: 0))
                try await waitUntil {
                    host.presentedViewController == nil
                        && findMap(host.view)?.window != nil
                        && navigation(host)?.viewControllers.count == 1
                        && navigation(host)?.transitionCoordinator == nil
                }
                #expect(store.currentStopIndex == 1)
                #expect(store.isSheetExpanded, "책찾기에서 돌아와도 펼침 상태를 유지해야 합니다")
            }
            store.send(.cancelConfirmed)
            try await waitUntil { host.presentedViewController == nil && host.transitionCoordinator == nil }
        }

        private func findMap(_ view: UIView) -> MKMapView? {
            if let map = view as? MKMapView { return map }
            return view.subviews.compactMap(findMap).first
        }
        private func navigation(_ controller: UIViewController) -> UINavigationController? {
            if let navigation = controller as? UINavigationController { return navigation }
            return controller.children.compactMap(navigation).first
        }
        private func waitUntil(_ predicate: () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(30))
            }
            try #require(predicate(), "안내 시트 전환이 완료되지 않았습니다")
        }
    }
}
