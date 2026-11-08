import Foundation
import ComposableArchitecture

nonisolated struct BookFavoritesClient: Sendable {
    var load: @Sendable () -> Set<[String?]>
    var save: @Sendable (Set<[String?]>) -> Void
    var loadItems: @Sendable () -> [BookFavoriteItem] = { [] }
    // 찜 목록 화면에 보여 줄 책 정보와 찜한 시각. 현재 찜 키에 있는 책만 돌려준다.
    var record: @Sendable (Book, Date) -> Void = { _, _ in }
    // 새로 찜한 책의 정보와 시각을 recordKey 기준으로 기록한다.
    var repairLegacyCover: @Sendable (Book.ID, URL, URL) -> Void = { _, _, _ in }

    private static let storageKey = "favoriteBookRecordKeys"
    private static let itemsStorageKey = "favoriteBookItems"

    static func userDefaults(suiteName: String? = nil) -> Self {
        let defaults: @Sendable () -> UserDefaults = {
            suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        }
        let loadKeys: @Sendable () -> Set<[String?]> = {
            guard let data = defaults().data(forKey: storageKey) else { return [] }
            return (try? JSONDecoder().decode(Set<[String?]>.self, from: data)) ?? []
        }
        let loadStoredItems: @Sendable () -> [StoredItem] = {
            guard let data = defaults().data(forKey: itemsStorageKey) else { return [] }
            return (try? JSONDecoder().decode([StoredItem].self, from: data)) ?? []
        }
        let saveStoredItems: @Sendable ([StoredItem]) -> Void = { items in
            guard let data = try? JSONEncoder().encode(items) else { return }
            defaults().set(data, forKey: itemsStorageKey)
        }

        return Self(
            load: loadKeys,
            save: { keys in
                guard let data = try? JSONEncoder().encode(keys) else { return }
                defaults().set(data, forKey: storageKey)
                let items = loadStoredItems()
                let kept = items.filter { keys.contains($0.key) }
                if kept.count != items.count { saveStoredItems(kept) }
                // 찜 해제된 책의 정보는 함께 지운다.
            },
            loadItems: {
                let keys = loadKeys()
                return loadStoredItems().filter { keys.contains($0.key) }.map(\.item)
            },
            record: { book, date in
                var items = loadStoredItems()
                items.removeAll { $0.key == book.recordKey }
                items.append(StoredItem(book: book, favoritedAt: date))
                saveStoredItems(items)
            },
            repairLegacyCover: { id, oldURL, newURL in
                guard oldURL.isFileURL, !newURL.isFileURL else { return }
                var items = loadStoredItems()
                guard let index = items.firstIndex(where: { $0.id == id && $0.imageURL == oldURL }),
                      loadKeys().contains(items[index].key) else { return }
                items[index].imageURL = newURL
                saveStoredItems(items)
            }
        )
    }

    /// 저장 형식은 Client 내부에 두어 팀이 공유하는 Book 계약은 바꾸지 않는다.
    private struct StoredItem: Codable {
        let id: String
        let isbn: String?
        let controlNumber: String?
        let title: String
        let author: String
        let publisher: String?
        let publicationYear: String?
        let description: String?
        var imageURL: URL?
        let favoritedAt: Date

        init(book: Book, favoritedAt: Date) {
            id = book.id; isbn = book.isbn; controlNumber = book.controlNumber
            title = book.title; author = book.author; publisher = book.publisher
            publicationYear = book.publicationYear; description = book.description
            imageURL = book.imageURL; self.favoritedAt = favoritedAt
        }

        var book: Book {
            Book(
                id: id, isbn: isbn, controlNumber: controlNumber, title: title,
                author: author, publisher: publisher, publicationYear: publicationYear,
                description: description, imageURL: imageURL
            )
        }

        var key: [String?] { book.recordKey }

        var item: BookFavoriteItem {
            BookFavoriteItem(book: book, favoritedAt: favoritedAt)
        }
    }
}

extension BookFavoritesClient: DependencyKey {
    static let liveValue = Self.userDefaults()
    static let testValue = Self(load: { [] }, save: { _ in })
}

extension DependencyValues {
    var bookFavoritesClient: BookFavoritesClient {
        get { self[BookFavoritesClient.self] }
        set { self[BookFavoritesClient.self] = newValue }
    }
}
