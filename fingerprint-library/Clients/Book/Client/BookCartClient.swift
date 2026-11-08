import Foundation
import ComposableArchitecture

nonisolated struct BookCartClient: Sendable {
    var load: @Sendable () -> [BookCartItem]
    var save: @Sendable ([BookCartItem]) -> Void
    var repairLegacyCover: @Sendable (Book.ID, URL, URL) -> Void = { _, _, _ in }

    private static let storageKey = "bookCartItems"

    // 테스트에서는 별도 suite를 사용해 앱의 실제 장바구니와 분리한다.
    static func userDefaults(suiteName: String? = nil) -> Self {
        let defaults: @Sendable () -> UserDefaults = {
            suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        }
        let loadStoredItems: @Sendable () -> [StoredItem] = {
            guard let data = defaults().data(forKey: storageKey) else { return [] }
            return (try? JSONDecoder().decode([StoredItem].self, from: data)) ?? []
        }
        let saveStoredItems: @Sendable ([StoredItem]) -> Void = { items in
            guard let data = try? JSONEncoder().encode(items) else { return }
            defaults().set(data, forKey: storageKey)
        }
        return Self(
            load: { loadStoredItems().map(\.item) },
            save: { saveStoredItems($0.map(StoredItem.init)) },
            repairLegacyCover: { id, oldURL, newURL in
                guard oldURL.isFileURL, !newURL.isFileURL else { return }
                var items = loadStoredItems()
                guard let index = items.firstIndex(where: { $0.id == id && $0.imageURL == oldURL }) else { return }
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
        let addedAt: Date

        init(_ item: BookCartItem) {
            let book = item.book
            id = book.id; isbn = book.isbn; controlNumber = book.controlNumber
            title = book.title; author = book.author; publisher = book.publisher
            publicationYear = book.publicationYear; description = book.description
            imageURL = book.imageURL; addedAt = item.addedAt
        }

        var item: BookCartItem {
            BookCartItem(
                book: Book(
                    id: id, isbn: isbn, controlNumber: controlNumber, title: title,
                    author: author, publisher: publisher, publicationYear: publicationYear,
                    description: description, imageURL: imageURL
                ),
                addedAt: addedAt
            )
        }
    }

    enum AddResult: Equatable, Sendable {
        case added
        case alreadyAdded
        case limitExceeded
    }

    // 같은 책이 없고 보관 한도가 남아 있을 때만 담은 시각과 함께 저장한다.
    @discardableResult
    func add(_ book: Book, at date: Date) -> AddResult {
        var items = load()
        guard !items.contains(where: { $0.book.recordKey == book.recordKey }) else { return .alreadyAdded }
        guard items.count < BookCartItem.maxStoredCount else { return .limitExceeded }
        items.append(BookCartItem(book: book, addedAt: date))
        save(items)
        return .added
    }
}

extension BookCartClient: DependencyKey {
    static let liveValue = Self.userDefaults()
    static let testValue = Self(load: { [] }, save: { _ in })
}

extension DependencyValues {
    var bookCartClient: BookCartClient {
        get { self[BookCartClient.self] }
        set { self[BookCartClient.self] = newValue }
    }
}
