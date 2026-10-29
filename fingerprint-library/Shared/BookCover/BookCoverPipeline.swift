import UIKit
import OSLog

@MainActor
enum BookCoverPipeline {
    private static let logger = Logger(subsystem: "Fingerprint", category: "BookCover")
    static let fallback = Yes24BookCoverResolver { isbn13 in
        guard let key = await AppConfiguration.yes24APIKey else {
            throw BookDetailClientError.missingAPIKey
        }
        return try await Yes24BookDetailService().fetchCoverURL(isbn13: isbn13, apiKey: key)
    }
    /// 추천·검색·상세가 같은 메모리 캐시와 진행 중 요청을 사용한다.
    static let shared = SharedImageLoader<UIImage>(
        readLocalImage: { url in
            guard url.isFileURL else { return nil }
            return UIImage(contentsOfFile: url.path)
        },
        cost: { image in
            guard let cgImage = image.cgImage else { return 1 }
            return cgImage.bytesPerRow * cgImage.height
        },
        loadImage: { url in
            do {
                if url.isFileURL {
                    guard let image = UIImage(contentsOfFile: url.path) else {
                        throw BookCoverFailure.unreadableLocalFile
                    }
                    return image
                }
                let (data, response) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                try BookCoverFailure.validate(data: data, response: response)
                guard let image = UIImage(data: data) else { throw BookCoverFailure.invalidImage }
                return image
            } catch {
                guard !Task.isCancelled else { throw CancellationError() }
                let diagnostic = BookCoverFailure.diagnostic(for: error)
                // URL·ISBN·헤더·응답 본문·error.localizedDescription은 기록하지 않는다.
                logger.notice("Cover load: reason=\(diagnostic.reason, privacy: .public) http=\(diagnostic.httpStatus) transport=\(diagnostic.transportCode)")
                throw error
            }
        }
    )
}
