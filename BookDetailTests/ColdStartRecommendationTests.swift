import ComposableArchitecture
import Foundation
import Testing
@testable import fingerprint_library

@MainActor
struct ColdStartRecommendationTests {
    @Test("관심사를 LCC 분류기호로 정리한다")
    func normalizeCodes() {
        #expect(ColdStartRecommendation.normalizedCodes([" q ", "QC", "q", "가", "ABCD", ""]) == ["Q", "QC"])
    }

    @Test("대분류는 하위 분류까지 펼쳐 숫자 와일드카드로 검색한다")
    func primoQuery() {
        let query = ColdStartRecommendation.primoQuery(for: ["Q"])
        let terms = query.dropFirst("any,contains,".count).components(separatedBy: " OR ")
        #expect(query.hasPrefix("any,contains,Q1* OR "))
        #expect(terms.count == 12 * 9)
        #expect(terms.contains("QA1*"))
        #expect(terms.contains("QR9*"))
        #expect(ColdStartRecommendation.primoQuery(for: ["QC"]).components(separatedBy: " OR ").count == 9)
    }

    @Test("대분류 관심사는 하위 분류 청구기호까지 통과시킨다")
    func callNumberMatching() {
        #expect(ColdStartRecommendation.callNumber("QC174.12 .M47 1998", matchesAnyOf: ["Q"]))
        #expect(ColdStartRecommendation.callNumber("Q180 .A1", matchesAnyOf: ["Q"]))
        #expect(ColdStartRecommendation.callNumber("qa 76.9", matchesAnyOf: ["Q"]))
        #expect(!ColdStartRecommendation.callNumber("QCD theory", matchesAnyOf: ["Q"]))
        #expect(!ColdStartRecommendation.callNumber("PL123", matchesAnyOf: ["Q"]))
        #expect(ColdStartRecommendation.callNumber("QC174", matchesAnyOf: ["QC"]))
        #expect(!ColdStartRecommendation.callNumber("QA76", matchesAnyOf: ["QC"]))
    }

    @Test("무작위 시작 위치는 게스트 제한 안에서만 고른다")
    func randomOffset() {
        var generator = SystemRandomNumberGenerator()
        #expect(ColdStartRecommendation.randomOffset(total: 30, using: &generator) == 0)
        for _ in 0..<200 {
            let offset = ColdStartRecommendation.randomOffset(total: 9_000, using: &generator)
            #expect((0...450).contains(offset))
        }
    }

    @Test("찜과 최근 검색이 모두 비었을 때만 첫 추천을 쓴다")
    func shouldApply() {
        #expect(ColdStartRecommendation.shouldApply(favoriteKeys: [], recentQueries: []))
        #expect(!ColdStartRecommendation.shouldApply(favoriteKeys: [["control", "x"]], recentQueries: []))
        #expect(!ColdStartRecommendation.shouldApply(favoriteKeys: [], recentQueries: ["스위프트"]))
    }

    @Test("포스텍 응답에서 조건에 맞는 후보만 남긴다")
    func parsePrimo() throws {
        let json = """
        {"info":{"total":123},"docs":[
          {"pnx":{"control":{"recordid":["alma1"]},"addata":{"isbn":["9788966260959"]}},
           "delivery":{"holding":[{"callNumber":"QC174.12 .M47 1998"}],
                       "link":[{"linkType":"thumbnail","linkURL":"https://covers.example.com/1.jpg"}]}},
          {"pnx":{"control":{"recordid":["alma2"]},"addata":{"isbn":["8966260950"]}},
           "delivery":{"holding":[{"callNumber":"QA76.9 .A43"}]}},
          {"pnx":{"control":{"recordid":["alma3"]},"addata":{"isbn":["9788966260959"]}},
           "delivery":{"holding":[{"callNumber":"PL123"}]}},
          {"pnx":{"control":{"recordid":["alma4"]},"addata":{"isbn":["9788966260959"]}},
           "delivery":{"holding":[]}},
          {"pnx":{"control":{"recordid":["alma1"]}},
           "delivery":{"holding":[{"callNumber":"QC1"}]}},
          {"pnx":{"control":{"recordid":["alma5"]}},
           "delivery":{"holding":[{"callNumber":"QB43"}]}},
          {"pnx":{"control":{"recordid":["alma6"]},"addata":{"isbn":["9788966260959"]}},
           "delivery":{"holding":[{"callNumber":"Q180"}],
                       "link":[{"linkType":"thumbnail","linkURL":"https://books.google.com/x?jscmd=viewapi"}]}},
          {"pnx":{"control":{"recordid":["alma7"]}},
           "delivery":{"holding":[{"callNumber":"QA1 .L4"}],
                       "link":[{"linkType":"thumbnail","linkURL":"https://local.4libs.org/c.php?isbn=978 (pbk.)&institute=82KC-P"}]}}
        ]}
        """
        let page = try ColdStartRecommendationService.parsePrimo(Data(json.utf8), codes: ["Q"])
        #expect(page.total == 123)
        #expect(page.candidates == [
            ColdStartCandidate(recordID: "alma1", primoCoverURL: URL(string: "https://covers.example.com/1.jpg"),
                               isbn13: "9788966260959"),
            ColdStartCandidate(recordID: "alma2", primoCoverURL: nil, isbn13: "9788966260959"),
            ColdStartCandidate(recordID: "alma6", primoCoverURL: nil, isbn13: "9788966260959"),
            ColdStartCandidate(recordID: "alma7",
                               primoCoverURL: URL(string: "https://local.4libs.org/c.php?isbn=978%20(pbk.)&institute=82KC-P"),
                               isbn13: nil),
        ])
    }

    @Test("정보나루의 http 표지 주소는 https로 바꾼다")
    func secureCoverURL() {
        #expect(ColdStartRecommendationService.secureCoverURL("http://image.aladin.co.kr/product/1/cover/a.jpg")
                == URL(string: "https://image.aladin.co.kr/product/1/cover/a.jpg"))
        #expect(ColdStartRecommendationService.secureCoverURL("https://bookthumb-phinf.pstatic.net/a.jpg?type=m1")
                == URL(string: "https://bookthumb-phinf.pstatic.net/a.jpg?type=m1"))
        #expect(ColdStartRecommendationService.secureCoverURL("") == nil)
        #expect(ColdStartRecommendationService.secureCoverURL("ftp://example.com/a.jpg") == nil)
    }

    @Test("정보나루로 6권을 채우면 4libs 링크는 확인하지 않는다")
    func data4LibraryFirst() async {
        let imageChecks = LockIsolated(0)
        let candidates = (1...8).map {
            ColdStartCandidate(recordID: "b\($0)", primoCoverURL: URL(string: "https://4libs.example.com/\($0)"),
                               isbn13: "isbn-\($0)")
        }
        let books = await ColdStartRecommendationService.booksWithCovers(
            candidates,
            data4LibraryLookup: { URL(string: "https://d4l.example.com/\($0).jpg") },
            isRealImage: { _ in
                imageChecks.withValue { $0 += 1 }
                return true
            }
        )
        #expect(books.map(\.recordID) == ["b1", "b2", "b3", "b4", "b5", "b6"])
        #expect(books.first?.coverImageURL == URL(string: "https://d4l.example.com/isbn-1.jpg"))
        #expect(imageChecks.value == 0)
    }

    @Test("정보나루가 10권씩 확인하다 6권이 모이면 멈춘다")
    func data4LibraryBatches() async {
        let lookedUp = LockIsolated<[String]>([])
        let candidates = (1...25).map {
            ColdStartCandidate(recordID: "n\($0)", primoCoverURL: nil, isbn13: "isbn-\($0)")
        }
        let books = await ColdStartRecommendationService.booksWithCovers(
            candidates,
            data4LibraryLookup: { isbn in
                lookedUp.withValue { $0.append(isbn) }
                let number = Int(isbn.dropFirst("isbn-".count)) ?? 0
                return number.isMultiple(of: 3) ? URL(string: "https://d4l.example.com/\(number).jpg") : nil
            },
            isRealImage: { _ in true }
        )
        // 1~10번에서 3·6·9번, 11~20번에서 12·15·18번 → 6권이 모여 21번부터는 묻지 않는다.
        #expect(books.map(\.recordID) == ["n3", "n6", "n9", "n12", "n15", "n18"])
        #expect(lookedUp.value.count == 20)
    }

    @Test("정보나루로 모자라면 4libs 링크를 받아 보고 실제 이미지인 것만 채운다")
    func fallbackToRealPrimoImages() async {
        let candidates = [
            ColdStartCandidate(recordID: "d1", primoCoverURL: URL(string: "https://4libs.example.com/d1"), isbn13: "isbn-d1"),
            ColdStartCandidate(recordID: "x1", primoCoverURL: URL(string: "https://4libs.example.com/empty"), isbn13: "isbn-x1"),
            ColdStartCandidate(recordID: "p1", primoCoverURL: URL(string: "https://4libs.example.com/p1"), isbn13: nil),
            ColdStartCandidate(recordID: "p2", primoCoverURL: URL(string: "https://4libs.example.com/p2"), isbn13: "isbn-p2"),
        ]
        let books = await ColdStartRecommendationService.booksWithCovers(
            candidates,
            data4LibraryLookup: { $0 == "isbn-d1" ? URL(string: "https://d4l.example.com/d1.jpg") : nil },
            isRealImage: { $0.lastPathComponent != "empty" }
        )
        #expect(books == [
            RecommendedBook(recordID: "d1", coverImageURL: URL(string: "https://d4l.example.com/d1.jpg")!),
            RecommendedBook(recordID: "p1", coverImageURL: URL(string: "https://4libs.example.com/p1")!),
            RecommendedBook(recordID: "p2", coverImageURL: URL(string: "https://4libs.example.com/p2")!),
        ])
    }

}
