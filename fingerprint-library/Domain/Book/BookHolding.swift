import Foundation

nonisolated struct BookHolding: Codable, Equatable, Identifiable, Sendable {
    let holdingID: String?
    let institutionCode: String?
    let libraryCode: String?
    let locationCode: String?
    let locationName: String?
    let callNumber: String?
    let availability: String?

    var id: String {
        [institutionCode, libraryCode, locationCode, locationName, callNumber, holdingID]
            .map { $0 ?? "" }.joined(separator: "\u{1F}")
    }

    var availabilityText: String {
        switch availability {
        case "available": "대출 가능"
        case "unavailable": "대출 중 또는 이용 불가"
        default: "대출 상태 확인 필요"
        }
    }
}
