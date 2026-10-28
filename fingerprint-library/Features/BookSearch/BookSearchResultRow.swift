//
//  BookSearchResultRow.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/17/26.
//

import SwiftUI

struct BookSearchResultRow: View {
    let book: Book
    let isFavorite: Bool
    let onShowDetail: () -> Void
    let onToggleFavorite: () -> Void
    let onAddToBasket: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                coverImage
                Button(action: onShowDetail) {
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(cleaned(book.title))
                                .font(.headline)
                                .foregroundStyle(.primary)
                                .lineLimit(3)

                            Text(cleaned(book.author))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)

                            if !publicationInfo.isEmpty {
                                Text(publicationInfo)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("책 소개 보기")
            }

            actionButtons
        }
        .padding(16)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color.gray.opacity(0.15))
        }
    }

    private var actionButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                favoriteButton
                basketButton
                directionsButton
            }
            .fixedSize(horizontal: true, vertical: false)

            // 큰 글자나 좁은 화면에서는 버튼을 세로로 배치한다.
            VStack(alignment: .trailing, spacing: 6) {
                favoriteButton
                basketButton
                directionsButton
            }
        }
        .font(.caption)
        .controlSize(.small)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private var favoriteButton: some View {
        Button(action: onToggleFavorite) {
            Image(systemName: isFavorite ? "heart.fill" : "heart")
                .frame(minWidth: 28, minHeight: 32)
        }
        .buttonStyle(.bordered)
        .tint(isFavorite ? .red : .primary)
        .accessibilityLabel(isFavorite ? "찜 해제" : "찜하기")
        .accessibilityValue(isFavorite ? "찜됨" : "찜 안 됨")
        .accessibilityIdentifier("book-favorite-\(book.id)")
    }

    private var basketButton: some View {
        Button(action: onAddToBasket) {
            Text("책바구니 담기")
                .frame(minHeight: 32)
        }
        .buttonStyle(.borderedProminent)
    }

    private var directionsButton: some View {
        Button(action: {}) {
            Text("길안내 받기")
                .frame(minHeight: 32)
        }
        .buttonStyle(.bordered)
    }

    private var coverImage: some View {
        // 상세 이동 버튼 안에 재시도 버튼을 중첩하지 않는다.
        BookCoverView(url: book.imageURL, onOpen: onShowDetail)
        .frame(width: 72, height: 104)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var publicationInfo: String {
        let values = [book.publisher, book.publicationYear]

        return values.compactMap { value -> String? in
            guard let value else {
                return nil
            }

            let text = cleaned(value)
            return text.isEmpty ? nil : text
        }
        .joined(separator: " · ")
    }

    private func cleaned(_ text: String) -> String {
        BookText.plainText(text)
    }
}
