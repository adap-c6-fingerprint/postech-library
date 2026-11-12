//
//  RecentlyFoundBookShelf.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  최근 찾은 책의 책등을 왼쪽부터 꽂아 보여주는 책장
//  마이페이지 카드는 스크롤하지 않고, 최근 찾은 책 화면은 좌우로 넘길 수 있다.
//  선반은 홈 추천 캐러셀과 같은 얇은 선반(RecommendationShelfView.thin)을 쓴다.
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
        let bookLeadingInset: CGFloat
        // 책 묶음 시작 x. 선반 시작 x는 두 화면 모두 RecommendationShelfView.leadingInset(16)

        static let card = Size(
            maxSpineHeight: 213.84, minSpineHeight: 171,
            bookLeadingInset: 53
        )
        // 피그마 09.마이페이지 (3478:26915)

        static let large = Size(
            maxSpineHeight: 378.38, minSpineHeight: 304.5,
            bookLeadingInset: 84
        )
        // 피그마 09.마이페이지_최근 찾은 목록 (3499:27619)
        // 피그마 프레임이 이미 넘긴 상태라 첫 책 시작 x는 카드 값(53)을 선반 배율(155.46 ÷ 97.81 ≈ 1.59)로 키운 값
    }

    var body: some View {
        shelf
            .frame(height: size.maxSpineHeight)
            .overlay(alignment: .bottomLeading) {
                RecommendationShelfView.thin()
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
                let frame = spineFrame(book, image: images[book.id], tallest: tallest, hasSameHeights: hasSameHeights)
                selectable(book) {
                    spine(book, image: images[book.id], frame: frame)
                        .modifier(RecommendationShelfView.CoverBlur(
                            height: RecommendationShelfView.thinHeight,
                            cornerRadius: RecommendationShelfView.recommendationCornerRadius
                        ))
                        .frame(width: frame.width, height: frame.height)
                    // 홈 추천 표지처럼 선반 유리 뒤에 들어간 부분만 흐리게 보인다.
                    // CoverBlur는 안쪽에서 GeometryReader를 쓰므로, 바깥에서 책 크기를 정해 주지 않으면
                    // HStack이 모든 책에 같은 너비를 나눠 줘 두꺼운 책이 잘리고 옆 책과 겹친다. (홈 추천 표지도 바깥에서 크기를 준다)
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

    /// 책등 사진으로 그릴 이미지만 모은다. 높이를 서로 비교해야 하므로 한 번에 모아 둔다.
    private var loadedImages: [Book.ID: UIImage] {
        var images: [Book.ID: UIImage] = [:]
        for book in books {
            if case let .loaded(image) = spines[book.id],
               image.size.height > 0, image.size.width / image.size.height < Self.maxSpineAspectRatio {
                images[book.id] = image
            }
            // Yes24는 책등이 없을 때 빈 값 대신 표지 모양의 "이미지 준비중" 그림을 준다.
            // 진짜 책등은 세로로 길쭉하므로, 길쭉하지 않은 그림은 책등이 없는 책으로 보고 플레이스홀더로 그린다.
        }
        return images
    }

    /// 책 한 권이 차지할 크기
    private func spineFrame(_ book: Book, image: UIImage?, tallest: CGFloat, hasSameHeights: Bool) -> CGSize {
        let fallbackHeight = fallbackHeight(book)
        guard let image else { return placeholderFrame(height: fallbackHeight) }
        // 불러오는 중·책등 없음·이미지로 바꾸지 못한 경우는 모두 대체 에셋 크기를 쓴다.
        let heightRatio = hasSameHeights ? fallbackHeight / size.maxSpineHeight : image.size.height / tallest
        let height = size.maxSpineHeight * heightRatio
        return CGSize(width: height * image.size.width / image.size.height, height: height)
        // 피그마 주석: 가장 큰 책이 최대 높이(카드 213.84, 큰 책장 378.38)가 되도록 모든 책을 같은 배율로 줄이고, 너비는 원본 비율을 지킨다.
        // 원본 높이가 모두 같으면 책마다 정해 둔 높이(최소~최대 높이 사이)로 줄여 윗면이 일자가 되지 않게 한다.
    }

    @ViewBuilder
    private func spine(_ book: Book, image: UIImage?, frame: CGSize) -> some View {
        if let image {
            Image(uiImage: image)
                .resizable()
                .frame(width: frame.width, height: frame.height)
                .accessibilityLabel(book.title)
        } else {
            placeholderSpine(book, frame: frame)
        }
        // 불러오는 중·책등 없음·이미지로 바꾸지 못한 경우 모두 recentlyFoundBookPlaceHolder 에셋 위에 제목을 얹어 그린다.
        // image는 loadedImages에서 .loaded이고 책등 비율인 경우에만 들어온다.
    }

    /// recentlyFoundBookPlaceHolder 에셋을 원본 비율 그대로 주어진 높이에 맞춘 크기
    private func placeholderFrame(height: CGFloat) -> CGSize {
        CGSize(width: height * Self.placeholderAspectRatio, height: height)
        // 에셋 아래쪽 로고가 찌그러지지 않도록 너비는 비율로 정한다.
        // 높이는 책마다 다르게 둬 책등이 없는 책이 여러 권이어도 윗면이 일자가 되지 않는다.
    }

    private static let maxSpineAspectRatio: CGFloat = 0.3
    // 책등으로 인정하는 최대 가로÷세로 비율. 실제 책등은 대략 0.05~0.25이고, Yes24 "이미지 준비중" 그림은 표지처럼 세로로 조금 긴 모양(약 0.5~0.7)이다.

    private static let placeholderAspectRatio: CGFloat = 188 / 1644
    // recentlyFoundBookPlaceHolder.png 원본 크기(가로 188 × 세로 1644 px)

    private func placeholderSpine(_ book: Book, frame: CGSize) -> some View {
        Image(.recentlyFoundBookPlaceHolder)
            .resizable()
            .frame(width: frame.width, height: frame.height)
            .overlay(alignment: .top) {
                placeholderTitle(book.title, frame: frame)
                    .padding(.top, frame.height * Self.titleTopInsetRatio)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(book.title)
        // 책등 이미지가 없으면 글자 없는 recentlyFoundBookPlaceHolder 에셋 위에 제목을 얹어 그린다.
        // 마이페이지(이 책장) 전용이다. 책찾기 화면 등 다른 곳은 그대로 bookSpinePlaceHolder로 폴백한다.
    }

    /// 플레이스홀더 책등을 따라 세로로 흐르는 검은 제목. 다른 서지정보는 넣지 않는다.
    private func placeholderTitle(_ title: String, frame: CGSize) -> some View {
        let length = frame.height * Self.titleLengthRatio
        let thickness = frame.width * Self.titleThicknessRatio
        return Text(Self.spineTitle(title))
            .font(.custom(PobookUI.Typography.bookTitle.fontName, size: thickness * 0.8))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            // 긴 제목은 한 줄에 들어가도록 글씨를 줄인다.
            .frame(width: length, height: thickness, alignment: .leading)
            .rotationEffect(.degrees(90))
            // 가로로 쓴 제목을 시계 방향으로 90도 돌려 책등 위에서 아래로 읽히게 한다. 줄의 시작이 책등 위쪽에 온다.
            .frame(width: frame.width, height: length)
            // rotationEffect는 레이아웃 크기를 바꾸지 않으므로, 돌린 뒤의 모양(책등 너비 × 제목 길이)으로 다시 감싼다.
    }

    private static let titleTopInsetRatio: CGFloat = 0.05
    // 책등 맨 위에서 제목 시작까지 (높이 대비)
    private static let titleLengthRatio: CGFloat = 0.78
    // 제목이 차지할 수 있는 길이 (높이 대비). 에셋 아래쪽 약 15%(1400~1560px)에 있는 로고를 덮지 않는다.
    private static let titleThicknessRatio: CGFloat = 0.7
    // 제목 글씨 줄의 굵기 (책등 너비 대비)

    private static let maxTitleBytes = 50

    /// 제목이 50바이트(UTF-8, 한글 1자 = 3바이트)를 넘으면 50바이트 안에 드는 글자까지만 남기고 "..."을 붙인다.
    static func spineTitle(_ title: String) -> String {
        guard title.utf8.count > maxTitleBytes else { return title }
        var kept = ""
        var bytes = 0
        for character in title {
            let size = String(character).utf8.count
            guard bytes + size <= maxTitleBytes else { break }
            kept.append(character)
            bytes += size
        }
        // 글자(Character) 단위로 자르므로 한글·이모지가 반쪽으로 깨지지 않는다.
        return kept.trimmingCharacters(in: .whitespaces) + "..."
    }

    /// 대체 에셋은 높이가 모두 같으면 윗면이 일자로 보이므로, 책마다 다른 높이를 준다.
    /// 피그마 주석: 너비가 같다면 책마다 줄이거나 키워 전체가 직사각형이 되지 않게 한다.
    private func fallbackHeight(_ book: Book) -> CGFloat {
        let seed = book.id.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        // String.hashValue는 실행마다 바뀌므로, 같은 책이 늘 같은 높이가 되도록 직접 계산한다.
        let heightRatio = CGFloat((seed / 100) % 100) / 99
        return size.minSpineHeight + (size.maxSpineHeight - size.minSpineHeight) * heightRatio
        // 너비는 placeholderFrame이 에셋 비율로 정한다.
    }
}
