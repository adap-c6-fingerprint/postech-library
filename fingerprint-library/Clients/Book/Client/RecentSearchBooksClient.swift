import ComposableArchitecture
import Foundation

nonisolated struct RecentSearchBooksClient: Sendable {
    var load: @Sendable () -> [Book]
    var record: @Sendable (Book) -> Void
    var remove: @Sendable (Book) -> Void

    static let maxCount = 5
    private static let storageKey = "recentSearchBooks"

    static func userDefaults(suiteName: String? = nil) -> Self {
        @Sendable func defaults() -> UserDefaults {
            suiteName.flatMap(UserDefaults.init(suiteName:)) ?? .standard
        }
        @Sendable func read() -> [Book] {
            guard let data = defaults().data(forKey: storageKey),
                  let stored = try? JSONDecoder().decode([StoredBook].self, from: data)
            else { return [] }
            return stored.prefix(maxCount).map(\.book)
        }
        @Sendable func write(_ books: [Book]) {
            let stored = books.prefix(maxCount).map(StoredBook.init)
            guard let data = try? JSONEncoder().encode(stored) else { return }
            defaults().set(data, forKey: storageKey)
        }
        return Self(
            load: { read() },
            record: { book in
                write([book] + read().filter { $0.recordKey != book.recordKey && $0.id != book.id })
            },
            remove: { book in
                write(read().filter { $0.recordKey != book.recordKey && $0.id != book.id })
            }
        )
    }

    private nonisolated struct StoredBook: Codable, Sendable {
        let id: String
        let isbn: String?
        let controlNumber: String?
        let title: String
        let author: String
        let publisher: String?
        let publicationYear: String?
        let description: String?
        let imageURL: URL?
        let subLocation: String?

        init(_ book: Book) {
            id = book.id
            isbn = book.isbn
            controlNumber = book.controlNumber
            title = book.title
            author = book.author
            publisher = book.publisher
            publicationYear = book.publicationYear
            description = book.description
            imageURL = book.imageURL
            subLocation = book.subLocation
        }

        var book: Book {
            Book(id: id, isbn: isbn, controlNumber: controlNumber, title: title, author: author,
                 publisher: publisher, publicationYear: publicationYear, description: description,
                 imageURL: imageURL, subLocation: subLocation)
        }
    }
}

extension RecentSearchBooksClient: DependencyKey {
    static let liveValue = Self.userDefaults()
    static let testValue = Self(load: { [] }, record: { _ in }, remove: { _ in })
}

nonisolated extension DependencyValues {
    var recentSearchBooksClient: RecentSearchBooksClient {
        get { self[RecentSearchBooksClient.self] }
        set { self[RecentSearchBooksClient.self] = newValue }
    }
}
