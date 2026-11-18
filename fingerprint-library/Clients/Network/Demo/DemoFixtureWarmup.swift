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
        guard !queries.isEmpty || includesDatasetCovers else { return }
        Task {
            if includesDatasetCovers { await recordDatasetCovers() }
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
            await recordCover(of: book)
        }
        logger.notice("recorded dataset covers: \(dataset.bookCount) books")
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
        @Dependency(\.bookDetailClient) var bookDetailClient
        @Dependency(\.bookHoldingsClient) var bookHoldingsClient
        for query in queries {
            let books: [Book]
            do {
                books = try await bookClient.search(BookSearchRequest(query: query, category: .all))
            } catch {
                logger.error("search failed: \(query, privacy: .public) \(error.localizedDescription, privacy: .public)")
                continue
            }
            for book in books {
                let isbn13 = BookISBN.isbn13(from: book.isbn)
                await recordCover(of: book)
                if let isbn = book.isbn { _ = try? await BookCoverPipeline.spineImage(isbn: isbn) }
                if let isbn13 { _ = try? await bookDetailClient.fetchDescription(isbn13) }
                if let recordID = BookHoldingsClient.recordID(for: book) {
                    _ = try? await bookHoldingsClient.fetch(recordID)
                }
            }
            logger.notice("recorded \(query, privacy: .public): \(books.count) books")
        }
    }
}
#endif
