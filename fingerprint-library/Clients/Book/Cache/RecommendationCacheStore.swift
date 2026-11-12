import CryptoKit
import Foundation
import ImageIO

nonisolated struct CachedRecommendations: Sendable {
    let books: [Book]
    let savedAt: Date
    let coverFiles: [Book.ID: URL]
}

actor RecommendationCacheStore {
    nonisolated struct PreparedCover: Sendable {
        let sourceURL: URL
        let data: Data
    }

    enum CacheError: Error {
        case invalidSnapshot
        case invalidImage
    }

    private let directory: URL
    private var displayedFiles: Set<String> = []
    private var retainedDisplayFiles: Set<String> = []
    private var preparationID: UUID?
    private var manifestURL: URL { directory.appendingPathComponent("recommendations.json") }
    private var imagesDirectory: URL { directory.appendingPathComponent("covers", isDirectory: true) }

    init(directory: URL) {
        self.directory = directory
    }

    func beginPreparation() -> UUID {
        let id = UUID()
        preparationID = id
        return id
    }

    func retainDisplayedCovers(_ files: [URL]) {
        retainedDisplayFiles = Set(files.filter {
            $0.isFileURL && $0.deletingLastPathComponent().standardizedFileURL == imagesDirectory.standardizedFileURL
        }.map(\.lastPathComponent))
    }

    func restore() throws -> CachedRecommendations? {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return nil }
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: manifestURL))
        guard [1, 2, 3].contains(manifest.version), !manifest.books.isEmpty,
              manifest.books.count <= 6,
              Set(manifest.books.map(\.id)).count == manifest.books.count else {
            throw CacheError.invalidSnapshot
        }
        var files: [Book.ID: URL] = [:]
        for book in manifest.books {
            let sourceURL = manifest.version == 3 ? book.coverSourceURL : book.imageURL
            guard let fileName = book.coverFile else {
                if manifest.version == 3 {
                    guard sourceURL == nil else { throw CacheError.invalidSnapshot }
                } else {
                    guard sourceURL == nil || (manifest.version == 2 && book.coverUnavailable == true) else {
                        throw CacheError.invalidSnapshot
                    }
                }
                continue
            }
            guard let sourceURL, fileName == (try coverName(for: sourceURL)),
                  book.coverUnavailable != true else { throw CacheError.invalidSnapshot }
            let file = imagesDirectory.appendingPathComponent(fileName)
            guard let data = try? Data(contentsOf: file),
                  (try? Self.validateImage(data)) != nil else { continue }
            files[book.id] = file
        }
        displayedFiles = Set(files.values.map(\.lastPathComponent)).union(retainedDisplayFiles)
        return CachedRecommendations(
            books: manifest.books.map(\.book), savedAt: manifest.savedAt, coverFiles: files
        )
    }

    func coverData(for remoteURL: URL) throws -> Data? {
        let file = imagesDirectory.appendingPathComponent(try coverName(for: remoteURL))
        guard let data = try? Data(contentsOf: file),
              (try? Self.validateImage(data)) != nil else { return nil }
        return data
    }

    func save(
        books: [Book], covers: [Book.ID: PreparedCover], savedAt: Date,
        preparationID expectedID: UUID? = nil
    ) throws -> CachedRecommendations {
        try Task.checkCancellation()
        if let expectedID, preparationID != expectedID { throw CancellationError() }
        guard !books.isEmpty, books.count <= 6,
              Set(books.map(\.id)).count == books.count else { throw CacheError.invalidSnapshot }
        var records: [StoredBook] = []
        var files: [Book.ID: URL] = [:]
        var imagesToWrite: [URL: Data] = [:]
        for book in books {
            guard let cover = covers[book.id] else {
                records.append(StoredBook(book))
                continue
            }
            let name = try coverName(for: cover.sourceURL)
            try Self.validateImage(cover.data)
            let file = imagesDirectory.appendingPathComponent(name)
            files[book.id] = file
            imagesToWrite[file] = cover.data
            records.append(StoredBook(book, coverFile: name, coverSourceURL: cover.sourceURL))
        }

        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        var root = directory
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try root.setResourceValues(values)
        for (file, data) in imagesToWrite {
            try Task.checkCancellation()
            if (try? Data(contentsOf: file)) != data {
                try data.write(to: file, options: .atomic)
            }
        }
        try Task.checkCancellation()
        let manifest = Manifest(version: 3, savedAt: savedAt, books: records)
        let data = try JSONEncoder().encode(manifest)
        try data.write(to: manifestURL, options: .atomic)

        let retained = displayedFiles.union(retainedDisplayFiles).union(files.values.map(\.lastPathComponent))
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: imagesDirectory, includingPropertiesForKeys: nil
        ) {
            for file in contents where !retained.contains(file.lastPathComponent) {
                try? FileManager.default.removeItem(at: file)
            }
        }
        return CachedRecommendations(books: books, savedAt: savedAt, coverFiles: files)
    }

    private func coverName(for url: URL) throws -> String {
        guard ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              url.host?.isEmpty == false else { throw CacheError.invalidSnapshot }
        return SHA256.hash(data: Data(url.absoluteString.utf8))
            .map { String(format: "%02x", $0) }.joined() + ".image"
    }

    nonisolated static func validateImage(_ data: Data) throws {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceCreateImageAtIndex(source, 0, nil) != nil else {
            throw CacheError.invalidImage
        }
    }

    private struct Manifest: Codable {
        let version: Int
        let savedAt: Date
        let books: [StoredBook]
    }

    private struct StoredBook: Codable {
        let id: String
        let isbn: String?
        let controlNumber: String?
        let title: String
        let author: String
        let publisher: String?
        let publicationYear: String?
        let description: String?
        let imageURL: URL?
        let coverFile: String?
        let coverSourceURL: URL?
        let coverUnavailable: Bool?

        init(_ book: Book, coverFile: String? = nil, coverSourceURL: URL? = nil) {
            id = book.id; isbn = book.isbn; controlNumber = book.controlNumber
            title = book.title; author = book.author; publisher = book.publisher
            publicationYear = book.publicationYear; description = book.description
            imageURL = book.imageURL; self.coverFile = coverFile
            self.coverSourceURL = coverSourceURL
            coverUnavailable = nil
        }

        var book: Book {
            Book(
                id: id, isbn: isbn, controlNumber: controlNumber, title: title,
                author: author, publisher: publisher, publicationYear: publicationYear,
                description: description, imageURL: imageURL
            )
        }
    }
}
