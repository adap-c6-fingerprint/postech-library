import Observation
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct HomeTopBarBlurScreenTests {
        @Test("카트 화면을 여러 번 왕복해도 배경 블러가 처음 강도를 유지한다", arguments: [false, true])
        func blurStaysWeakAfterNavigation(usesSwiftUINavigation: Bool) async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let root = ZStack(alignment: .top) {
                HStack(spacing: 0) { Color.white; Color.black }
                LibraryTopBarBackground()
            }
            .ignoresSafeArea()
            .environment(\.scenePhase, .active)
            let state = NavigationState()
            let host = UIHostingController(rootView: usesSwiftUINavigation
                ? AnyView(NavigationHarness(state: state, background: AnyView(root))) : AnyView(root))
            host.overrideUserInterfaceStyle = .dark
            if usesSwiftUINavigation {
                window.rootViewController = host
            } else {
                let navigation = UINavigationController(rootViewController: host)
                navigation.setNavigationBarHidden(true, animated: false)
                window.rootViewController = navigation
            }
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(for: .milliseconds(300))
            let rootController = try #require(window.rootViewController)
            let navigation = try #require(navigation(in: rootController))
            let edge = window.bounds.midX
            let baseline = snapshot(window)
            var transitionSamples = 0
            for attempt in 1...3 {
                if usesSwiftUINavigation {
                    state.showsCart = true
                } else {
                    let cart = UIHostingController(rootView: Text("책바구니").frame(maxWidth: .infinity, maxHeight: .infinity).background(.black))
                    navigation.setNavigationBarHidden(false, animated: false)
                    navigation.pushViewController(cart, animated: true)
                }
                try await waitUntil { navigation.viewControllers.count == 2 && navigation.transitionCoordinator == nil }
                let departingView = try #require(navigation.topViewController?.view)
                if usesSwiftUINavigation {
                    state.showsCart = false
                } else {
                    navigation.setNavigationBarHidden(true, animated: false)
                    navigation.popViewController(animated: true)
                }
                for sample in 1...10 {
                    try await Task.sleep(for: .milliseconds(80))
                    let blur = try #require(findBlur(in: host.view))
                    let layer = blur.layer.presentation() ?? blur.layer
                    let windowLayer = window.layer.presentation() ?? window.layer
                    let point = layer.convert(CGPoint(x: blur.bounds.midX, y: 180), to: windowLayer)
                    let departingLayer = departingView.layer.presentation() ?? departingView.layer
                    let coveredFromX = departingView.window == nil ? window.bounds.width
                        : departingLayer.convert(.zero, to: windowLayer).x
                    let frame = snapshot(window, afterScreenUpdates: false)
                    // presentation 레이어 좌표와 drawHierarchy의 캡처 시점은 같지 않다.
                    // 같은 이미지의 블러 아래쪽 경계로 x를 구해, 이동 중인 경계 밖을 흐림으로 오인하지 않는다.
                    guard let edgeX = try sharpEdgeX(in: frame, y: min(window.bounds.height - 20, max(400, window.bounds.height * 0.65))),
                          edgeX > 12, edgeX + 30 < coveredFromX else { continue }
                    var sharpestStep = 0.0
                    for offset in -10..<10 {
                        let left = try brightness(frame, x: edgeX + CGFloat(offset), y: point.y)
                        let right = try brightness(frame, x: edgeX + CGFloat(offset + 1), y: point.y)
                        sharpestStep = max(sharpestStep, left - right)
                    }
                    let inTransition = navigation.transitionCoordinator != nil
                    if inTransition { transitionSamples += 1 }
                    print("TOP_BLUR_TRANSITION swiftui=\(usesSwiftUINavigation) attempt=\(attempt) sample=\(sample) transitioning=\(inTransition) sharpestStep=\(sharpestStep)")
                    #expect(sharpestStep > 0.25, "복귀 애니메이션 중에도 경계가 강하게 흐려지면 안 됩니다")
                }
                try await waitUntil { navigation.viewControllers.count == 1 && navigation.transitionCoordinator == nil }
                let restored = snapshot(window)
                for y: CGFloat in [60, 180, 250] {
                    let before = try brightness(baseline, x: edge + 8, y: y)
                    let after = try brightness(restored, x: edge + 8, y: y)
                    print("TOP_BLUR_RETURN swiftui=\(usesSwiftUINavigation) attempt=\(attempt) y=\(y) before=\(before) after=\(after)")
                    #expect(abs(after - before) < 0.03, "화면 복귀 후 블러가 진해지면 안 됩니다")
                    let near = try brightness(restored, x: edge + 1, y: y)
                    let far = try brightness(restored, x: edge + 30, y: y)
                    #expect(near > far + 0.02, "복귀 후에도 옅은 블러는 남아야 합니다")
                }
            }
            #expect(transitionSamples > 0, "복귀가 끝나기 전의 화면도 검사해야 합니다")
        }

        @Observable
        final class NavigationState {
            var showsCart = false
        }

        private struct NavigationHarness: View {
            @Bindable var state: NavigationState
            let background: AnyView

            var body: some View {
                NavigationStack {
                    background
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(isPresented: $state.showsCart) {
                            Text("책바구니")
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .background(.black)
                                .toolbar(.visible, for: .navigationBar)
                        }
                }
            }
        }

        private func navigation(in controller: UIViewController) -> UINavigationController? {
            if let value = controller as? UINavigationController { return value }
            return controller.children.compactMap { navigation(in: $0) }.first
        }

        private func waitUntil(_ predicate: () -> Bool) async throws {
            for _ in 0..<100 {
                if predicate() { return }
                try await Task.sleep(for: .milliseconds(50))
            }
            try #require(predicate(), "화면 전환 완료 대기 시간이 초과됐습니다")
        }

        @Test("옅은 기본 블러가 화면 위부터 인사 문구 높이까지 실제로 적용된다")
        func blurCoversGreeting() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let root = ZStack(alignment: .top) {
                HStack(spacing: 0) { Color.white; Color.black }
                LibraryTopBarBackground()
            }
            .ignoresSafeArea()
            .environment(\.scenePhase, .active)
            let host = UIHostingController(rootView: root)
            host.overrideUserInterfaceStyle = .dark
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(for: .milliseconds(250))

            let blur = try #require(findBlur(in: host.view))
            let frame = blur.convert(blur.bounds, to: window)
            #expect(abs(frame.minY) < 0.5)
            #expect(abs(frame.height - 361) < 0.5)
            #expect(blur.alpha == 1, "블러를 약하게 하려고 원본 지도가 그대로 비치게 만들면 안 됩니다")
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let edge = window.bounds.midX
            for y: CGFloat in [60, 180, 250] {
                let near = try brightness(image, x: edge + 1, y: y)
                let far = try brightness(image, x: edge + 30, y: y)
                let distant = try brightness(image, x: edge + 8, y: y)
                print("TOP_BLUR_EDGE y=\(y) near=\(near) distant=\(distant) far=\(far)")
                #expect(near > far + 0.02, "인사 문구 높이에서도 경계가 흐려져야 합니다")
                #expect(distant < far + 0.04, "블러가 경계에서 멀리 번지지 않도록 옅게 적용해야 합니다")
            }
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory
                .appendingPathComponent("home-top-bar-blur-pixels.png"))
        }

        private func findBlur(in view: UIView) -> UIVisualEffectView? {
            if let effect = view as? UIVisualEffectView,
               effect.accessibilityIdentifier == "library-top-bar-blur" { return effect }
            return view.subviews.compactMap { findBlur(in: $0) }.first
        }

        private func snapshot(_ window: UIWindow, afterScreenUpdates: Bool = true) -> UIImage {
            UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: afterScreenUpdates)
            }
        }

        private func sharpEdgeX(in image: UIImage, y: CGFloat) throws -> CGFloat? {
            let source = try #require(image.cgImage)
            let row = try #require(source.cropping(to: CGRect(x: 0, y: y * image.scale, width: CGFloat(source.width), height: 1)))
            var bytes = [UInt8](repeating: 0, count: row.width * 4)
            try bytes.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: row.width, height: 1,
                    bitsPerComponent: 8, bytesPerRow: row.width * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(row, in: CGRect(x: 0, y: 0, width: CGFloat(row.width), height: 1))
            }
            var best: (x: CGFloat, contrast: Double)?
            for x in 12..<(Int(image.size.width) - 30) {
                let left = Int(CGFloat(x) * image.scale) * 4
                let right = Int(CGFloat(x + 1) * image.scale) * 4
                let contrast = (Double(bytes[left]) - Double(bytes[right])) / 255
                if contrast > (best?.contrast ?? 0.25) { best = (CGFloat(x), contrast) }
            }
            return best?.x
        }

        private func brightness(_ image: UIImage, x: CGFloat, y: CGFloat) throws -> Double {
            let cgImage = try #require(image.cgImage)
            let pixel = try #require(cgImage.cropping(to: CGRect(x: x * image.scale, y: y * image.scale, width: 1, height: 1)))
            var rgba = [UInt8](repeating: 0, count: 4)
            try rgba.withUnsafeMutableBytes { buffer in
                let context = try #require(CGContext(data: buffer.baseAddress, width: 1, height: 1,
                    bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
                context.draw(pixel, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            }
            return Double(rgba[0]) / 255
        }
    }
}
