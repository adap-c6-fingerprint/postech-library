import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct ShelfOverlapRequestTests {
    @Test("인접 후보는 모두 경로 입력에 전달하고 먼 서가·다른 층·빈 후보는 거부한다")
    func validatesRouteCandidates() async throws {
        let map = try await BundledIndoorMapLoader().loadLibrary()
        let labels = try await BundledShelfLabelLoader().loadLibrary(on: map)
        let book = BookHoldingTestData.book()
        let holding = BookHoldingTestData.holding(call: "HD30.29.K5")
        var state = BookShelfMapFeature.State(book: book)
        state.map.map = map
        state.map.shelfLabels = labels
        state.holdings[book.id] = .loaded([holding])
        state.resolutions[book.id] = BookHoldingShelfResolver().resolve([holding], on: map, labels: labels)
        let start = try await bookRouteTestStart(on: map, labels: labels)
        guard case .ready(_, _, _, let received) = BookRoutePreviewRequest(state: state, start: start) else {
            Issue.record("확인된 인접 후보를 경로 입력에 전달하지 못했습니다."); return
        }
        #expect(received.count == 1)
        #expect(Set(received[0].candidateShelves.map(\.fixtureNumber)) == ["S-3F-524-A", "S-3F-524-B"])
        let third = try #require(labels.first { $0.fixtureNumber == "S-3F-524-A" })
        let distant = try #require(labels.first { $0.fixtureNumber == "S-3F-657-A" })
        let fourth = try #require(labels.first { $0.fixtureNumber == "S-4F-804-A" })
        for shelves in [[], [third, distant], [third, fourth]] {
            state.resolutions[book.id] = [.init(holding: holding, outcome: .candidates(shelves))]
            guard case .failed = BookRoutePreviewRequest(state: state) else {
                Issue.record("확인되지 않은 후보를 경로에 사용했습니다."); continue
            }
        }
    }
}
