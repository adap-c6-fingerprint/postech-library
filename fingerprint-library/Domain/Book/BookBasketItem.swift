//
//  BookBasketItem.swift
//  fingerprint-library
//

import Foundation

// 장바구니에 보관한 책과 보관한 시각
struct BookBasketItem: Equatable, Identifiable, Sendable {
    let book: Book
    let addedAt: Date

    var id: Book.ID { book.id }
}

// 같은 날 보관한 책 묶음
struct BookBasketSection: Equatable, Identifiable, Sendable {
    let day: Date
    let items: [BookBasketItem]

    var id: Date { day }

    // 최근에 보관한 날짜와 책이 먼저 오도록 묶는다.
    static func grouped(_ items: [BookBasketItem], calendar: Calendar) -> [Self] {
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
