import Foundation

@MainActor
enum BookCoverSource {
    static func usesProvidedURLFirst(_ url: URL, isbn13: String?) -> Bool {
        guard isbn13 != nil, !url.isFileURL else { return true }
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return host == "yes24.com" || host.hasSuffix(".yes24.com")
    }

    static func load<Value: Sendable>(
        url: URL?, isbn13: String?, cachedURL: URL? = nil,
        lookupYes24: (String) async throws -> URL?,
        lookupLegacyOriginal: (() async throws -> URL?)? = nil,
        loadImage: (URL) async throws -> Value
    ) async throws -> Value {
        try Task.checkCancellation()
        if let cachedURL {
            do { return try await loadImage(cachedURL) }
            catch { try Task.checkCancellation() }
        }
        let providedURLFirst = url.map { usesProvidedURLFirst($0, isbn13: isbn13) } ?? false
        var failure: any Error = BookCoverFailure.unavailable(statusCode: 0)

        if providedURLFirst, let url {
            do { return try await loadImage(url) }
            catch {
                try Task.checkCancellation()
                failure = error
            }
        }

        if let isbn13 {
            do {
                if let preferredURL = try await lookupYes24(isbn13), !providedURLFirst || preferredURL != url {
                    try Task.checkCancellation()
                    return try await loadImage(preferredURL)
                }
            } catch {
                try Task.checkCancellation()
                if !BookCoverFailure.isUnavailable(error) { failure = error }
            }
        }

        if !providedURLFirst, let url {
            do { return try await loadImage(url) }
            catch {
                try Task.checkCancellation()
                if !BookCoverFailure.isUnavailable(error) { failure = error }
            }
        }

        if url?.isFileURL == true, let lookupLegacyOriginal {
            do {
                if let recoveredURL = try await lookupLegacyOriginal() {
                    try Task.checkCancellation()
                    return try await loadImage(recoveredURL)
                }
            } catch {
                try Task.checkCancellation()
                if !BookCoverFailure.isUnavailable(error) { failure = error }
            }
        }

        throw failure
    }
}
