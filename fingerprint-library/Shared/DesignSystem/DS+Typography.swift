//
//  DS+Typography.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/2/26.
//

import SwiftUI
import UIKit

/// 사용법 예시
/// Text("도서 제목")
///    .typography(.bookTitle)
///    .foregroundStyle(DS.text.primary)

extension DS {
    enum FontFamily {
        static let Pretendard = "Pretendard"
    }

    enum FontStyle {
        static let Regular = "Regular"
        static let Medium = "Medium"
        static let SemiBold = "SemiBold"
        static let Bold = "Bold"
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
        let style: String
        let size: CGFloat
        let lineHeight: CGFloat
        let letterSpacing: CGFloat

        var fontName: String { "\(FontFamily.Pretendard)-\(style)" }

        static let largeTitle = Typography(style: FontStyle.SemiBold, size: FontSize._32, lineHeight: LineHeight._32, letterSpacing: LetterSpacing._32)
        static let title1 = Typography(style: FontStyle.SemiBold, size: FontSize._24, lineHeight: LineHeight._24, letterSpacing: LetterSpacing._24)
        static let title2 = Typography(style: FontStyle.SemiBold, size: FontSize._20, lineHeight: LineHeight._20, letterSpacing: LetterSpacing._20)
        static let bookTitle = Typography(style: FontStyle.SemiBold, size: FontSize._18, lineHeight: LineHeight._18, letterSpacing: LetterSpacing._18)
        static let body1 = Typography(style: FontStyle.Medium, size: FontSize._18, lineHeight: LineHeight._18, letterSpacing: LetterSpacing._18)
        static let body2 = Typography(style: FontStyle.Medium, size: FontSize._16, lineHeight: LineHeight._16, letterSpacing: LetterSpacing._16)
        static let caption1 = Typography(style: FontStyle.Regular, size: FontSize._14, lineHeight: LineHeight._14, letterSpacing: LetterSpacing._14)
        static let caption2 = Typography(style: FontStyle.Regular, size: FontSize._12, lineHeight: LineHeight._12, letterSpacing: LetterSpacing._12)
    }
}

extension View {
    func typography(_ typography: DS.Typography) -> some View {
        let fontLineHeight = UIFont(name: typography.fontName, size: typography.size)?.lineHeight ?? typography.lineHeight
        let extraSpacing = max(typography.lineHeight - fontLineHeight, 0)

        return self
            .font(.custom(typography.fontName, fixedSize: typography.size))
            .tracking(typography.letterSpacing)
            .lineSpacing(extraSpacing)
            .padding(.vertical, extraSpacing / 2)
    }
}
