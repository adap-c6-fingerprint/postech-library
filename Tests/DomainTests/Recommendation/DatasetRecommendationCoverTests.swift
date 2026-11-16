import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct DatasetRecommendationCoverTests {
    @Test func 표지_URL이_없는_책은_6선_후보에서_빠진다() {
        let covered = makeBook(1, imageURL: URL(string: "https://example.com/1.jpg"))
        let uncovered = makeBook(2)
        let alsoCovered = makeBook(3, imageURL: URL(string: "https://example.com/3.jpg"))

        let candidates = DatasetRecommendation.coveredCandidates(from: [covered, uncovered, alsoCovered])

        #expect(candidates.map(\.id) == [covered.id, alsoCovered.id])
    }

    @Test func 모두_표지가_없으면_후보가_없다() {
        #expect(DatasetRecommendation.coveredCandidates(from: [makeBook(1), makeBook(2)]).isEmpty)
    }
}
