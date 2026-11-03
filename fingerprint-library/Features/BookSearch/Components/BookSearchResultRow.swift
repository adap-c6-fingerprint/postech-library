//
//  BookSearchResultRow.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/17/26.
//

import SwiftUI

struct BookSearchResultRow: View {
    let book: Book
    let libraryInfo: BookCardLibraryInfo?
    let onShowDetail: () -> Void

    private let coverHeight: CGFloat = 111

    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            BookCoverView(url: book.imageURL, isbn: book.isbn, onOpen: onShowDetail)
                .frame(width: 78, height: coverHeight)
                .background(.white.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 8))

            Button(action: onShowDetail) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(BookText.plainText(book.title))
                        .typography(.bookTitle)
                        .foregroundStyle(.white)
                        .lineLimit(2)

                    Text(BookText.plainText(locationText))
                        .typography(.body2)
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Text(BookText.plainText(book.author))
                        .typography(.caption2)
                        .foregroundStyle(.white.opacity(0.65))
                        .lineLimit(1)

                    Spacer(minLength: 8)

                    availabilityText
                        .typography(.caption2)
                }
                .frame(maxWidth: .infinity, minHeight: coverHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("책 소개 보기")
        }
        .padding(16)
    }

    private var locationText: String {
        libraryInfo?.location ?? book.subLocation ?? "위치 정보 없음"
    }

    @ViewBuilder
    private var availabilityText: some View {
        switch libraryInfo?.availability {
        case .available:
            Text("대출 가능").foregroundStyle(.green)
        case .unavailable:
            Text("이용 불가").foregroundStyle(.red)
        case .unknown, .none:
            Text("대출 상태 확인 필요").foregroundStyle(.white.opacity(0.65))
        }
    }
}
