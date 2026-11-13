import Foundation

nonisolated struct BookDescription: Equatable, Sendable {
    let text: String
    let sourceURL: URL
}
