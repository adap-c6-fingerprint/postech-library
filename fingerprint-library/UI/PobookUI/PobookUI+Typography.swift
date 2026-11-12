//
//  PobookUI+Typography.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/2/26.
//

import SwiftUI
import UIKit

extension PobookUI {
    // Figma 「Typography / Foundation」 Default 모드의 폰트 값.
    enum FontFamily {
        static let Pretendard = "Pretendard"
    }

    enum FontStyle: String, CaseIterable {
        case regular = "Regular"
        case medium = "Medium"
        case semibold = "SemiBold"
        case bold = "Bold"

        var systemWeight: UIFont.Weight {
            switch self {
            case .regular: .regular
            case .medium: .medium
            case .semibold: .semibold
            case .bold: .bold
            }
        }
    }

    enum FontSize {
        static let _32: CGFloat = 32
        static let _24: CGFloat = 24
        static let _20: CGFloat = 20
        static let _18: CGFloat = 18
        static let _16: CGFloat = 16
        static let _14: CGFloat = 14
        static let _12: CGFloat = 12
    }

    enum LineHeight {
        static let _32: CGFloat = 45
        static let _28: CGFloat = 39.2
        static let _24: CGFloat = 34
        static let _20: CGFloat = 28
        static let _18: CGFloat = 25
        static let _16: CGFloat = 22.4
        static let _14: CGFloat = 19.6
        static let _12: CGFloat = 16.8
    }

    enum LetterSpacing {
        static let _32: CGFloat = -0.64
        static let _28: CGFloat = -0.56
        static let _24: CGFloat = -0.48
        static let _20: CGFloat = -0.4
        static let _18: CGFloat = -0.36
        static let _16: CGFloat = -0.32
        static let _14: CGFloat = -0.28
        static let _12: CGFloat = -0.24
    }

    struct Typography {
        enum Scaling {
            case dynamic
            /// 지도·책등 번호표처럼 그래픽 좌표에 맞춰 그려야 하는 텍스트에만 사용한다.
            case fixed
        }

        let style: FontStyle
        let size: CGFloat
        let lineHeight: CGFloat
        let letterSpacing: CGFloat
        let relativeTo: UIFont.TextStyle

        var fontName: String { "\(FontFamily.Pretendard)-\(style.rawValue)" }

        static let largeTitle = Self(style: .semibold, size: FontSize._32,
            lineHeight: LineHeight._32, letterSpacing: LetterSpacing._32, relativeTo: .largeTitle)
        static let title1 = Self(style: .semibold, size: FontSize._24,
            lineHeight: LineHeight._24, letterSpacing: LetterSpacing._24, relativeTo: .title1)
        static let title2 = Self(style: .semibold, size: FontSize._20,
            lineHeight: LineHeight._20, letterSpacing: LetterSpacing._20, relativeTo: .title2)
        static let bookTitle = Self(style: .semibold, size: FontSize._18,
            lineHeight: LineHeight._18, letterSpacing: LetterSpacing._18, relativeTo: .headline)
        static let body1 = Self(style: .medium, size: FontSize._18,
            lineHeight: LineHeight._18, letterSpacing: LetterSpacing._18, relativeTo: .body)
        static let body2 = Self(style: .medium, size: FontSize._16,
            lineHeight: LineHeight._16, letterSpacing: LetterSpacing._16, relativeTo: .body)
        static let caption1 = Self(style: .regular, size: FontSize._14,
            lineHeight: LineHeight._14, letterSpacing: LetterSpacing._14, relativeTo: .footnote)
        static let caption2 = Self(style: .regular, size: FontSize._12,
            lineHeight: LineHeight._12, letterSpacing: LetterSpacing._12, relativeTo: .caption1)

        /// 도서명이 아닌 버튼 문구에는 용도가 드러나는 이름을 사용한다.
        static let button = bookTitle
        static let buttonSmall = body2
        static let shelfHeading = Self(style: .medium, size: FontSize._20,
            lineHeight: LineHeight._20, letterSpacing: LetterSpacing._20, relativeTo: .title3)

        func weight(_ style: FontStyle) -> Self {
            Self(style: style, size: size, lineHeight: lineHeight,
                 letterSpacing: letterSpacing, relativeTo: relativeTo)
        }

        struct Metrics {
            let font: UIFont
            let lineHeight: CGFloat
            let letterSpacing: CGFloat

            var lineSpacing: CGFloat { max(lineHeight - font.lineHeight, 0) }
            /// 외부 여백이 아니라 디자인 행 높이를 맞추는 글자 위·아래의 여유 공간이다.
            var halfLeading: CGFloat { lineSpacing / 2 }
        }

        @MainActor
        func metrics(for dynamicTypeSize: DynamicTypeSize, scaling: Scaling = .dynamic) -> Metrics {
            let baseFont = UIFont(name: fontName, size: size)
                ?? UIFont.systemFont(ofSize: size, weight: style.systemWeight)
            let font: UIFont
            switch scaling {
            case .dynamic:
                let traits = UITraitCollection(preferredContentSizeCategory: dynamicTypeSize.contentSizeCategory)
                font = UIFontMetrics(forTextStyle: relativeTo).scaledFont(for: baseFont, compatibleWith: traits)
            case .fixed:
                font = baseFont
            }
            let scale = font.pointSize / size
            return Metrics(font: font, lineHeight: lineHeight * scale, letterSpacing: letterSpacing * scale)
        }

        /// Text 보간처럼 View modifier를 적용할 수 없는 인라인 강조에도 같은 확대 기준을 쓴다.
        @MainActor
        func font(for dynamicTypeSize: DynamicTypeSize, scaling: Scaling = .dynamic) -> Font {
            Font(metrics(for: dynamicTypeSize, scaling: scaling).font)
        }
    }
}

extension View {
    /// 기본값은 Dynamic Type. 화면 간격은 호출부의 spacing/padding으로 별도 지정한다.
    func typography(_ typography: PobookUI.Typography, scaling: PobookUI.Typography.Scaling = .dynamic) -> some View {
        modifier(TypographyModifier(typography: typography, scaling: scaling))
    }
}

private struct TypographyModifier: ViewModifier {
    let typography: PobookUI.Typography
    let scaling: PobookUI.Typography.Scaling
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let metrics = typography.metrics(for: dynamicTypeSize, scaling: scaling)
        content
            .font(Font(metrics.font))
            .tracking(metrics.letterSpacing)
            .lineSpacing(metrics.lineSpacing)
            .padding(.vertical, metrics.halfLeading)
    }
}

private extension DynamicTypeSize {
    var contentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: .extraSmall
        case .small: .small
        case .medium: .medium
        case .large: .large
        case .xLarge: .extraLarge
        case .xxLarge: .extraExtraLarge
        case .xxxLarge: .extraExtraExtraLarge
        case .accessibility1: .accessibilityMedium
        case .accessibility2: .accessibilityLarge
        case .accessibility3: .accessibilityExtraLarge
        case .accessibility4: .accessibilityExtraExtraLarge
        case .accessibility5: .accessibilityExtraExtraExtraLarge
        @unknown default: .large
        }
    }
}
