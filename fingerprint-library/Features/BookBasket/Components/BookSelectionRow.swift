//
//  BookSelectionRow.swift
//  fingerprint-library
//

import SwiftUI

// 피그마 Book_Long Version_CartVer: 장바구니·찜 목록에서 책을 고르는 행
struct BookSelectionRow: View {
    let book: Book
    let location: String?
    let availability: BookCardLibraryInfo.Availability?
    let isSelected: Bool
    let onToggle: () -> Void
    var onShowDetail: (() -> Void)? = nil

    var body: some View {
        Group {
            if onShowDetail != nil {
                rowContent
            } else {
                Button(action: onToggle) {
                    rowContent
                }
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            }
        }
        .buttonStyle(.plain)
    }

    private var rowContent: some View {
        HStack(spacing: 16) {
            if onShowDetail != nil {
                Button(action: onToggle) {
                    selectionMark
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("\(BookText.plainText(book.title)) 선택")
                .accessibilityAddTraits(isSelected ? .isSelected : [])
            } else {
                selectionMark
            }

            HStack(alignment: .top, spacing: 20) {
                if let onShowDetail {
                    Button(action: onShowDetail) {
                        bookCover
                    }
                    .accessibilityLabel("\(BookText.plainText(book.title)) 상세 보기")
                    .accessibilityIdentifier("basket-book-detail-\(book.id)")

                    Button(action: onToggle) {
                        bookInformation
                            .contentShape(Rectangle())
                    }
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                } else {
                    bookCover
                    bookInformation
                }
            }
        }
        .padding(16)
        .contentShape(Rectangle())
    }

    private var bookCover: some View {
        BookCoverView(url: book.imageURL, isbn: book.isbn, allowsRetry: false)
            .frame(width: 78, height: 111)
            .background(.white.opacity(0.06))
            .clipShape(.rect(cornerRadius: 8))
            .accessibilityHidden(true)
    }

    private var bookInformation: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(BookText.plainText(book.title))
                .typography(.bookTitle)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(2)

            Text(BookText.plainText(location ?? book.subLocation ?? "위치 정보 없음"))
                .typography(.body2)
                .foregroundStyle(Color.textPrimary)
                .lineLimit(1)

            Text(BookText.plainText(book.author))
                .typography(.caption2)
                .foregroundStyle(Color.basketTextTertiary)
                .lineLimit(1)

            Spacer(minLength: 8)
            availabilityText
                .typography(.caption2)
        }
        .frame(maxWidth: .infinity, minHeight: 111, alignment: .topLeading)
    }

    private var selectionMark: some View {
        ZStack {
            if isSelected {
                Circle().fill(Color.basketPrimary)
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.black)
            } else {
                Circle().strokeBorder(Color.basketTextTertiary, lineWidth: 2)
            }
        }
        .frame(width: 24, height: 24)
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private var availabilityText: some View {
        switch availability {
        case .available:
            Text("대출 가능").foregroundStyle(.green)
        case .unavailable:
            Text("이용 불가").foregroundStyle(.red)
        case .unknown, .none:
            Text("대출 상태 확인 필요").foregroundStyle(Color.basketTextTertiary)
        }
    }
}
