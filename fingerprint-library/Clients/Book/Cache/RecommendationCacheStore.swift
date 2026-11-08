import CryptoKit
import Foundation
import ImageIO

/// 저장 형식은 Client 내부에 두어 팀이 공유하는 Book 계약은 바꾸지 않는다.
nonisolated struct CachedRecommendations: Sendable {
    let books: [Book]
    let savedAt: Date
    let coverFiles: [Book.ID: URL]
}

/// 마지막 정상 목록과 해당 표지를 함께 보존한다. 모든 디스크 작업은 이 actor에서 수행한다.
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

    /// 접속이 바뀌어도 열린 상세 화면이 참조하는 로컬 표지는 정리하지 않는다.
    func retainDisplayedCovers(_ files: [URL]) {
        retainedDisplayFiles = Set(files.filter {
            $0.isFileURL && $0.deletingLastPathComponent().standardizedFileURL == imagesDirectory.standardizedFileURL
        }.map(\.lastPathComponent))
    }

    /// 목록은 복원하고 읽을 수 있는 표지 파일만 표시용으로 넘긴다.
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

    /// 같은 표지 URL의 정상 파일은 다음 추천을 준비할 때 다시 다운로드하지 않는다.
    func coverData(for remoteURL: URL) throws -> Data? {
        let file = imagesDirectory.appendingPathComponent(try coverName(for: remoteURL))
        guard let data = try? Data(contentsOf: file),
              (try? Self.validateImage(data)) != nil else { return nil }
        return data
    }

    /// 파일 준비 → 마지막에 목록을 atomic 교체한다. 실패하면 이전 목록과 표지는 유지한다.
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

        // 지금 표시 중인 A와 다음 접속용 B가 참조하는 표지는 모두 보존한다.
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
