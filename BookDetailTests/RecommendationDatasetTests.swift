import Foundation
import Testing
@testable import fingerprint_library

// ✅ 이슈 #237: 앱 번들에 넣은 하드데이터의 구조만 검증한다.
// 표지 URL 값·파일 해시·권 수처럼 데이터 갱신 때 바뀔 수 있는 값은 고정하지 않는다.
@MainActor
struct RecommendationDatasetTests {
    private static func bundledDataset() async throws -> RecommendationDataset {
        let bundle = Bundle.allBundles.first {
            $0.url(forResource: RecommendationDatasetLoader.resourceName, withExtension: "json") != nil
        } ?? .main
        return try await RecommendationDatasetLoader(bundle: bundle).load()
    }

    @Test("소속 301개와 선호 분류 20개를 원본 순서대로 읽는다")
    func loadsAllOptions() async throws {
        let dataset = try await Self.bundledDataset()
        #expect(dataset.affiliationPaths.count == 301)
        #expect(dataset.preferenceNames.count == 20)
        #expect(dataset.parents == [
            "POSTECH 학부", "POSTECH 대학원", "Apple·연계 교육 프로그램",
            "POSTECH 교직원·행정 조직", "POSTECH 연구기관·연구사업단", "기타 이용자"
        ])
        #expect(dataset.preferenceNames.first == "수학")
    }

    @Test("소속 경로는 모두 다르고, 학부와 대학원의 같은 이름 학과는 각자의 경로를 가진다")
    func affiliationPathsAreUnique() async throws {
        let dataset = try await Self.bundledDataset()
        #expect(Set(dataset.affiliationPaths).count == dataset.affiliationPaths.count)
        let math = dataset.affiliationPaths.filter { $0.name == "수학과" }
        #expect(Set(math.map(\.parent)) == ["POSTECH 학부", "POSTECH 대학원"])
    }

    @Test("모든 목록은 20권이고 목록 안에 중복이 없으며 참조한 도서가 모두 있다")
    func everyListResolvesTwentyBooks() async throws {
        let dataset = try await Self.bundledDataset()
        #expect(dataset.bookCount > 0)
        for path in dataset.affiliationPaths {
            let ids = dataset.recordIDs(forAffiliation: path)
            #expect(ids.count == 20, "\(path.key)")
            #expect(Set(ids).count == ids.count, "\(path.key)")
            #expect(dataset.books(forAffiliation: path).count == 20, "\(path.key)")
        }
        for name in dataset.preferenceNames {
            let ids = dataset.recordIDs(forPreference: name)
            #expect(ids.count == 20, "\(name)")
            #expect(Set(ids).count == ids.count, "\(name)")
        }
    }

    @Test("도서는 소장 조회가 가능한 primo id와 ISBN을 가진다")
    func booksAreQueryable() async throws {
        let dataset = try await Self.bundledDataset()
        for path in dataset.affiliationPaths.prefix(30) {
            for book in dataset.books(forAffiliation: path) {
                #expect(book.id.hasPrefix("primo:alma"))
                #expect(BookHoldingsClient.recordID(for: book) != nil)
                #expect(BookISBN.isbn13(from: book.isbn) != nil)
                // 표지가 있으면 https 주소다. 표지가 없는 책(null)은 기본 이미지를 보여준다.
                if let url = book.imageURL { #expect(url.scheme == "https") }
            }
        }
    }

    @Test("여러 선호 분류를 고르면 목록을 합치고 recordID로 중복을 뺀다 (Q3)")
    func mergesPreferences() async throws {
        let dataset = try await Self.bundledDataset()
        let names = Array(dataset.preferenceNames.prefix(3))
        let merged = dataset.books(forPreferences: names)
        let expectedIDs = Set(names.flatMap { dataset.recordIDs(forPreference: $0) })
        #expect(merged.count == expectedIDs.count)
        #expect(Set(merged.map(\.id)).count == merged.count)
    }
}
