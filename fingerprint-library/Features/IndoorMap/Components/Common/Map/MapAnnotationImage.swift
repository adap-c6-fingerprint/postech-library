import UIKit

/// 홈 시설 핀과 길안내 배지에 원본 픽셀·색상을 유지한 에셋을 표시한다.
enum MapAnnotationImage {
    static func asset(named name: String, size: CGFloat) -> UIImage? {
        guard let image = UIImage(named: name), let pixels = image.cgImage else { return nil }
        return UIImage(cgImage: pixels, scale: CGFloat(pixels.width) / size, orientation: image.imageOrientation)
            .withRenderingMode(.alwaysOriginal)
    }
}
