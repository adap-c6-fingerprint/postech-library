//
//  BookCartItem.swift
//  fingerprint-library
//

import Foundation

nonisolated struct BookCartItem: Equatable, Identifiable, Sendable {
    let book: Book
    let addedAt: Date

    var id: Book.ID { book.id }

    nonisolated static let maxStoredCount = 30
}

nonisolated struct BookCartSection: Equatable, Identifiable, Sendable {
    let day: Date
    let items: [BookCartItem]

    var id: Date { day }

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

nonisolated enum BookCartAddResult: Equatable, Sendable {
    case added
    case alreadyAdded
    case limitExceeded
}

extension Array where Element == BookCartItem {
    @discardableResult
    nonisolated mutating func add(_ book: Book, at date: Date) -> BookCartAddResult {
        guard !contains(where: { $0.book.recordKey == book.recordKey }) else { return .alreadyAdded }
        guard count < BookCartItem.maxStoredCount else { return .limitExceeded }
        append(BookCartItem(book: book, addedAt: date))
        return .added
    }

    @discardableResult
    nonisolated mutating func remove(recordKeys: Set<[String?]>) -> Int {
        let before = count
        removeAll { recordKeys.contains($0.book.recordKey) }
        return before - count
    }

    nonisolated mutating func repairLegacyCover(of id: Book.ID, from oldURL: URL, to newURL: URL) {
        guard oldURL.isFileURL, !newURL.isFileURL,
              let index = firstIndex(where: { $0.id == id && $0.book.imageURL == oldURL }) else { return }
        self[index] = BookCartItem(book: self[index].book.replacingImageURL(newURL), addedAt: self[index].addedAt)
    }
}
