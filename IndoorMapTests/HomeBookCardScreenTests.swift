import ComposableArchitecture
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import fingerprint_library

extension IndoorMapSerialTests {
    @MainActor
    struct HomeBookCardScreenTests {
        @Test("추천 카드가 위치·이용 상태·누락·실패를 표시한다")
        func rendersLibraryInformation() async throws {
            let cases = ["사피엔스", "대출할 수 없는 책", "소장 정보 없는 책", "조회 실패 도서"]
            let books = cases.enumerated().map { index, title in
                Book(id: "book-\(index)", isbn: nil, controlNumber: "alma99100095875970328\(index)",
                     title: title, author: "저자 \(index + 1)", publisher: nil, publicationYear: nil,
                     description: nil, imageURL: nil)
            }
            var initial = HomeFeature.State()
            initial.departmentName = "반도체공학과"
            initial.recommendedBooks = books
            initial.popularBooks = books
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
            let host = UIHostingController(rootView: NavigationStack { HomeView(store: store) })
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer { window.isHidden = true; window.rootViewController = nil }
            for _ in 0..<100 {
                if store.libraryInfo.count == 4, !store.libraryInfo.values.contains(.loading) { break }
                try await Task.sleep(for: .milliseconds(50))
            }
            #expect(store.libraryInfo[books[0].id] == .loaded(.init(holdings: [Self.holding(status: "available")])))
            #expect(store.libraryInfo[books[1].id] == .loaded(.init(holdings: [Self.holding(status: "unavailable")])))
            #expect(store.libraryInfo[books[2].id] == .loaded(.init(holdings: [])))
            #expect(store.libraryInfo[books[3].id] == .failed)
            try await Task.sleep(for: .milliseconds(300))
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            try image.pngData()?.write(to: FileManager.default.temporaryDirectory.appendingPathComponent("home-book-card-issue88.png"))
            #expect(store.popularBooks == books)
            store.send(.bookSelected(books[0]))
            #expect(store.detail?.book == books[0])
        }

        private nonisolated static func holding(status: String) -> BookHolding {
            .init(holdingID: "h1", institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
                  locationCode: "c3b", locationName: "단행본3층", callNumber: "CB113.H4 .H3713 2015", availability: status)
        }
    }
}
