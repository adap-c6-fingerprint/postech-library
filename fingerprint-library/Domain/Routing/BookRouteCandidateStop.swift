import Foundation

/// 경로 계산 전의 책·소장 정보와 서가 후보. 목적지 한 곳으로 미리 확정하지 않는다.
struct BookRouteCandidateStop: Equatable, Sendable {
    let book: Book
    let holdings: [BookHolding]
    let candidateShelves: [IndoorShelfLabel]

    init(book: Book, holdings: [BookHolding], candidateShelves: [IndoorShelfLabel]) {
        self.book = book
        self.holdings = holdings
        // 동률인 후보도 결과가 일정하도록 사진 순서 대신 ID로 정렬한다.
        self.candidateShelves = candidateShelves.sorted { $0.fixtureNumber < $1.fixtureNumber }
    }

    func resolved(at shelf: IndoorShelfLabel) -> BookNavigationStop {
        .init(book: book, holdings: holdings, shelf: shelf, candidateShelves: candidateShelves)
    }
}
