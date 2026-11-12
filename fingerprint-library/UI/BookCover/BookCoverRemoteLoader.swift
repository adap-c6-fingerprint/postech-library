import Foundation

@MainActor
enum BookCoverRemoteLoader {
    static func image<Image: Sendable>(
        for originalURL: URL,
        download: @MainActor (URL) async throws -> Image
    ) async throws -> Image {
        try Task.checkCancellation()
        if let largeURL = largeURL(for: originalURL) {
            do {
                let image = try await download(largeURL)
                try Task.checkCancellation()
                return image
            } catch {
                try Task.checkCancellation()
                if error is CancellationError || (error as? URLError)?.code == .cancelled {
                    throw error
                }
            }
        }
        try Task.checkCancellation()
        let image = try await download(originalURL)
        try Task.checkCancellation()
        return image
    }

    static func largeURL(for originalURL: URL) -> URL? {
        guard var parts = URLComponents(url: originalURL, resolvingAgainstBaseURL: false),
              let scheme = parts.scheme?.lowercased(), ["http", "https"].contains(scheme),
              parts.user == nil, parts.password == nil,
              !parts.path.hasSuffix("/") else { return nil }
        let path = parts.path.split(separator: "/")
        switch parts.host?.lowercased() {
        case "image.aladin.co.kr":
            guard path.count == 5, path[0] == "product", path[3] == "cover",
                  path[1].allSatisfy(\.isNumber), path[2].allSatisfy(\.isNumber) else { return nil }
            parts.path = parts.path.replacingOccurrences(of: "/cover/", with: "/cover500/")
        case "image.yes24.com":
            guard path.count == 3, path[0] == "goods", path[1].allSatisfy(\.isNumber),
                  path[2] == "L" else { return nil }
            parts.path = String(parts.path.dropLast(2)) + "/XL"
        default:
            return nil
        }
        parts.scheme = "https"
        return parts.url
    }
}
