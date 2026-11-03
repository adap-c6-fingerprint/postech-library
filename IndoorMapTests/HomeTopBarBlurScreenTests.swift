import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct HomeTopBarBlurScreenTests {
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
