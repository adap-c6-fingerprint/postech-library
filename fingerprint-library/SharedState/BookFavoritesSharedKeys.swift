//
//  BookFavoritesSharedKeys.swift
//  fingerprint-library
//
//  찜은 두 값으로 저장한다. 이전 BookFavoritesClient가 쓰던 UserDefaults 키를 그대로 써서
//  기존 사용자의 찜을 옮기지 않고 읽는다.
//  - favoriteBookKeys: 찜 여부의 기준. 책의 recordKey 집합이다.
//  - favoriteBookRecords: 찜 목록 화면에 보여 줄 책 정보와 찜한 시각. 키에 없는 기록은 보이지 않는다.
//

import ComposableArchitecture
import Foundation

extension SharedKey where Self == AppStorageKey<Set<[String?]>>.Default {
    nonisolated static var favoriteBookKeys: Self {
        Self[.appStorage("favoriteBookRecordKeys"), default: []]
    }
}

extension SharedKey where Self == AppStorageKey<[BookFavoriteItem]>.Default {
    nonisolated static var favoriteBookRecords: Self {
        Self[.appStorage("favoriteBookItems"), default: []]
    }
}

struct BookFavorites {
    @Shared(.favoriteBookKeys) var keys
    @Shared(.favoriteBookRecords) var records

    init() {}

    var items: [BookFavoriteItem] { records.active(in: keys) }

    func contains(_ book: Book) -> Bool { keys.contains(book.recordKey) }

    @discardableResult
    func toggle(_ book: Book, at date: Date) -> Bool {
        let key = book.recordKey
        let isFavorite = $keys.withLock { keys in
            if keys.remove(key) == nil {
                keys.insert(key)
                return true
            }
            return false
        }
        $records.withLock { records in
            if isFavorite {
                records.record(book, at: date)
            } else {
                records.removeAll { $0.book.recordKey == key }
            }
        }
        return isFavorite
    }

    @discardableResult
    func remove(_ removedKeys: Set<[String?]>) -> Int {
        let removedCount = $keys.withLock { keys in
            let count = keys.intersection(removedKeys).count
            keys.subtract(removedKeys)
            return count
        }
        $records.withLock { $0.removeAll { removedKeys.contains($0.book.recordKey) } }
        return removedCount
    }

    func repairLegacyCover(of id: Book.ID, from oldURL: URL, to newURL: URL) {
        $records.withLock { $0.repairLegacyCover(of: id, from: oldURL, to: newURL) }
    }
}
