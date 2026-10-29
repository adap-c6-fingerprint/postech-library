import Foundation

// Compile with the production models/mapper and onboarding enums; see Docs/RecommendationDatasets/README.txt.
@main
struct VerifyCuratedRecommendations {
    struct Invalid: Error, CustomStringConvertible {
        let description: String
    }
    static func require(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        if try !value() { throw Invalid(description: message) }
    }
    static func object(_ value: Any?) throws -> [String: Any] {
        guard let value = value as? [String: Any] else { throw Invalid(description: "Expected object") }
        return value
    }
    static func objects(_ value: Any?) throws -> [[String: Any]] {
        guard let value = value as? [[String: Any]] else { throw Invalid(description: "Expected object array") }
        return value
    }
    static func strings(_ value: Any?) throws -> [String] {
        guard let value = value as? [String] else { throw Invalid(description: "Expected string array") }
        return value
    }
    static func string(_ value: Any?) throws -> String {
        guard let value = value as? String, !value.isEmpty else { throw Invalid(description: "Expected nonempty string") }
        return value
    }
    static func normalizedTitle(_ value: String) -> String {
        BookText.plainText(value)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s*/\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    static func validate(_ data: [String: Any], _ evidence: [String: Any]) throws -> Int {
        try require(data["schemaVersion"] as? Int == 1, "schemaVersion")
        let records = try objects(data["books"]), checks = try objects(evidence["checks"])
        let ids = try records.map { try string($0["recordID"]) }
        let checkIDs = try checks.map { try string($0["recordID"]) }
        try require(Set(ids).count == ids.count && Set(checkIDs).count == checkIDs.count, "Duplicate catalogue/evidence ID")
        try require(Set(ids) == Set(checkIDs), "Evidence coverage")
        let proofByID = Dictionary(uniqueKeysWithValues: zip(checkIDs, checks))
        var holdingsByID: [String: [BookHolding]] = [:]
        var isbnByID: [String: String] = [:]
        for record in records {
            let id = try string(record["recordID"]), book = try object(record["book"])
            let proof = try object(proofByID[id]), document = try object(proof["document"])
            let pnx = try object(document["pnx"]), control = try object(pnx["control"])
            let display = try object(pnx["display"]), addata = try object(pnx["addata"])
            let delivery = try object(document["delivery"])
            try require(PrimoBookHoldingsService.isValid(recordID: id), "Invalid alma recordID")
            try require(try strings(control["recordid"]).contains(id), "Source recordID mismatch")
            try require(try strings(display["type"]).contains { $0.lowercased() == "printed_book" }, "Not Printed_Book")
            try require(try strings(delivery["deliveryCategory"]).contains("Alma-P"), "No physical delivery")
            try require(proof["httpStatus"] as? Int == 200, "HTTP verification not successful")
            let url = try string(proof["requestURL"])
            guard let components = URLComponents(string: url) else { throw Invalid(description: "Invalid request URL") }
            try require(components.scheme == "https" && components.host == "api-ap.hosted.exlibrisgroup.com"
                && components.path == "/primo/v1/search", "Unexpected verification endpoint")
            let items = components.queryItems ?? []
            try require(Set(items.map(\.name)).count == items.count, "Duplicate query parameter")
            let params = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
            try require(params["vid"] == "82POSTECH_INST:82POSTECH" && params["q"] == "any,contains,\(id.dropFirst(4))"
                && params["limit"] == "20" && params["skipDelivery"] == "false" && params["apikey"] == nil, "Lookup contract mismatch")
            let isbn = try string(book["isbn"]), rawISBNs = try strings(addata["isbn"])
            try require(BookISBN.isbn13(from: isbn) == isbn && BookISBN.isbn13(from: rawISBNs.joined(separator: " ")) == isbn,
                        "ISBN mismatch \(id)")
            try require(book["id"] as? String == "primo:\(id)" && book["controlNumber"] as? String == "primo:\(id)", "Book identity mismatch")
            let title = try string(book["title"]), sourceTitle = try strings(display["title"]).first ?? ""
            try require(normalizedTitle(sourceTitle) == title, "Title mismatch \(id)")
            let model = Book(id: "primo:\(id)", isbn: isbn, controlNumber: "primo:\(id)", title: title,
                author: book["author"] as? String ?? "", publisher: book["publisher"] as? String,
                publicationYear: book["publicationYear"] as? String, description: nil, imageURL: nil,
                subLocation: book["subLocation"] as? String)
            try require(model.id == model.controlNumber, "Book initializer compatibility")
            let response = try JSONSerialization.data(withJSONObject: ["docs": [document]])
            let expected = try PrimoHoldingsMapper.decode(response, recordID: id).filter {
                $0.institutionCode == "82POSTECH_INST" && $0.libraryCode == "MAIN"
                    && !($0.callNumber ?? "").isEmpty && !($0.locationCode ?? "").isEmpty
            }
            let actual = try objects(record["holdings"]).map { h in
                BookHolding(holdingID: h["holdingID"] as? String, institutionCode: h["institutionCode"] as? String,
                    libraryCode: h["libraryCode"] as? String, locationCode: h["locationCode"] as? String,
                    locationName: h["locationName"] as? String, callNumber: h["callNumber"] as? String,
                    availability: h["availability"] as? String)
            }
            try require(!actual.isEmpty && actual == expected, "Production holdings mapper mismatch \(id)")
            try require(record["verifiedAt"] as? String == proof["fetchedAt"] as? String, "Verification timestamp mismatch")
            holdingsByID[id] = actual
            isbnByID[id] = isbn
        }
        let categories = try objects(data["categories"]), affiliations = try objects(data["affiliations"])
        let categoryIDs = try categories.map { try string($0["id"]) }
        try require(Set(categoryIDs) == Set(UserInterest.allCases.map(\.rawValue)) && categoryIDs.count == UserInterest.allCases.count, "Missing/duplicate categories")
        var expectedAffiliations: [String: String] = [:]
        for status in PostechStatus.allCases {
            if status.departments.isEmpty { expectedAffiliations[status.rawValue] = status.koreanName }
            for department in status.departments {
                let key: String
                switch department { case .undergraduate(let d): key = d.rawValue; case .graduate(let d): key = d.rawValue }
                expectedAffiliations[status.rawValue + "." + key] = department.koreanName
            }
        }
        let affiliationIDs = try affiliations.map { try string($0["id"]) }
        try require(Set(affiliationIDs) == Set(expectedAffiliations.keys) && affiliationIDs.count == expectedAffiliations.count,
                    "Missing/duplicate affiliations")
        var used = Set<String>()
        for (groups, count) in [(categories, 12), (affiliations, 20)] {
            for group in groups {
                let id = try string(group["id"]), references = try strings(group["recordIDs"])
                try require(references.count == count && Set(references).count == count, "Quota/duplicate failure \(id)")
                try require(Set(references).isSubset(of: Set(ids)), "Dangling reference \(id)")
                try require(Set(references.compactMap { isbnByID[$0] }).count == count, "Repeated ISBN \(id)")
                used.formUnion(references)
                if count == 12 {
                    guard let interest = UserInterest(rawValue: id) else { throw Invalid(description: "Unknown interest") }
                    try require(group["name"] as? String == interest.koreanName && (try strings(group["lccClasses"])) == interest.lccClasses, "Interest key/name mismatch")
                    for reference in references {
                        try require(holdingsByID[reference, default: []].contains { holding in
                            interest.lccClasses.contains { (holding.callNumber ?? "").hasPrefix($0) }
                        }, "LCC category mismatch \(id) / \(reference)")
                    }
                } else {
                    try require(group["profileDepartmentName"] as? String == expectedAffiliations[id], "Affiliation profile key mismatch")
                }
            }
        }
        try require(used == Set(ids), "Unused catalogue entries")
        return ids.count
    }
    static func main() throws {
        let root = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? FileManager.default.currentDirectoryPath)
        let data = try object(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("fingerprint-library/Resources/Recommendations/CuratedRecommendations.json"))))
        let evidence = try object(JSONSerialization.jsonObject(with: Data(contentsOf: root.appendingPathComponent("Docs/RecommendationDatasets/PrimoVerification.json"))))
        let count = try validate(data, evidence)
        // 손상된 입력을 통과시키지 않는지도 같은 검증기로 확인한다.
        var invalid = data, books = try objects(data["books"]), first = books[0], book = try object(first["book"])
        book["isbn"] = "9780000000000"; first["book"] = book; books[0] = first; invalid["books"] = books
        try require((try? validate(invalid, evidence)) == nil, "Bad ISBN was accepted")
        invalid = data
        var groups = try objects(data["categories"]), group = groups[0], references = try strings(group["recordIDs"])
        references[1] = references[0]; group["recordIDs"] = references; groups[0] = group; invalid["categories"] = groups
        try require((try? validate(invalid, evidence)) == nil, "Repeated recommendation was accepted")
        invalid = data; groups = try objects(data["affiliations"]); groups.removeLast(); invalid["affiliations"] = groups
        try require((try? validate(invalid, evidence)) == nil, "Missing affiliation was accepted")
        var badEvidence = evidence, checks = try objects(evidence["checks"]), check = checks[0]
        var document = try object(check["document"]), delivery = try object(document["delivery"])
        delivery["deliveryCategory"] = ["Alma-E"]; document["delivery"] = delivery; check["document"] = document; checks[0] = check; badEvidence["checks"] = checks
        try require((try? validate(data, badEvidence)) == nil, "Electronic-only evidence was accepted")
        print("PASS: \(count) books; 17×12 categories; 36×20 affiliations; production Book/ISBN/holdings compatibility; 4 negative checks")
    }
}
