//
//  BookCartItem.swift
//  fingerprint-library
//

import Foundation

// 책바구니에 보관한 책과 보관한 시각
nonisolated struct BookCartItem: Equatable, Identifiable, Sendable {
    let book: Book
    let addedAt: Date

    var id: Book.ID { book.id }

    // 한 번에 길안내할 수 있는 최대 권수
    nonisolated static let maxGuidanceCount = 3

    // 책바구니에 보관할 수 있는 최대 권수
    nonisolated static let maxStoredCount = 30
}

// 같은 날 보관한 책 묶음
nonisolated struct BookCartSection: Equatable, Identifiable, Sendable {
    let day: Date
    let items: [BookCartItem]

    var id: Date { day }

    // 최근에 보관한 날짜와 책이 먼저 오도록 묶는다.
    static func grouped(_ items: [BookCartItem], calendar: Calendar) -> [Self] {
        let sorted = items.sorted { $0.addedAt > $1.addedAt }
        var sections: [Self] = []
        for item in sorted {
            let day = calendar.startOfDay(for: item.addedAt)
            if let last = sections.last, last.day == day {
                sections[sections.count - 1] = Self(day: day, items: last.items + [item])
            } else {
                sections.append(Self(day: day, items: [item]))
            }
        }
        return sections
    }
}

// 책바구니에 책을 담은 결과
nonisolated enum BookCartAddResult: Equatable, Sendable {
    case added
    case alreadyAdded
    case limitExceeded
}

extension Array where Element == BookCartItem {
    // 같은 책이 없고 보관 한도가 남아 있을 때만 담은 시각과 함께 추가한다.
    @discardableResult
    nonisolated mutating func add(_ book: Book, at date: Date) -> BookCartAddResult {
        guard !contains(where: { $0.book.recordKey == book.recordKey }) else { return .alreadyAdded }
        guard count < BookCartItem.maxStoredCount else { return .limitExceeded }
        append(BookCartItem(book: book, addedAt: date))
        return .added
    }

    // 같은 책(recordKey 기준)을 모두 뺀다. 실제로 뺀 권수를 돌려준다.
    @discardableResult
    nonisolated mutating func remove(recordKeys: Set<[String?]>) -> Int {
        let before = count
        removeAll { recordKeys.contains($0.book.recordKey) }
        return before - count
    }

    // 예전에 기기 안 파일 주소로 저장한 표지를 새로 찾은 원격 주소로 바꾼다.
    nonisolated mutating func repairLegacyCover(of id: Book.ID, from oldURL: URL, to newURL: URL) {
        guard oldURL.isFileURL, !newURL.isFileURL,
              let index = firstIndex(where: { $0.id == id && $0.book.imageURL == oldURL }) else { return }
        self[index] = BookCartItem(book: self[index].book.replacingImageURL(newURL), addedAt: self[index].addedAt)
    }
}
