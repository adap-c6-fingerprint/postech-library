import Foundation

extension BookNavigationBookInfo {
    var shelfText: String {
        let names = candidateShelves.map { $0.faceTitle }.joined(separator: " · ")
        return candidateShelves.count > 1 ? "후보 서가: \(names)" : (candidateShelves.first?.isNamedShelf == true ? names : "서가 \(names)")
    }
}
