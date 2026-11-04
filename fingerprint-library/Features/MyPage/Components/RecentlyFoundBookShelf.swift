//
//  RecentlyFoundBookShelf.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  최근 찾은 책의 책등을 왼쪽부터 꽂아 보여주는 책장
//  마이페이지 카드는 스크롤하지 않고, 최근 찾은 책 화면은 좌우로 넘길 수 있다.
//  선반은 홈 추천 캐러셀과 같은 RecommendationShelfView(RecommendationGlass·Bolt 에셋)를 쓴다.
//

import SwiftUI
import UIKit

struct RecentlyFoundBookShelf: View {
    let books: [Book]
    let spines: [Book.ID: RecentlyFoundBookFeature.SpinePhase]
    var isScrollable = false
    // false면 화면을 넘는 책은 오른쪽 화면 밖으로 밀려나 보이지 않는다. (피그마 주석: 좌우 넘김 없음)
    var onTap: (() -> Void)?
    // 피그마 주석: 마이페이지에서는 책·선반 어디를 눌러도 최근 찾은 책 화면으로 간다.
    var onSelect: ((Book) -> Void)?
    // 최근 찾은 책 화면에서는 책등 하나하나를 눌러 그 책의 상세로 간다.

    var size: Size = .card
    // 마이페이지 카드와 최근 찾은 책 화면은 같은 모양의 책장을 서로 다른 크기로 그린다.

    /// 피그마(iPhone 17 기준)에서 잰 화면별 책장 크기
    struct Size {
        let maxSpineHeight: CGFloat
        // 피그마 주석: 각 책의 최대 높이
        let minSpineHeight: CGFloat
        let shelfHeight: CGFloat
        // Recommendation Glass Overlay_Large 높이
        let bookLeadingInset: CGFloat
        // 책 묶음 시작 x. 선반 시작 x는 두 화면 모두 RecommendationShelfView.leadingInset(16)
        let fallbackWidths: ClosedRange<CGFloat>
        // 책등 이미지가 없을 때 쓰는 막대 너비 범위

        static let card = Size(
            maxSpineHeight: 213.84, minSpineHeight: 171, shelfHeight: 97.81,
            bookLeadingInset: 53, fallbackWidths: 18...34
        )
        // 피그마 09.마이페이지 (3478:26915)

        static let large = Size(
            maxSpineHeight: 378.38, minSpineHeight: 304.5, shelfHeight: 155.46,
            bookLeadingInset: 84, fallbackWidths: 32...60
        )
        // 피그마 09.마이페이지_최근 찾은 목록 (3499:27619)
        // 피그마 프레임이 이미 넘긴 상태라 첫 책 시작 x는 카드 값(53)을 선반 배율(155.46 ÷ 97.81 ≈ 1.59)로 키운 값
        // 막대 너비는 책 배율(378.38 ÷ 213.84 ≈ 1.77)로 키운 값
    }

    var body: some View {
        shelf
            .frame(height: size.maxSpineHeight)
            .overlay(alignment: .bottomLeading) {
                RecommendationShelfView(height: size.shelfHeight)
                    .padding(.leading, RecommendationShelfView.leadingInset)
            }
            .coordinateSpace(.named(RecommendationShelfView.carouselSpace))
            .modifier(WholeShelfTap(action: onTap))
    }

    /// onTap이 있을 때만 책장 전체를 하나의 버튼처럼 만든다. 없으면 책등 버튼과 스크롤을 막지 않는다.
    private struct WholeShelfTap: ViewModifier {
        let action: (() -> Void)?

        func body(content: Content) -> some View {
            if let action {
                content
                    .contentShape(.rect)
                    .onTapGesture(perform: action)
                    .accessibilityAddTraits(.isButton)
            } else {
                content
            }
        }
    }

    @ViewBuilder
    private var shelf: some View {
        if isScrollable {
            ScrollView(.horizontal) {
                spineRow
            }
            .contentMargins(.leading, size.bookLeadingInset, for: .scrollContent)
            .contentMargins(.trailing, RecommendationShelfView.leadingInset, for: .scrollContent)
            .scrollIndicators(.hidden)
        } else {
            spineRow
                .fixedSize(horizontal: true, vertical: false)
                .padding(.leading, size.bookLeadingInset)
                .frame(maxWidth: .infinity, alignment: .leading)
                .clipped()
            // 책등 줄의 원래 폭을 유지한 채 왼쪽에 붙이고, 화면 밖으로 나간 부분은 잘라 낸다.
        }
    }

    private var spineRow: some View {
        let images = loadedImages
        let tallest = images.values.map(\.size.height).max() ?? 0
        let shortest = images.values.map(\.size.height).min() ?? 0
        let hasSameHeights = tallest > 0 && (tallest - shortest) / tallest < 0.02
        // Yes24 책등 이미지가 모두 같은 높이로 오면 원본 비율만으로는 높이 차이가 생기지 않는다.
        return HStack(alignment: .bottom, spacing: 0) {
            ForEach(books) { book in
                selectable(book) {
                    spine(book, image: images[book.id], tallest: tallest, hasSameHeights: hasSameHeights)
                        .modifier(RecommendationShelfView.CoverBlur(height: size.shelfHeight))
                    // 홈 추천 표지처럼 선반 유리 뒤에 들어간 부분만 흐리게 보인다.
                }
            }
        }
        .frame(height: size.maxSpineHeight, alignment: .bottom)
    }

    @ViewBuilder
    private func selectable<Content: View>(_ book: Book, @ViewBuilder content: () -> Content) -> some View {
        if let onSelect {
            Button { onSelect(book) } label: { content() }
                .buttonStyle(.plain)
                .accessibilityHint("책 상세 보기")
        } else {
            content()
        }
    }

    /// 받은 책등 PNG를 UIImage로 바꾼다. 높이를 서로 비교해야 하므로 한 번에 모아 둔다.
    private var loadedImages: [Book.ID: UIImage] {
        var images: [Book.ID: UIImage] = [:]
        for book in books {
            if case let .loaded(data) = spines[book.id], let image = UIImage(data: data), image.size.height > 0 {
                images[book.id] = image
            }
        }
        return images
    }

    @ViewBuilder
    private func spine(_ book: Book, image: UIImage?, tallest: CGFloat, hasSameHeights: Bool) -> some View {
        let bar = fallbackSize(book)
        switch spines[book.id] ?? .loading {
        case .loaded:
            if let image {
                let heightRatio = hasSameHeights ? bar.height / size.maxSpineHeight : image.size.height / tallest
                let height = size.maxSpineHeight * heightRatio
                Image(uiImage: image)
                    .resizable()
                    .frame(width: height * image.size.width / image.size.height, height: height)
                    .accessibilityLabel(book.title)
                // 피그마 주석: 가장 큰 책이 최대 높이(카드 213.84, 큰 책장 378.38)가 되도록 모든 책을 같은 배율로 줄이고, 너비는 원본 비율을 지킨다.
                // 원본 높이가 모두 같으면 책마다 정해 둔 높이(최소~최대 높이 사이)로 줄여 윗면이 일자가 되지 않게 한다.
            } else {
                titleSpine(book, bar: bar)
            }
        case .loading:
            Rectangle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: bar.width, height: bar.height)
                .accessibilityLabel("책등 불러오는 중")
        case .unavailable:
            titleSpine(book, bar: bar)
        }
    }

    private func titleSpine(_ book: Book, bar: CGSize) -> some View {
        Text(book.title)
            .typography(.caption2)
            .foregroundStyle(Color.backgroundDefault)
            .lineLimit(1)
            .frame(width: bar.height - 16)
            .rotationEffect(.degrees(90))
            .frame(width: bar.width, height: bar.height)
            .background(Color.limeDark)
            .accessibilityLabel(book.title)
        // 책등 이미지가 없으면 LimeDark 막대에 제목만 세로로 적는다.
    }

    /// 이미지가 없는 막대는 크기가 모두 같으면 직사각형으로 보이므로, 책마다 다른 크기를 준다.
    /// 피그마 주석: 너비가 같다면 책마다 줄이거나 키워 전체가 직사각형이 되지 않게 한다.
    private func fallbackSize(_ book: Book) -> CGSize {
        let seed = book.id.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        // String.hashValue는 실행마다 바뀌므로, 같은 책이 늘 같은 크기가 되도록 직접 계산한다.
        let widthRatio = CGFloat(seed % 100) / 99
        let heightRatio = CGFloat((seed / 100) % 100) / 99
        let widths = size.fallbackWidths
        return CGSize(
            width: widths.lowerBound + (widths.upperBound - widths.lowerBound) * widthRatio,
            height: size.minSpineHeight + (size.maxSpineHeight - size.minSpineHeight) * heightRatio
        )
    }
}
