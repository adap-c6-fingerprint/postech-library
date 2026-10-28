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
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(store.items) { item in
                    Text(item.book.title)
                }
            }
            .padding(.horizontal, 16)
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
}

// 피그마 장바구니 시안의 색상 토큰
extension Color {
    static let basketBackground = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255)
}
