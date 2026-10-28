//
//  BookBasketView.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/21/26.
//

import ComposableArchitecture
import SwiftUI

struct BookBasketView: View {
    @Bindable var store: StoreOf<BookBasketFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 0) {
                Text("총 \(store.items.count)권")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.basketTextSecondary)

                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(store.sections) { section in
                        sectionView(section)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 24)
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView(
                    "책바구니가 비어 있어요",
                    systemImage: "basket",
                    description: Text(
                        "검색 화면에서 책을 담아 주세요."
                    )
                )
            }
        }
        .background(Color.basketBackground)
        .navigationTitle("장바구니")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            store.send(.task)
        }
    }

    private func sectionView(_ section: BookBasketSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.day, format: Self.dayFormat)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.basketTextTertiary)

            VStack(alignment: .leading, spacing: 16) {
                ForEach(Array(section.items.enumerated()), id: \.element.id) { index, item in
                    if index > 0 {
                        Divider().overlay(Color.basketTextTertiary.opacity(0.3))
                    }
                    row(item)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.basketCard, in: .rect(cornerRadius: 20))
        }
    }

    private func row(_ item: BookBasketItem) -> some View {
        HStack(spacing: 21) {
            BookCoverView(url: item.book.imageURL, allowsRetry: false)
                .frame(width: 80, height: 113)
                .background(Color.basketTextTertiary)
                .clipShape(.rect(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 3) {
                Text(item.book.title)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white)
                    .lineLimit(2)

                Text(item.book.author)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color.basketTextTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    // 피그마 시안의 날짜 표기(Oct 12, 2026)를 따른다.
    private static let dayFormat = Date.FormatStyle(date: .abbreviated, time: .omitted)
        .locale(Locale(identifier: "en_US"))
}

// 피그마 장바구니 시안의 색상 토큰
extension Color {
    static let basketBackground = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255)
    static let basketCard = Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2B / 255)
    static let basketTextSecondary = Color(red: 0xF3 / 255, green: 0xF3 / 255, blue: 0xF3 / 255)
    static let basketTextTertiary = Color(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD9 / 255)
}
