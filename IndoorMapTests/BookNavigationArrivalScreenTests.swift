import SwiftUI
import Testing
import UIKit
import Vision
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct BookNavigationArrivalScreenTests {
        @Test("도착 화면은 단권·중간·마지막 책과 누락 정보를 구분한다", arguments: ["single", "middle", "last", "missing", "compact", "large-text"])
        func rendersArrival(scenario: String) async throws {
            let base = try BookNavigationDetailsTestFixture.session(holdings: scenario == "missing" ? [] : [
                BookHoldingTestData.holding(call: "QA76.73 .P98 2021")
            ])
            let coverURL = try coverFixture()
            let book = Book(id: "arrival-cover", isbn: nil, controlNumber: nil, title: "푸울에 풍덩", author: "이재은",
                            publisher: nil, publicationYear: "2021", description: nil, imageURL: coverURL)
            let first = BookNavigationStop(book: book, holdings: base.stops[0].holdings, shelf: base.stops[0].shelf)
            let isMultiple = scenario == "middle" || scenario == "last"
            let session = try BookNavigationSession(map: base.map, shelfLabels: base.shelfLabels,
                stops: isMultiple ? [first, base.stops[1]] : [first], legs: isMultiple ? base.legs : [base.legs[0]],
                graph: base.graph, origin: base.origin, start: base.start)
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let size = scenario == "compact" ? CGSize(width: 320, height: 568) : CGSize(width: 393, height: 852)
            let view = NavigationStack {
                BookNavigationArrivalView(session: session, currentStopIndex: scenario == "last" ? 1 : 0)
            }
            .environment(\.dynamicTypeSize, scenario == "large-text" ? .accessibility2 : .large)
            .frame(width: size.width, height: size.height)
            let host = UIHostingController(rootView: view)
            host.overrideUserInterfaceStyle = .dark
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            try await Task.sleep(for: .milliseconds(700))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory
                .appendingPathComponent("issue133-\(scenario).png"))
            let text = try await recognizedText(image)
            #expect(text.contains("찾았어요"))
            if scenario == "missing" {
                #expect(text.contains("청구기호확인필요"))
                #expect(text.contains("367-A"))
            } else if scenario != "large-text", scenario != "last" {
                #expect(text.contains("76.73"))
                #expect(text.contains("P98"))
                #expect(text.contains("2021"))
            }
            if isMultiple { #expect(text.contains(scenario == "last" ? "2/2" : "1/2")) }
            else { #expect(!text.contains("1/1")) }
        }

        @concurrent
        private func recognizedText(_ image: UIImage) async throws -> String {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: #require(image.cgImage), options: [:]).perform([request])
            return String((request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
                .filter { !$0.isWhitespace })
        }

        /// 네트워크 없이 표지의 로딩·비율·회전을 확인하는 테스트 전용 이미지다.
        private func coverFixture() throws -> URL {
            let size = CGSize(width: 230, height: 330)
            let image = UIGraphicsImageRenderer(size: size).image { context in
                UIColor(red: 0.22, green: 0.65, blue: 0.8, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                for y in stride(from: 30, through: 300, by: 60) {
                    UIColor.white.withAlphaComponent(0.5).setStroke()
                    context.cgContext.stroke(CGRect(x: 0, y: y, width: 230, height: 1))
                }
                ("푸울에\n풍덩" as NSString).draw(in: CGRect(x: 26, y: 100, width: 180, height: 160),
                    withAttributes: [.font: UIFont.systemFont(ofSize: 40, weight: .bold), .foregroundColor: UIColor.white])
            }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("issue133-cover-fixture.png")
            try image.pngData()?.write(to: url)
            return url
        }
    }
}
