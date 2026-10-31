import Foundation

/// 같은 판본의 큰 표지를 먼저 요청하고, 실패하면 제공받은 원본 주소로 복구한다.
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
                // 큰 주소에서도 작은 이미지가 올 수 있다. 정상 표지는 크기만으로 버리지 않는다.
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

    /// 확인한 앞표지 주소 형식만 바꾼다. ISBN·상품 번호·파일명·쿼리는 유지한다.
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
