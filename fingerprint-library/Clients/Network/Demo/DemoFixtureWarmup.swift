//
//  DemoFixtureWarmup.swift
//  fingerprint-library
//
//  녹화 전용(Debug). `POBOOK_DEMO_RECORD_DIR`와 `POBOOK_DEMO_RECORD_QUERIES`(| 구분)를 함께 주고 실행하면
//  화면을 조작하지 않아도 검색 결과 화면·상세 화면이 보내는 요청(검색, 표지, 책등, 책 소개, 소장 정보)을
//  앱과 같은 Client로 보내 응답을 녹화한다.
//

#if DEBUG
import ComposableArchitecture
import Foundation
import OSLog

@MainActor
enum DemoFixtureWarmup {
    private static let logger = Logger(subsystem: "Fingerprint", category: "DemoFixtureWarmup")

    static func startIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard environment["POBOOK_DEMO_RECORD_DIR"]?.isEmpty == false else { return }
        let queries = (environment["POBOOK_DEMO_RECORD_QUERIES"] ?? "").split(separator: "|").map { String($0) }
        let includesDatasetCovers = environment["POBOOK_DEMO_RECORD_DATASET_COVERS"] == "1"
        let includesDatasetSpines = environment["POBOOK_DEMO_RECORD_DATASET_SPINES"] == "1"
        let includesDatasetDescriptions = environment["POBOOK_DEMO_RECORD_DATASET_DESCRIPTIONS"] == "1"
        guard !queries.isEmpty || includesDatasetCovers || includesDatasetSpines || includesDatasetDescriptions
                || environment["POBOOK_DEMO_RECORD_DESCRIPTION_ISBNS"]?.isEmpty == false
        else { return }
        Task {
            if includesDatasetCovers { await recordDatasetCovers() }
            if includesDatasetSpines { await recordDatasetSpines() }
            if includesDatasetDescriptions { await recordDatasetDescriptions() }
            if let isbns = environment["POBOOK_DEMO_RECORD_DESCRIPTION_ISBNS"], !isbns.isEmpty {
                await recordDescriptions(isbns: isbns.split(separator: "|").map(String.init))
            }
            if !queries.isEmpty { await run(queries: queries) }
            logger.notice("demo fixture warmup finished")
        }
    }

    /// 추천 탭은 번들 데이터셋의 책을 보여주므로, 데이터셋 책 표지를 모두 녹화한다.
    static func recordDatasetCovers() async {
        @Dependency(\.recommendationDatasetClient) var datasetClient
        guard let dataset = try? await datasetClient.load() else {
            logger.error("dataset load failed")
            return
        }
        for book in dataset.allBooks {
            await recordDetail(of: book)
        }
        logger.notice("recorded dataset books: \(dataset.bookCount) books")
    }

    /// 도착 화면의 책등만 다시 녹화한다. 이미 받은 책등은 기기 파일에서 읽으므로 빠진 것만 요청한다.
    static func recordDatasetSpines() async {
        @Dependency(\.recommendationDatasetClient) var datasetClient
        guard let dataset = try? await datasetClient.load() else {
            logger.error("dataset load failed")
            return
        }
        var failed = 0
        for book in dataset.allBooks where await !recordSpine(of: book) { failed += 1 }
        logger.notice("recorded dataset spines: \(dataset.bookCount) books, failed \(failed)")
    }

    /// 책 소개만 다시 녹화한다. Yes24 미등록(404) 응답도 저장해 데모에서 "정보 없음"으로 보이게 한다.
    static func recordDatasetDescriptions() async {
        @Dependency(\.recommendationDatasetClient) var datasetClient
        @Dependency(\.bookDetailClient) var bookDetailClient
        guard let dataset = try? await datasetClient.load() else {
            logger.error("dataset load failed")
            return
        }
        for book in dataset.allBooks {
            guard let isbn13 = BookISBN.isbn13(from: book.isbn) else { continue }
            _ = try? await bookDetailClient.fetchDescription(isbn13)
        }
        logger.notice("recorded dataset descriptions: \(dataset.bookCount) books")
    }

    /// 누락 검사에서 빠진 책 소개만 다시 받는다. 실패 사유를 로그로 남긴다.
    static func recordDescriptions(isbns: [String]) async {
        @Dependency(\.bookDetailClient) var bookDetailClient
        var failed = 0
        for isbn13 in isbns {
            do {
                _ = try await bookDetailClient.fetchDescription(isbn13)
            } catch {
                failed += 1
                logger.error("description failed: \(isbn13, privacy: .public) \(String(describing: error), privacy: .public)")
            }
        }
        logger.notice("recorded descriptions: \(isbns.count) books, failed \(failed)")
    }

    /// 이미지 서버가 일시적으로 실패하면 책등이 녹화되지 않으므로 몇 번 더 시도한다.
    @discardableResult
    private static func recordSpine(of book: Book) async -> Bool {
        guard let isbn = book.isbn, BookISBN.isbn13(from: isbn) != nil else { return true }
        for attempt in 0..<4 {
            do {
                _ = try await BookCoverPipeline.spineImage(isbn: isbn)
                return true
            } catch RecommendationCacheStore.CacheError.invalidImage {
                return true // Yes24에 책등이 없는 책
            } catch {
                try? await Task.sleep(for: .seconds(1 + attempt))
            }
        }
        logger.error("spine failed: \(isbn, privacy: .public)")
        return false
    }

    /// 상세 화면이 보내는 요청(표지, 책등, 책 소개, 소장·대출 상태)을 녹화한다.
    private static func recordDetail(of book: Book) async {
        @Dependency(\.bookDetailClient) var bookDetailClient
        @Dependency(\.bookHoldingsClient) var bookHoldingsClient
        await recordCover(of: book)
        await recordSpine(of: book)
        if let isbn13 = BookISBN.isbn13(from: book.isbn) { _ = try? await bookDetailClient.fetchDescription(isbn13) }
        if let recordID = BookHoldingsClient.recordID(for: book) {
            _ = try? await bookHoldingsClient.fetch(recordID)
        }
    }

    private static func recordCover(of book: Book) async {
        _ = try? await BookCoverSource.load(
            url: book.imageURL, isbn13: BookISBN.isbn13(from: book.isbn), cachedURL: nil,
            lookupYes24: { try await BookCoverPipeline.yes24Cover.url(for: $0) },
            lookupLegacyOriginal: nil
        ) { candidate in (try await BookCoverPipeline.shared.image(for: candidate), candidate) }
    }

    static func run(queries: [String]) async {
        @Dependency(\.bookClient) var bookClient
        for query in queries {
            let books: [Book]
            do {
                books = try await bookClient.search(BookSearchRequest(query: query, category: .all))
            } catch {
                logger.error("search failed: \(query, privacy: .public) \(error.localizedDescription, privacy: .public)")
                continue
            }
            for book in books {
                await recordDetail(of: book)
            }
            logger.notice("recorded \(query, privacy: .public): \(books.count) books")
        }
    }
}
#endif
