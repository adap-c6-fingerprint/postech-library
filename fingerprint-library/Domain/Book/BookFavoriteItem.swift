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

extension Array where Element == BookFavoriteItem {
    // 찜 키에 남아 있는 책의 기록만 저장 순서대로 돌려준다. 키가 찜 여부의 기준이다.
    nonisolated func active(in keys: Set<[String?]>) -> [BookFavoriteItem] {
        filter { keys.contains($0.book.recordKey) }
    }

    // 새로 찜한 책의 정보와 시각을 기록한다. 같은 책(recordKey 기준)의 이전 기록은 바꾼다.
    nonisolated mutating func record(_ book: Book, at date: Date) {
        removeAll { $0.book.recordKey == book.recordKey }
        append(BookFavoriteItem(book: book, favoritedAt: date))
    }

    // 예전에 기기 안 파일 주소로 저장한 표지를 새로 찾은 원격 주소로 바꾼다.
    nonisolated mutating func repairLegacyCover(of id: Book.ID, from oldURL: URL, to newURL: URL) {
        guard oldURL.isFileURL, !newURL.isFileURL,
              let index = firstIndex(where: { $0.id == id && $0.book.imageURL == oldURL }) else { return }
        self[index] = BookFavoriteItem(
            book: self[index].book.replacingImageURL(newURL), favoritedAt: self[index].favoritedAt
        )
    }
}
