import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct BookClientTests {
    @Test("빈 검색 결과는 빈 배열로 반환한다")
    func acceptsEmptySearchResults() throws {
        #expect(try BookClient.books(from: Data(#"{"docs":[]}"#.utf8)).isEmpty)
    }

    @Test("응답 문서가 있어도 유효한 책이 하나도 없으면 기존 Client 오류로 전달한다")
    func rejectsUnusableSearchResults() {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma1"]},"display":{"title":[" "]}}}]}"#.utf8)
        #expect(throws: (any Error).self) { try BookClient.books(from: data) }
    }

    @Test("유효하지 않은 후보와 중복을 제외하고 최초의 유효한 책 순서를 보존한다")
    func keepsValidBooksInOrder() throws {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma1"]},"display":{"title":[" "]}}},{"pnx":{"control":{"recordid":["alma1"]},"display":{"title":["<b>첫 책</b>"]}}},{"pnx":{"control":{"recordid":["alma1"]},"display":{"title":["중복 책"]}}},{"pnx":{"control":{"recordid":["alma2"]},"display":{"title":["둘째 책"]}}}]}"#.utf8)
        let books = try BookClient.books(from: data)
        #expect(books.map(\.id) == ["primo:alma1", "primo:alma2"])
        #expect(books.map(\.title) == ["첫 책", "둘째 책"])
    }

    @Test("Primo 날짜에서 네 자리 출판 연도만 추출한다", arguments: [
        ("2011", "2011"),
        (" 2011\n", "2011"),
        ("c2011", "2011"),
        ("©2011", "2011"),
        ("[2011]", "2011"),
        ("2011년", "2011"),
        ("2011-2013", "2011")
    ])
    func publicationYear(sample: (String, String)) {
        #expect(PrimoBookMapper.publicationYear(from: sample.0) == sample.1)
    }

    @Test("유효한 네 자리 연도가 없으면 출판 연도를 저장하지 않는다", arguments: [
        nil, "", " \n", "n.d.", "20??", "201", "0000", "12011", "20110", "20112012"
    ] as [String?])
    func invalidPublicationYear(value: String?) {
        #expect(PrimoBookMapper.publicationYear(from: value) == nil)
    }

    @Test("공백 출판사는 건너뛰고 유효한 pub를 우선한다", arguments: [
        (nil, nil, nil),
        ([], [], nil),
        (["", " \n"], ["", " "], nil),
        (["주 출판사"], ["대체 출판사"], "주 출판사"),
        ([" 주 출판사 "], ["대체 출판사"], "주 출판사"),
        ([" ", " "], ["대체 출판사"], "대체 출판사"),
        (["", ""], ["대체 출판사"], "대체 출판사"),
        (nil, [" 대체 출판사 "], "대체 출판사"),
        ([], ["", " 대체 출판사 ", " "], "대체 출판사"),
        (["", " 주 출판사 ", " "], ["대체 출판사"], "주 출판사"),
        ([" 첫 출판사 ", "", "두 번째 출판사 "], nil, "첫 출판사, 두 번째 출판사")
    ] as [([String]?, [String]?, String?)])
    func publisher(sample: ([String]?, [String]?, String?)) {
        #expect(PrimoBookMapper.publisher(from: sample.0, fallback: sample.1) == sample.2)
    }

    @Test("검색 응답의 subLocation과 저자를 같은 책에 보존한다")
    func searchLocationAndAuthor() throws {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma991000958759703286"]},"display":{"title":["책 제목"],"creator":["<b>저자 이름</b>$$Qcreator-id"]},"addata":{"pub":["출판사"],"date":["c2026"]}},"delivery":{"holding":[{"subLocation":" 단행본3층 "},{"subLocation":"단행본3층"},{"subLocation":"스마트도서관"},{"subLocation":" "},{}]}}]}"#.utf8)
        let book = try #require(BookClient.books(from: data).first)
        #expect(book.subLocation == "단행본3층 · 스마트도서관")
        #expect(book.author == "저자 이름")
        #expect(book.publisher == "출판사")
        #expect(book.publicationYear == "2026")

        let cache = BookSearchResultCache()
        let request = BookSearchRequest(query: "책 제목", category: .all)
        cache.save([book], for: request)
        #expect(cache.load(request)?.first?.subLocation == book.subLocation)
    }

    @Test("holding이 없으면 bestlocation의 subLocation을 사용한다")
    func searchBestLocation() throws {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma991000958759703286"]},"display":{"title":["책 제목"]}},"delivery":{"bestlocation":{"subLocation":"단행본4층"}}}]}"#.utf8)
        let book = try #require(BookClient.books(from: data).first)
        #expect(book.subLocation == "단행본4층")
        #expect(book.author == "저자 정보 없음")
    }

    @Test("명시적인 빈 holding은 bestlocation의 과거 위치로 대체하지 않는다")
    func searchEmptyHoldings() throws {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma991000958759703286"]},"display":{"title":["책 제목"]}},"delivery":{"holding":[],"bestlocation":{"subLocation":"단행본3층"}}}]}"#.utf8)
        #expect(try BookClient.books(from: data).first?.subLocation == nil)
    }

    @Test("위치 필드가 없거나 비어 있어도 다른 책의 위치를 섞지 않는다")
    func searchMissingLocations() throws {
        let data = Data(#"{"docs":[{"pnx":{"control":{"recordid":["alma1"]},"display":{"title":["위치 있음"]}},"delivery":{"holding":[{"subLocation":"단행본3층"}]}},{"pnx":{"control":{"recordid":["alma2"]},"display":{"title":["위치 없음"]}}},{"pnx":{"control":{"recordid":["alma3"]},"display":{"title":["빈 위치"]}},"delivery":{"holding":[{"subLocation":" "},{}]}}]}"#.utf8)
        let books = try BookClient.books(from: data)
        #expect(books.map(\.subLocation) == ["단행본3층", nil, nil])
    }
}
