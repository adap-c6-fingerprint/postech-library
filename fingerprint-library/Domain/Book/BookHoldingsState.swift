import Foundation

nonisolated enum BookHoldingsState: Equatable, Sendable {
    case idle
    case loading
    case loaded([BookHolding])
    case failed(String)
}
