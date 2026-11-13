//
//  BookFavoriteItem.swift
//  fingerprint-library
//

import Foundation

nonisolated struct BookFavoriteItem: Equatable, Identifiable, Sendable {
    let book: Book
    let favoritedAt: Date

    var id: Book.ID { book.id }
}

nonisolated struct BookFavoriteSection: Equatable, Identifiable, Sendable {
    let day: Date
    let items: [BookFavoriteItem]

    var id: Date { day }

    static func grouped(_ items: [BookFavoriteItem], calendar: Calendar) -> [Self] {
        let sorted = items.sorted { $0.favoritedAt > $1.favoritedAt }
        var sections: [Self] = []
        for item in sorted {
            let day = calendar.startOfDay(for: item.favoritedAt)
            if let last = sections.last, last.day == day {
                sections[sections.count - 1] = Self(day: day, items: last.items + [item])
            } else {
                sections.append(Self(day: day, items: [item]))
            }
        }
        return sections
    }
}

extension Array where Element == BookFavoriteItem {
    nonisolated func active(in keys: Set<[String?]>) -> [BookFavoriteItem] {
        filter { keys.contains($0.book.recordKey) }
    }

    nonisolated mutating func record(_ book: Book, at date: Date) {
        removeAll { $0.book.recordKey == book.recordKey }
        append(BookFavoriteItem(book: book, favoritedAt: date))
    }

    nonisolated mutating func repairLegacyCover(of id: Book.ID, from oldURL: URL, to newURL: URL) {
        guard oldURL.isFileURL, !newURL.isFileURL,
              let index = firstIndex(where: { $0.id == id && $0.book.imageURL == oldURL }) else { return }
        self[index] = BookFavoriteItem(
            book: self[index].book.replacingImageURL(newURL), favoritedAt: self[index].favoritedAt
        )
    }
}
