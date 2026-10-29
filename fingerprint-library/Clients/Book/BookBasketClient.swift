import Foundation
import ComposableArchitecture

nonisolated struct BookBasketClient: Sendable {
    var load: @Sendable () -> [BookBasketItem]
    var save: @Sendable ([BookBasketItem]) -> Void

    // 테스트에서는 별도 suite를 사용해 앱의 실제 장바구니와 분리한다.
    static func userDefaults(suiteName: String? = nil) -> Self {
        Self(
            load: {
                let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
                guard let data = defaults.data(forKey: BookStorageKey.basketItems) else { return [] }
                let records = (try? JSONDecoder().decode([StoredItem].self, from: data)) ?? []
                return records.map(\.item)
            },
            save: { items in
                guard let data = try? JSONEncoder().encode(items.map(StoredItem.init)) else { return }
                let defaults = suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
                defaults.set(data, forKey: BookStorageKey.basketItems)
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
        let imageURL: URL?
        let addedAt: Date

        init(_ item: BookBasketItem) {
            let book = item.book
            id = book.id; isbn = book.isbn; controlNumber = book.controlNumber
            title = book.title; author = book.author; publisher = book.publisher
            publicationYear = book.publicationYear; description = book.description
            imageURL = book.imageURL; addedAt = item.addedAt
        }

        var item: BookBasketItem {
            BookBasketItem(
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
        guard items.count < BookBasketItem.maxStoredCount else { return .limitExceeded }
        items.append(BookBasketItem(book: book, addedAt: date))
        save(items)
        return .added
    }
}

extension BookBasketClient: DependencyKey {
    static let liveValue = Self.userDefaults()
    static let testValue = Self(load: { [] }, save: { _ in })
}

extension DependencyValues {
    var bookBasketClient: BookBasketClient {
        get { self[BookBasketClient.self] }
        set { self[BookBasketClient.self] = newValue }
    }
}
