import ComposableArchitecture
import SwiftUI
import Testing
import UIKit
import Vision
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct IndoorMapFloorPickerLayoutTests {
        @Test("낮은 지도와 세로 지도 모두 모든 층을 스크롤 없이 표시한다", arguments: [false, true], [false, true])
        func keepsAllFloorsVisible(isHome: Bool, isShort: Bool) async throws {
            let map = try await BundledIndoorMapLoader().loadLibrary()
            var initial = IndoorMapFeature.State()
            initial.map = map
            initial.selectedFloorID = map.floors.first?.id
            initial.locationMessage = "현재 위치를 확인하고 있어요"
            let store = Store(initialState: initial) { IndoorMapFeature() }
            // 가로 화면이나 하단 시트 때문에 지도 높이가 줄어든 경우를 같은 폭에서 재현한다.
            let size = CGSize(width: 390, height: isShort ? 240 : 800)
            let host = UIHostingController(rootView: IndoorMapView(
                store: store, showsDestinationCard: false, bottomContentInset: 40,
                appearance: isHome ? .home : .standard, extendsUnderBottomSafeArea: false
            )
                .frame(width: size.width, height: size.height)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .ignoresSafeArea())
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(for: .milliseconds(500))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(size: size).image { _ in
                host.view.drawHierarchy(in: host.view.bounds, afterScreenUpdates: true)
            }
            let name = "pr264-floor-picker-\(isHome ? "home" : "standard")-\(isShort ? "short" : "tall").png"
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent(name))
            let text = try await recognizedText(image)
            for floor in map.floors {
                let label = isHome ? "\(floor.ordinal + 1)F" : floor.name
                #expect(text.contains(label), "지도 표시 영역 안에 \(label) 버튼이 보여야 한다: \(text)")
            }
        }

        @concurrent
        private func recognizedText(_ image: UIImage) async throws -> String {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: #require(image.cgImage), options: [:]).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
                .joined().filter { !$0.isWhitespace }
        }
    }
}
