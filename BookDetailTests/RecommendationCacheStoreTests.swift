import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct RecommendationCacheStoreTests {
    @Test("이전 버전의 미제공 표식 없는 저장본도 읽는다")
    func restoresLegacyManifest() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = RecommendationCacheFixture.book("legacy")
        let store = RecommendationCacheStore(directory: directory)
        _ = try await store.save(books: [book], covers: [book.imageURL!: RecommendationCacheFixture.image], savedAt: .now)
        let manifest = directory.appendingPathComponent("recommendations.json")
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifest)) as? [String: Any])
        json["version"] = 1
        try JSONSerialization.data(withJSONObject: json).write(to: manifest)
        #expect(try await RecommendationCacheStore(directory: directory).restore()?.books == [book])
    }

    @Test("표지 파일과 미제공 표식을 동시에 저장하는 모순을 거부한다")
    func rejectsContradictoryUnavailableMarker() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = RecommendationCacheFixture.book("a")
        let store = RecommendationCacheStore(directory: directory)
        await #expect(throws: RecommendationCacheStore.CacheError.invalidSnapshot) {
            try await store.save(
                books: [book], covers: [book.imageURL!: RecommendationCacheFixture.image],
                savedAt: .now, unavailableCovers: [book.imageURL!]
            )
        }
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    @Test("새 저장소 인스턴스에서도 목록과 표지 파일을 복원한다")
    func persistsAcrossInstances() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let book = RecommendationCacheFixture.book("a")
        let savedAt = Date(timeIntervalSince1970: 123)
        let store = RecommendationCacheStore(directory: directory)
        #expect(try await store.restore() == nil)
        _ = try await store.save(books: [book], covers: [book.imageURL!: RecommendationCacheFixture.image], savedAt: savedAt)
        let restored = try #require(try await RecommendationCacheStore(directory: directory).restore())
        #expect(restored.books == [book])
        #expect(restored.savedAt == savedAt)
        let local = try #require(restored.displayBooks.first?.imageURL)
        #expect(local.isFileURL)
        #expect(try Data(contentsOf: local) == RecommendationCacheFixture.image)
    }

    @Test("일부 표지 누락이나 잘못된 이미지는 이전 정상 저장본을 덮어쓰지 않는다")
    func preservesLastGoodSnapshot() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecommendationCacheStore(directory: directory)
        let first = RecommendationCacheFixture.book("a"), next = RecommendationCacheFixture.book("b")
        _ = try await store.save(books: [first], covers: [first.imageURL!: RecommendationCacheFixture.image], savedAt: .distantPast)
        await #expect(throws: (any Error).self) {
            try await store.save(books: [next], covers: [:], savedAt: .now)
        }
        await #expect(throws: (any Error).self) {
            try await store.save(books: [next], covers: [next.imageURL!: Data("html".utf8)], savedAt: .now)
        }
        #expect(try await store.restore()?.books == [first])
    }

    @Test("표지가 없는 책은 책 아이콘으로 표시할 수 있는 정상 항목으로 저장한다")
    func acceptsUnavailableCover() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecommendationCacheStore(directory: directory)
        let book = RecommendationCacheFixture.book("no-cover", hasCover: false)
        _ = try await store.save(books: [book], covers: [:], savedAt: .now)
        #expect(try await store.restore()?.displayBooks == [book])
    }

    @Test("표지 파일 유실과 손상된 manifest를 정상 캐시로 반환하지 않는다")
    func rejectsIncompleteRestore() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecommendationCacheStore(directory: directory)
        let book = RecommendationCacheFixture.book("a")
        let saved = try await store.save(books: [book], covers: [book.imageURL!: RecommendationCacheFixture.image], savedAt: .now)
        try FileManager.default.removeItem(at: saved.coverFiles[book.imageURL!]!)
        await #expect(throws: (any Error).self) { try await store.restore() }
        try Data("broken".utf8).write(to: directory.appendingPathComponent("recommendations.json"))
        await #expect(throws: (any Error).self) { try await store.restore() }
    }

    @Test("표시 중인 A와 다음 B를 보존하고 다음 세션 갱신 후 참조 없는 표지를 정리한다")
    func retainsDisplayedAndNextAssets() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecommendationCacheStore(directory: directory)
        let a = RecommendationCacheFixture.book("a"), b = RecommendationCacheFixture.book("b"), c = RecommendationCacheFixture.book("c")
        let first = try await store.save(books: [a], covers: [a.imageURL!: RecommendationCacheFixture.image], savedAt: .now)
        _ = try await store.restore()
        _ = try await store.save(books: [b], covers: [b.imageURL!: RecommendationCacheFixture.image], savedAt: .now)
        #expect(FileManager.default.fileExists(atPath: first.coverFiles[a.imageURL!]!.path))
        _ = try await store.restore()
        _ = try await store.save(books: [c], covers: [c.imageURL!: RecommendationCacheFixture.image], savedAt: .now)
        #expect(!FileManager.default.fileExists(atPath: first.coverFiles[a.imageURL!]!.path))
    }

    @Test("다음 접속으로 넘어가도 열린 상세 화면의 표지 파일을 보존한다")
    func retainsOpenDetailCover() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecommendationCacheStore(directory: directory)
        let a = RecommendationCacheFixture.book("a"), b = RecommendationCacheFixture.book("b"), c = RecommendationCacheFixture.book("c")
        let first = try await store.save(books: [a], covers: [a.imageURL!: RecommendationCacheFixture.image], savedAt: .now)
        let detailCover = first.coverFiles[a.imageURL!]!
        _ = try await store.restore()
        _ = try await store.save(books: [b], covers: [b.imageURL!: RecommendationCacheFixture.image], savedAt: .now)
        await store.retainDisplayedCovers([detailCover])
        _ = try await store.restore()
        _ = try await store.save(books: [c], covers: [c.imageURL!: RecommendationCacheFixture.image], savedAt: .now)
        #expect(FileManager.default.fileExists(atPath: detailCover.path))
    }

    @Test("빈 목록과 중복 도서 결과는 정상 저장본을 교체하지 않는다")
    func rejectsEmptyAndDuplicateResults() async throws {
        let directory = directory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = RecommendationCacheStore(directory: directory)
        let a = RecommendationCacheFixture.book("a")
        _ = try await store.save(books: [a], covers: [a.imageURL!: RecommendationCacheFixture.image], savedAt: .now)
        await #expect(throws: (any Error).self) { try await store.save(books: [], covers: [:], savedAt: .now) }
        await #expect(throws: (any Error).self) { try await store.save(books: [a, a], covers: [a.imageURL!: RecommendationCacheFixture.image], savedAt: .now) }
        #expect(try await store.restore()?.books == [a])
    }
}

@MainActor
enum RecommendationCacheFixture {
    // 오프라인 테스트용 1×1 PNG. 실제 API나 비밀 값은 사용하지 않는다.
    nonisolated static let image = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScLttAAAAABJRU5ErkJggg==")!

    static func book(_ id: String, hasCover: Bool = true) -> Book {
        Book(
            id: id, isbn: "9788966260959", controlNumber: "primo:\(id)",
            title: id, author: "저자", publisher: "출판사", publicationYear: "2026",
            description: nil,
            imageURL: hasCover ? URL(string: "https://example.invalid/\(id).png")! : nil
        )
    }
}
