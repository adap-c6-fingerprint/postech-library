//
//  RecentlyFoundBookView.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  마이페이지에서 navigate되는 최근 찾은 책 화면 View
//

import ComposableArchitecture
import SwiftUI

struct RecentlyFoundBookView: View {
    @Bindable var store: StoreOf<RecentlyFoundBookFeature>
    let mapStore: StoreOf<IndoorMapFeature>

    var body: some View {
        VStack(spacing: 0) {
            guide
                .padding(.top, 76)
                .padding(.bottom, 76)
            RecentlyFoundBookShelf(
                books: store.books, spines: store.spines, isScrollable: true,
                onSelect: { book in store.send(.bookSelected(book)) },
                size: .large
            )
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .background { Color.backgroundDefault.ignoresSafeArea() }
        .navigationTitle("최근 찾은 책 목록")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { store.send(.task) }
    }

    private var guide: some View {
        let navigationText = highlighted("길찾기")
        let swipeText = highlighted("좌우")
        return Text("이전에 \(navigationText)한 책을\n\(swipeText)로 넘겨보세요")
            .typography(.title2)
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(.center)
    }

    private func highlighted(_ word: String) -> Text {
        let title1 = PobookUI.Typography.title1
        return Text(word)
            .font(.custom(title1.fontName, fixedSize: title1.size))
            .tracking(title1.letterSpacing)
            .foregroundStyle(Color.limeBase)
    }
}
