import Foundation

/// Compile this with the production model, mapper and service (see the simulation context).
@main
struct VerifyPrimoHoldings {
    static func main() async throws {
        let base = URL(string: CommandLine.arguments.dropFirst().first ?? "http://127.0.0.1:47575/library")!
        let service = PrimoBookHoldingsService(baseURL: base)
        let holdings = try await service.fetch(recordID: "alma991000958759703286")
        try check(holdings.count == 3, "real sample's three holdings")
        try check(holdings.first?.locationCode == "c3b", "physical location code")
        try check(holdings.first?.callNumber == "CB113.H4 .H3713 2015", "complete call number")
        try check(holdings.last?.availability == "unavailable", "unavailable copy retained")
        for suffix in ["1", "2", "3"] {
            do {
                _ = try await service.fetch(recordID: "alma99999999999999000" + suffix)
                throw VerificationFailed(message: "expected upstream failure \(suffix)")
            } catch is BookHoldingsError { }
        }
        for suffix in ["4", "5"] {
            let result = try await service.fetch(recordID: "alma99999999999999000" + suffix)
            try check(result.isEmpty, "empty or mismatched record \(suffix)")
        }
        let recovered = try await service.fetch(recordID: "alma999999999999990006")
        try check(recovered.count == 3, "429 retry recovery")
        let mixed = try await service.fetch(recordID: "alma999999999999990007")
        try check(mixed == holdings, "incomplete non-target documents do not hide a valid target")
        let (data, _) = try await URLSession.shared.data(from: base.appending(path: "__counts"))
        let counts = try JSONDecoder().decode([String: Int].self, from: data)
        try check(counts["alma999999999999990001"] == 3, "503 bounded to three attempts")
        try check(counts["alma999999999999990002"] == 1, "401 not retried")
        try check(counts["alma999999999999990003"] == 1, "invalid JSON not retried")
        try check(counts["alma999999999999990006"] == 2, "429 recovered on second attempt")
        print("PASS: production Swift 6 HTTP service — holdings, incomplete documents, exact ID, empty result, 401, invalid JSON, 503 and 429 recovery")
    }

    static func check(_ condition: Bool, _ message: String) throws {
        if !condition { throw VerificationFailed(message: message) }
    }
    struct VerificationFailed: Error { let message: String }
}
