//
//  DesignSystemColor.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/7/26.
//

import SwiftUI

/// 사용법 예시
/// Text("도서 제목")
///    .foregroundStyle(DS.ColorToken.neutralPrimary)
/// RoundedRectangle(cornerRadius: DS.Radius.button)
///    .fill(DS.ColorToken.Button.primaryBackground)

extension DS {
    /// Figma 「Color / Primitive Token」 컬렉션
    enum ColorPrimitive {
        enum Grayscale {
            static let _0 = SwiftUI.Color(hex: 0xFFFFFF)
            static let _25 = SwiftUI.Color(hex: 0xF9F9F9)
            static let _50 = SwiftUI.Color(hex: 0xF3F3F3)
            static let _100 = SwiftUI.Color(hex: 0xE7E7E7)
            static let _200 = SwiftUI.Color(hex: 0xDBDBDB)
            static let _250 = SwiftUI.Color(hex: 0xD9D9D9)
            static let _300 = SwiftUI.Color(hex: 0xB6B6B6)
            static let _400 = SwiftUI.Color(hex: 0x999999)
            static let _500 = SwiftUI.Color(hex: 0x777777)
            static let _600 = SwiftUI.Color(hex: 0x555555)
            static let _700 = SwiftUI.Color(hex: 0x333333)
            static let _800 = SwiftUI.Color(hex: 0x2B2B2B)
            static let _900 = SwiftUI.Color(hex: 0x242424)
            static let _1000 = SwiftUI.Color(hex: 0x1D1D1D)
            static let _1100 = SwiftUI.Color(hex: 0x121212)
            static let black = SwiftUI.Color(hex: 0x000000)
        }

        enum Primary {
            static let _100 = SwiftUI.Color(hex: 0xF7FDCE)
            static let _200 = SwiftUI.Color(hex: 0xEEFA9E)
            static let _300 = SwiftUI.Color(hex: 0xE6F86D)
            static let _500 = SwiftUI.Color(hex: 0xDDF53C)
            static let _600 = SwiftUI.Color(hex: 0xC5E300)
            static let _700 = SwiftUI.Color(hex: 0xBBCE3A)
            static let _800 = SwiftUI.Color(hex: 0x99A738)
            static let _900 = SwiftUI.Color(hex: 0x778137)
        }
    }

    /// Figma 「Color / Semantic & Component Token」 컬렉션
    /// Figma에서 다른 변수를 참조(alias)하는 토큰은 같은 참조로 옮겼다.
    enum ColorToken {
        private typealias Gray = ColorPrimitive.Grayscale
        private typealias Primary = ColorPrimitive.Primary

        static let neutralDark = Gray._1100
        static let neutralPrimary = Gray._25
        static let neutralSecondary = Gray._50
        static let neutralTertiary = Gray._250
        static let primaryLight = Primary._500
        static let primaryDark = Primary._600
        static let glassBackground = Gray._400.opacity(0.17)
        // 외부 Color Scheme 참조는 전달받은 Default 모드의 색상 값으로 반영한다.
        static let textAvailable = SwiftUI.Color(hex: 0x34C759)
        static let textUnavailable = SwiftUI.Color(hex: 0xFF383C)

        enum Tabbar {
            static let pressedBackground = ColorToken.neutralDark
            static let darkOverlay = Gray.black
        }

        enum BookDetails {
            static let background = Gray._900.opacity(0.8)
            static let textPlace = Gray._100
            static let textDistance = Gray._200
            static let textAuthor = ColorToken.neutralTertiary
            static let textStory = Gray._300
        }

        enum MapIndicator {
            static let text = ColorToken.neutralTertiary
        }

        enum Button {
            static let primaryBackground = ColorToken.primaryLight
            static let primaryText = Gray._800
            static let primaryBacking = Gray._0
            static let neutralBackground = Gray._700
            static let neutralText = ColorToken.neutralPrimary
            static let neutralBacking = ColorToken.neutralSecondary
            static let neutralShadow = Gray._400.opacity(0.17)
            static let effectDark = Gray._900
            static let effectLight = Gray._100
        }

        enum BookSelection {
            static let itemBackground = Gray._800
            static let itemTextAuthor = ColorToken.neutralTertiary
            static let itemBorder = Gray._600
            static let checkboxItemBorder = Gray._300
        }

        enum Chip {
            static let neutralBackground = Gray._900
        }

        enum Pin {
            static let startBackgroundFill = SwiftUI.Color(hex: 0x08C66A)
            static let startStroke = SwiftUI.Color(hex: 0x087F4A)
            static let endBackgroundFill = SwiftUI.Color(hex: 0xC83434)
            static let endStroke = SwiftUI.Color(hex: 0x7D2121)
            static let text = Gray._0
        }

        enum CurrentLocation {
            static let circleFill = ColorToken.primaryLight
            static let circleStroke = ColorToken.primaryDark
            static let circleBackshadow = Primary._700.opacity(0.3)
        }

        static let recommendationBackground = Primary._600.opacity(0.6)
    }
}

extension SwiftUI.Color {
    /// 0xRRGGBB 형식의 sRGB 색
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
