import UIKit

@MainActor
enum BookCoverPipeline {
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
            if url.isFileURL {
                guard let image = UIImage(contentsOfFile: url.path) else {
                    throw URLError(.cannotDecodeContentData)
                }
                return image
            }
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let response = response as? HTTPURLResponse,
                  (200..<300).contains(response.statusCode) else {
                throw URLError(.badServerResponse)
            }
            guard let image = UIImage(data: data) else {
                throw URLError(.cannotDecodeContentData)
            }
            return image
        }
    )
}
