import Foundation

nonisolated enum BookHoldingsState: Equatable, Sendable {
    case idle
    case loading
    case loaded([BookHolding])
    case failed(String)

    var isUnavailableForGuidance: Bool {
        guard case let .loaded(holdings) = self else { return false }
        return BookCardLibraryInfo(holdings: holdings).primaryHolding?.isUnavailableForGuidance == true
    }
}
