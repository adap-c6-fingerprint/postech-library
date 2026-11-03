import UIKit

/// 홈 시설 핀과 길안내 배지에 원본 픽셀·색상을 유지한 에셋을 표시한다.
enum MapAnnotationImage {
    static let size = CGSize(width: 30, height: 30)

    static func asset(named name: String) -> UIImage? {
        guard let image = UIImage(named: name), let pixels = image.cgImage else { return nil }
        return UIImage(cgImage: pixels, scale: CGFloat(pixels.width) / size.width, orientation: image.imageOrientation)
            .withRenderingMode(.alwaysOriginal)
    }

    static func symbol(named name: String, tintColor: UIColor) -> UIImage? {
        guard let image = UIImage(systemName: name)?.withTintColor(tintColor, renderingMode: .alwaysOriginal) else { return nil }
        let scale = min(size.width / image.size.width, size.height / image.size.height)
        let glyph = CGSize(width: image.size.width * scale, height: image.size.height * scale)
        return UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(x: (size.width - glyph.width) / 2, y: (size.height - glyph.height) / 2,
                                  width: glyph.width, height: glyph.height))
        }.withRenderingMode(.alwaysOriginal)
    }
}
