import ComposableArchitecture
import Foundation

nonisolated struct BookHoldingsClient: Sendable {
    var fetch: @Sendable (_ recordID: String) async throws -> [BookHolding]

    static func recordID(for book: Book) -> String? {
        for value in [book.controlNumber, book.id].compactMap({ $0 }) {
            let recordID = value.hasPrefix("primo:") ? String(value.dropFirst(6)) : value
            if PrimoBookHoldingsService.isValid(recordID: recordID) { return recordID }
        }
        return nil
    }
}

extension BookHoldingsClient: DependencyKey {
    private static let cache = BookHoldingsCache()

    static let liveValue = Self(fetch: { recordID in
        let service: PrimoBookHoldingsService
        if let address = await AppConfiguration.primoProxyURL {
            guard let url = URL(string: address), url.scheme == "https", url.host != nil,
                  url.user == nil, url.password == nil, url.query == nil, url.fragment == nil else {
                throw BookHoldingsError.invalidProxyURL
            }
            // 프록시가 기관 키를 보관한다. 앱의 키를 프록시로 전달하지 않는다.
            service = .init(baseURL: url)
        } else {
            #if DEBUG
            guard let key = await AppConfiguration.primoAPIKey else { throw BookHoldingsError.missingAPIKey }
            service = .init(apiKey: key)
            #else
            throw BookHoldingsError.missingProxy
            #endif
        }
        let cacheKey = service.baseURL.absoluteString + "|" + recordID
        if let holdings = await cache.value(for: cacheKey) { return holdings }
        let holdings = try await service.fetch(recordID: recordID)
        try Task.checkCancellation()
        await cache.insert(holdings, for: cacheKey)
        return holdings
    })

    static let testValue = Self(fetch: { _ in [] })
}

extension DependencyValues {
    var bookHoldingsClient: BookHoldingsClient {
        get { self[BookHoldingsClient.self] }
        set { self[BookHoldingsClient.self] = newValue }
    }
}

private actor BookHoldingsCache {
    private var entries: [String: (expires: Date, holdings: [BookHolding])] = [:]

    func value(for key: String) -> [BookHolding]? {
        guard let entry = entries[key], entry.expires > Date() else {
            entries[key] = nil
            return nil
        }
        return entry.holdings
    }

    func insert(_ holdings: [BookHolding], for key: String) {
        entries = entries.filter { $0.value.expires > Date() }
        if entries.count >= 200, let oldest = entries.min(by: { $0.value.expires < $1.value.expires })?.key {
            entries[oldest] = nil
        }
        entries[key] = (Date().addingTimeInterval(24 * 60 * 60), holdings)
    }
}
