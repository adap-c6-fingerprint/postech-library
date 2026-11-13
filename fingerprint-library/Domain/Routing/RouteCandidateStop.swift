import Foundation

struct RouteCandidateStop: Equatable, Sendable {
    let book: Book
    let holdings: [BookHolding]
    let candidateShelves: [IndoorShelfLabel]

    init(book: Book, holdings: [BookHolding], candidateShelves: [IndoorShelfLabel]) {
        self.book = book
        self.holdings = holdings
        self.candidateShelves = candidateShelves.sorted { $0.fixtureNumber < $1.fixtureNumber }
    }

    func resolved(at shelf: IndoorShelfLabel) -> RouteStop {
        .init(book: book, holdings: holdings, shelf: shelf, candidateShelves: candidateShelves)
    }
}
