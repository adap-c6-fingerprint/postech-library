import Foundation
import CoreGraphics

struct BookNavigationCallNumberLabelLayout: Equatable {
    enum Metrics {
        static let minimumWidth: CGFloat = 96
        static let defaultFontSize: CGFloat = 20
        static let minimumFontSize: CGFloat = 19
        static let upperHeight: CGFloat = 149.977
        static let lowerHeight: CGFloat = 61.755
        static var height: CGFloat { upperHeight + lowerHeight }
        static let horizontalPadding: CGFloat = 12
        static let verticalPadding: CGFloat = 33.163
        static let lineHeight: CGFloat = 1.3
        static let markFontSize: CGFloat = 50.308
        static let tracking: CGFloat = -0.7188
    }

    typealias MeasureText = (_ text: String, _ fontSize: CGFloat, _ isFirstLine: Bool) -> CGFloat

    let lines: [String]
    let size: CGSize
    let fontSize: CGFloat
    let scale: CGFloat
    let horizontalPadding: CGFloat

    var upperHeight: CGFloat { Metrics.upperHeight * scale }
    var lowerHeight: CGFloat { Metrics.lowerHeight * scale }
    var verticalPadding: CGFloat { Metrics.verticalPadding * scale }
    var lineHeight: CGFloat { fontSize * Metrics.lineHeight }
    var markFontSize: CGFloat { Metrics.markFontSize * scale }
    var tracking: CGFloat { Self.tracking(for: fontSize) }

    static func tracking(for fontSize: CGFloat) -> CGFloat {
        Metrics.tracking * fontSize / Metrics.defaultFontSize
    }

    init(callNumber: BookNavigationArrivalCallNumber, maximumWidth: CGFloat? = nil, measureText: MeasureText) {
        let lines = callNumber.stickerLines
        let padding = Metrics.horizontalPadding
        let available = Metrics.minimumWidth - padding * 2
        func width(at fontSize: CGFloat) -> CGFloat {
            Self.textWidth(lines: lines, fontSize: fontSize, measureText: measureText)
        }
        let selectedFont: CGFloat
        let selectedWidth: CGFloat
        if width(at: Metrics.defaultFontSize) <= available {
            selectedFont = Metrics.defaultFontSize
            selectedWidth = Metrics.minimumWidth
        } else if width(at: Metrics.minimumFontSize) <= available {
            selectedFont = Self.fittingFont(minimum: Metrics.minimumFontSize, maximum: Metrics.defaultFontSize,
                availableWidth: available, textWidth: width)
            selectedWidth = Metrics.minimumWidth
        } else {
            let naturalWidth = ceil(width(at: Metrics.minimumFontSize) + padding * 2)
            let limit = maximumWidth.flatMap { $0.isFinite ? max(Metrics.minimumWidth, $0) : nil }
                ?? naturalWidth
            selectedWidth = min(naturalWidth, limit)
            selectedFont = selectedWidth < naturalWidth
                ? Self.fittingFont(minimum: 0.01, maximum: Metrics.minimumFontSize,
                    availableWidth: selectedWidth - padding * 2, textWidth: width)
                : Metrics.minimumFontSize
        }
        self.init(lines: lines, size: .init(width: selectedWidth, height: Metrics.height),
            fontSize: selectedFont, scale: 1, horizontalPadding: padding)
    }

    func fitted(to size: CGSize, measureText: MeasureText) -> Self {
        let size = CGSize(width: max(1, size.width), height: max(1, size.height))
        let scale = size.height / Metrics.height
        let padding = min(Metrics.horizontalPadding * scale, size.width * 0.1)
        let font = Self.fittingFont(minimum: 0.01, maximum: Metrics.defaultFontSize * scale,
            availableWidth: size.width - padding * 2) { fontSize in
                Self.textWidth(lines: lines, fontSize: fontSize, measureText: measureText)
            }
        return .init(lines: lines, size: size, fontSize: font, scale: scale, horizontalPadding: padding)
    }

    private init(lines: [String], size: CGSize, fontSize: CGFloat, scale: CGFloat, horizontalPadding: CGFloat) {
        self.lines = lines
        self.size = size
        self.fontSize = fontSize
        self.scale = scale
        self.horizontalPadding = horizontalPadding
    }

    private static func textWidth(lines: [String], fontSize: CGFloat, measureText: MeasureText) -> CGFloat {
        lines.enumerated().map { measureText($0.element, fontSize, $0.offset == 0) }.max() ?? 0
    }

    private static func fittingFont(minimum: CGFloat, maximum: CGFloat, availableWidth: CGFloat,
                                   textWidth: (CGFloat) -> CGFloat) -> CGFloat {
        if textWidth(maximum) <= availableWidth { return maximum }
        var lower = minimum, upper = maximum
        for _ in 0..<16 {
            let middle = (lower + upper) / 2
            if textWidth(middle) <= availableWidth { lower = middle } else { upper = middle }
        }
        return lower
    }
}
