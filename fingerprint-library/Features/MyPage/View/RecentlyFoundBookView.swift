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
    // 책 상세(BookDetailMapView)가 실내지도 상태를 함께 그린다.

    var body: some View {
        VStack(spacing: 0) {
            guide
                .padding(.top, 40)
                .padding(.bottom, 64)
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
        .navigationDestination(
            item: $store.scope(state: \.detail, action: \.detail)
        ) { detailStore in
            BookDetailMapView(store: detailStore, mapStore: mapStore)
        }
    }

    private var guide: some View {
        let navigationText = Text("길찾기").foregroundStyle(Color.limeBase)
        let swipeText = Text("좌우").foregroundStyle(Color.limeBase)
        return Text("이전에 \(navigationText)한 책을\n\(swipeText)로 넘겨보세요")
            .typography(.title2)
            .foregroundStyle(Color.textPrimary)
            .multilineTextAlignment(.center)
        // 피그마 안내 문구. "길찾기"와 "좌우"만 라임색으로 강조한다.
    }
}
