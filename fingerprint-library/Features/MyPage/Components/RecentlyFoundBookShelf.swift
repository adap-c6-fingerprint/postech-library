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
    var onTap: (() -> Void)?
    var onSelect: ((Book) -> Void)?

    var size: Size = .card

    struct Size {
        let maxSpineHeight: CGFloat
        let minSpineHeight: CGFloat
        let bookLeadingInset: CGFloat

        static let card = Size(
            maxSpineHeight: 213.84, minSpineHeight: 171,
            bookLeadingInset: 53
        )

        static let large = Size(
            maxSpineHeight: 378.38, minSpineHeight: 304.5,
            bookLeadingInset: 84
        )
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
        }
    }

    private var spineRow: some View {
        let images = loadedImages
        let tallest = images.values.map(\.size.height).max() ?? 0
        let shortest = images.values.map(\.size.height).min() ?? 0
        let hasSameHeights = tallest > 0 && (tallest - shortest) / tallest < 0.02
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

    private var loadedImages: [Book.ID: UIImage] {
        var images: [Book.ID: UIImage] = [:]
        for book in books {
            if case let .loaded(image) = spines[book.id],
               image.size.height > 0, image.size.width / image.size.height < Self.maxSpineAspectRatio {
                images[book.id] = image
            }
        }
        return images
    }

    private func spineFrame(_ book: Book, image: UIImage?, tallest: CGFloat, hasSameHeights: Bool) -> CGSize {
        let fallbackHeight = fallbackHeight(book)
        guard let image else { return placeholderFrame(height: fallbackHeight) }
        let heightRatio = hasSameHeights ? fallbackHeight / size.maxSpineHeight : image.size.height / tallest
        let height = size.maxSpineHeight * heightRatio
        return CGSize(width: height * image.size.width / image.size.height, height: height)
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
    }

    private func placeholderFrame(height: CGFloat) -> CGSize {
        CGSize(width: height * Self.placeholderAspectRatio, height: height)
    }

    private static let maxSpineAspectRatio: CGFloat = 0.3

    private static let placeholderAspectRatio: CGFloat = 188 / 1644

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
    }

    private func placeholderTitle(_ title: String, frame: CGSize) -> some View {
        let length = frame.height * Self.titleLengthRatio
        let thickness = frame.width * Self.titleThicknessRatio
        return Text(Self.spineTitle(title))
            .font(.custom(PobookUI.Typography.bookTitle.fontName, size: thickness * 0.8))
            .foregroundStyle(.black)
            .lineLimit(1)
            .minimumScaleFactor(0.3)
            .frame(width: length, height: thickness, alignment: .leading)
            .rotationEffect(.degrees(90))
            .frame(width: frame.width, height: length)
    }

    private static let titleTopInsetRatio: CGFloat = 0.05
    private static let titleLengthRatio: CGFloat = 0.78
    private static let titleThicknessRatio: CGFloat = 0.7

    private static let maxTitleBytes = 50

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
        return kept.trimmingCharacters(in: .whitespaces) + "..."
    }

    private func fallbackHeight(_ book: Book) -> CGFloat {
        let seed = book.id.unicodeScalars.reduce(UInt64(5381)) { ($0 &* 33) &+ UInt64($1.value) }
        let heightRatio = CGFloat((seed / 100) % 100) / 99
        return size.minSpineHeight + (size.maxSpineHeight - size.minSpineHeight) * heightRatio
    }
}
