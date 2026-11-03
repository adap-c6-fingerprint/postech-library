//
//  BookFavoriteItem.swift
//  fingerprint-library
//

import Foundation

// 찜한 책과 찜한 시각
nonisolated struct BookFavoriteItem: Equatable, Identifiable, Sendable {
    let book: Book
    let favoritedAt: Date

    var id: Book.ID { book.id }
}

// 같은 날 찜한 책 묶음
nonisolated struct BookFavoriteSection: Equatable, Identifiable, Sendable {
    let day: Date
    let items: [BookFavoriteItem]

    var id: Date { day }

    // 최근에 찜한 날짜와 책이 먼저 오도록 묶는다.
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
