import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct DemoFixtureTests {
    private func request(_ string: String, token: String? = nil) -> URLRequest {
        var request = URLRequest(url: URL(string: string)!)
        if let token { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        return request
    }

    @Test func 개발_운영_중계_호스트와_쿼리_순서가_달라도_같은_키다() {
        let development = DemoFixtureKey.make(for: request("https://pobook-api-dev.fpmaps.com/primo/v1/search?q=a&lang=ko"))
        let production = DemoFixtureKey.make(for: request("https://pobook-api.fpmaps.com/primo/v1/search?lang=ko&q=a", token: "secret"))
        #expect(development == production)
        #expect(development == "GET relay/primo/v1/search?lang=ko&q=a")
        #expect(DemoFixtureKey.make(for: request("https://image.yes24.com/goods/1/XL")) == "GET image.yes24.com/goods/1/XL?")
    }

    @Test func 녹화한_응답만_재생하고_없으면_시연용_오류를_낸다() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let key = "GET relay/yes24/v1/goods/itemDetail?query=1&searchType=ISBN13"
        let file = DemoFixtureKey.fileName(for: key)
        try Data("{}".utf8).write(to: directory.appending(path: file))
        let manifest = DemoFixtureManifest(entries: [key: .init(statusCode: 200, contentType: "application/json", file: file)])
        try JSONEncoder().encode(manifest).write(to: directory.appending(path: DemoFixtureManifest.fileName))
        let client = HTTPClient.demoReplay(DemoFixtureStore(directory: directory))

        let hit = try await client.send(request("https://pobook-api.fpmaps.com/yes24/v1/goods/itemDetail?searchType=ISBN13&query=1"))
        #expect(hit.data == Data("{}".utf8))
        #expect(hit.response.statusCode == 200)
        await #expect(throws: DemoFixtureMissError.self) {
            try await client.send(request("https://pobook-api.fpmaps.com/yes24/v1/goods/itemDetail?query=2"))
        }
    }

    @Test func 데모_검색은_녹화가_없으면_번들_데이터셋에서_찾는다() async throws {
        let catalog = DemoCatalog(entries: [
            ("alma1", makeDemoBook(id: "1", title: "UI 디자인 입문"), [], []),
            ("alma2", makeDemoBook(id: "2", title: "A Guide to Building"), [], []),
            ("alma3", makeDemoBook(id: "3", title: "스티브 잡스", type: "Journal"), [], [])
        ])
        let recorded = BookClient(search: { _ in throw DemoFixtureMissError() })
        let client = BookClient.demoFallback(recorded: recorded, catalog: { catalog })

        #expect(try await client.search(.init(query: "ui", category: .all)).map(\.id) == ["1"])
        #expect(try await client.search(.init(query: "디자인", category: .all)).map(\.id) == ["1"])
        #expect(try await client.search(.init(query: "잡스", category: .monograph)).isEmpty)
        #expect(try await client.search(.init(query: "잡스", category: .journal)).map(\.id) == ["3"])
    }

    @Test func 녹화한_검색_결과가_있으면_데이터셋보다_우선한다() async throws {
        let recordedBook = makeDemoBook(id: "recorded", title: "UI")
        let client = BookClient.demoFallback(
            recorded: BookClient(search: { _ in [recordedBook] }),
            catalog: { Issue.record("녹화가 있으면 데이터셋을 읽지 않는다"); return DemoCatalog(entries: []) }
        )
        #expect(try await client.search(.init(query: "UI", category: .all)) == [recordedBook])
    }

    @Test func 녹화한_소장_정보가_없으면_데이터셋_청구기호를_대출_상태_없이_쓴다() async throws {
        let holding = BookHolding(
            holdingID: "h", institutionCode: nil, libraryCode: "MAIN", locationCode: "c3b",
            locationName: "단행본3층", callNumber: "QA76 .A1", availability: nil
        )
        let catalog = DemoCatalog(entries: [("alma1", makeDemoBook(id: "1", title: "책"), [holding], [])])
        let client = BookHoldingsClient.demoFallback(
            recorded: BookHoldingsClient(fetch: { _ in throw DemoFixtureMissError() }), catalog: { catalog }
        )

        let holdings = try await client.fetch("alma1")
        #expect(holdings == [holding])
        #expect(holdings.first?.availabilityText == "대출 상태 확인 필요")
        await #expect(throws: DemoFixtureMissError.self) { try await client.fetch("alma9") }
    }

    @Test func 번들_추천_데이터셋을_데모_카탈로그로_읽는다() async throws {
        let catalog = try await DemoCatalogLoader(bundle: .main).load()
        #expect(catalog.entries.count > 0)
        #expect(catalog.entries.contains { !$0.holdings.isEmpty && $0.holdings.allSatisfy { $0.availability == nil } })
    }

    private func makeDemoBook(id: String, title: String, type: String = "Printed_Book") -> Book {
        var book = Book(
            id: id, isbn: nil, controlNumber: nil, title: title, author: "저자", publisher: nil,
            publicationYear: nil, description: nil, imageURL: nil
        )
        book.resourceTypes = [type]
        return book
    }
}
