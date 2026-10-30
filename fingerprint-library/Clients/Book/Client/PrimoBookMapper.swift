import Foundation

/// Primo 검색 응답을 앱의 Book으로 변환한다. 인증·전송·캐시는 다루지 않는다.
nonisolated enum PrimoBookMapper {
    nonisolated enum MappingError: Error { case invalidResponse }

    nonisolated static func publicationYear(from value: String?) -> String? {
        guard let value,
              let range = value.range(
                of: #"(?<![0-9])(?!0000)[0-9]{4}(?![0-9])"#,
                options: .regularExpression
              ) else {
            return nil
        }

        return String(value[range])
    }

    nonisolated static func publisher(
        from values: [String]?,
        fallback: [String]?
    ) -> String? {
        nonEmpty(
            values?.compactMap { nonEmpty($0) }.joined(separator: ", ")
        ) ?? nonEmpty(
            fallback?.compactMap { nonEmpty($0) }.joined(separator: ", ")
        )
    }

    private nonisolated static func nonEmpty(_ value: String?) -> String? {
        guard let text = value?.trimmingCharacters(
            in: .whitespacesAndNewlines
        ), !text.isEmpty else {
            return nil
        }

        return text
    }

    /// 검색 응답 변환은 인증과 분리해 소장 위치와 서지 정보를 오프라인에서 검증한다.
    nonisolated static func books(from data: Data) throws -> [Book] {
        let decodedResponse = try JSONDecoder().decode(
            PrimoResponse.self,
            from: data
        )

        var seen = Set<String>()

        let books = decodedResponse.docs.compactMap { document -> Book? in
            guard
                let recordID = nonEmpty(
                    document.pnx.control.recordid.first
                ),
                let rawTitle = document.pnx.display.title.first
            else {
                return nil
            }

            let title = BookText.plainText(rawTitle)

            guard !title.isEmpty, seen.insert(recordID).inserted else {
                return nil
            }

            let imageURL = document.delivery?.link?
                .filter {
                    $0.linkType == "thumbnail"
                        || $0.linkType?.hasSuffix("/thumbnail") == true
                }
                .compactMap { link -> URL? in
                    guard
                        let address = link.linkURL,
                        let parts = URLComponents(string: address),
                        parts.scheme?.lowercased() == "https",
                        let host = parts.host, !host.isEmpty
                    else { return nil }

                    // 이미지 대신 정보를 반환하는 조회용 주소는 제외
                    let isLookup = parts.queryItems?.contains {
                        $0.name == "jscmd" && $0.value == "viewapi"
                    } ?? false

                    return isLookup ? nil : parts.url
                }
                .first

            let identity = "primo:\(recordID)"

            return Book(
                id: identity,
                isbn: BookISBN.isbn13(from: document.pnx.addata?.isbn?.joined(separator: " ")),
                controlNumber: identity,
                title: title,
                author: nonEmpty(
                    document.pnx.display.creator?
                        .map {
                            // $$Q 앞의 화면 표시용 정보만 사용한다.
                            let displayText = $0.components(separatedBy: "$$Q").first ?? $0
                            return BookText.plainText(displayText)
                        }
                    .filter { !$0.isEmpty }
                    .joined(separator: ", ")
                ) ?? "저자 정보 없음",
                publisher: publisher(
                    from: document.pnx.addata?.pub,
                    fallback: document.pnx.addata?.publisher
                ),
                publicationYear: publicationYear(from:
                    document.pnx.addata?.date?.first
                ),
                description: nil,
                imageURL: imageURL,
                subLocation: document.delivery?.subLocation
            )
        }

        if !decodedResponse.docs.isEmpty && books.isEmpty {
            throw MappingError.invalidResponse
        }

        return books
    }

    private nonisolated struct PrimoResponse: Decodable {
        let docs: [PrimoDocument]
    }

    private nonisolated struct PrimoDocument: Decodable {
        let pnx: PrimoPNX
        let delivery: PrimoDelivery?
    }

    private nonisolated struct PrimoDelivery: Decodable {
        let link: [PrimoLink]?
        let holding: [PrimoHolding]?
        let bestlocation: PrimoHolding?

        var subLocation: String? {
            // 명시적인 빈 holding은 소장 정보 없음이며, bestlocation으로 되살리지 않는다.
            let locations = holding.map { $0.compactMap(\.subLocation) }
                ?? [bestlocation?.subLocation].compactMap { $0 }
            var seen = Set<String>()
            let names = locations.map(BookText.plainText)
                .filter { !$0.isEmpty && seen.insert($0).inserted }
            return names.isEmpty ? nil : names.joined(separator: " · ")
        }
    }

    private nonisolated struct PrimoHolding: Decodable {
        let subLocation: String?
    }

    private nonisolated struct PrimoLink: Decodable {
        let linkType: String?
        let linkURL: String?
    }

    private nonisolated struct PrimoPNX: Decodable {
        let control: PrimoControl
        let display: PrimoDisplay
        let addata: PrimoAddData?
    }

    private nonisolated struct PrimoAddData: Decodable {
        let isbn: [String]?
        let pub: [String]?
        let publisher: [String]?
        let date: [String]?
    }

    private nonisolated struct PrimoControl: Decodable {
        let recordid: [String]
    }

    private nonisolated struct PrimoDisplay: Decodable {
        let title: [String]
        let creator: [String]?
    }
}
