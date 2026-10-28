import ComposableArchitecture
import Foundation
import SwiftUI
import Testing
import UIKit
import Vision
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct HomeBookCardScreenTests {
        @Test("추천 카드가 위치·이용 상태·누락·실패 문구를 표시한다", arguments: 0..<4)
        func rendersLibraryInformation(scenario: Int) async throws {
            let cases = ["사피엔스", "자료 A", "자료 B", "자료 C"]
            let books = cases.enumerated().map { index, title in
                Book(id: "book-\(index)", isbn: nil, controlNumber: "alma99100095875970328\(index)",
                     title: title, author: "저자 \(index + 1)", publisher: nil, publicationYear: nil,
                     description: nil, imageURL: nil)
            }
            var initial = HomeFeature.State()
            initial.departmentName = "반도체공학과"
            initial.recommendedBooks = books
            let selectedBook = books[scenario]
            // 각 상태를 화면 안의 실제 카드 경로에서 확인한다.
            initial.popularBooks = [selectedBook]
            let store = Store(initialState: initial) { HomeFeature() } withDependencies: {
                $0.bookHoldingsClient.fetch = { recordID in
                    switch recordID.last {
                    case "0": return [Self.holding(status: "available")]
                    case "1": return [Self.holding(status: "unavailable")]
                    case "2": return []
                    default: throw URLError(.notConnectedToInternet)
                    }
                }
            }
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let mapStore = Store(initialState: IndoorMapFeature.State()) { IndoorMapFeature() }
            let host = UIHostingController(rootView: NavigationStack {
                HomeView(store: store, mapStore: mapStore)
            })
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            for _ in 0..<100 {
                if store.libraryInfo.count == 1, !store.libraryInfo.values.contains(.loading) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            let expected: HomeFeature.LibraryInfoState = switch scenario {
            case 0: .loaded(.init(holdings: [Self.holding(status: "available")]))
            case 1: .loaded(.init(holdings: [Self.holding(status: "unavailable")]))
            case 2: .loaded(.init(holdings: []))
            default: .failed
            }
            #expect(store.libraryInfo[selectedBook.id] == expected)
            let expectedText: [String] = switch scenario {
            case 0: ["3층 QA1", "대출 가능"]
            case 1: ["3층 QA1", "이용 불가"]
            case 2: ["소장 정보 없음", "대출 정보 없음"]
            default: ["소장 정보 확인 불가", "대출 상태 확인 필요"]
            }
            try await Task.sleep(for: .milliseconds(300))
            host.view.layoutIfNeeded()
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("home-book-card-issue88-\(scenario).png"))
            let renderedText = try recognizedText(in: image)
            #expect(renderedText.contains(withoutWhitespace(selectedBook.title)))
            #expect(renderedText.contains(withoutWhitespace(selectedBook.author)))
            for text in expectedText {
                #expect(renderedText.contains(withoutWhitespace(text)), "렌더링된 카드에 '\(text)'가 없습니다: \(renderedText)")
            }
            #expect(!renderedText.contains("단행본"))
            #expect(!renderedText.contains(withoutWhitespace(scenario == 0 ? "이용 불가" : "대출 가능")))
            #expect(store.popularBooks == [selectedBook])
            store.send(.bookSelected(selectedBook))
            #expect(store.detail?.book == selectedBook)
        }

        private func recognizedText(in image: UIImage) throws -> String {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["ko-KR", "en-US"]
            request.usesLanguageCorrection = false
            try VNImageRequestHandler(cgImage: #require(image.cgImage), options: [:]).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined()
            return withoutWhitespace(text)
        }

        private func withoutWhitespace(_ text: String) -> String {
            String(text.filter { !$0.isWhitespace })
        }

        private nonisolated static func holding(status: String) -> BookHolding {
            .init(holdingID: "h1", institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
                  locationCode: "c3b", locationName: "단행본3층", callNumber: "QA1", availability: status)
        }
    }
}
