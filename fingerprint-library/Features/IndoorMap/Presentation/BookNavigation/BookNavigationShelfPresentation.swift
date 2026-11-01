import Foundation

extension BookNavigationBookInfo {
    var shelfText: String {
        let names = candidateShelves.map { "\($0.realNumber)-\($0.side.rawValue)" }.joined(separator: " · ")
        return candidateShelves.count > 1 ? "후보 서가: \(names)" : "서가 \(names)"
    }
}
