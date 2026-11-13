import Foundation

nonisolated struct BookLocationStatus: Equatable, Sendable {
    let location: String?
    let availability: BookCardLibraryInfo.Availability?
}
