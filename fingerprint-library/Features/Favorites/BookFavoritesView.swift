//
//  BookFavoritesView.swift
//  fingerprint-library
//

import ComposableArchitecture
import SwiftUI

struct BookFavoritesView: View {
    @Bindable var store: StoreOf<BookFavoritesFeature>

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 4) {
                Text("총 \(store.items.count)권")
                    .typography(.body2)
                    .foregroundStyle(Color.cartTextSecondary)

                LazyVStack(alignment: .leading, spacing: 24) {
                    ForEach(store.sections) { section in
                        sectionView(section)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .background { Color.cartBackground.ignoresSafeArea() }
        .navigationTitle("내가 읽고 싶은 책")
        .analyticsScreen(.favorites)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
        .alert(
            "선택한 책을 책바구니에 담았어요.",
            isPresented: Binding(
                get: { store.isAddedToCartAlertPresented },
                set: { if !$0 { store.send(.addedToCartAlertDismissed) } }
            )
        ) {
            Button("지금 안함", role: .cancel) {}
            Button("책바구니 가기") {
                store.send(.goToCartButtonTapped)
            }
        } message: {
            Text("책바구니로 이동해 길 안내를 시작할까요?")
        }
        .cartLimitAlert(isPresented: store.isCartLimitAlertPresented) {
            store.send(.cartLimitAlertDismissed)
        }
        .task { store.send(.task) }
        .task(id: store.items.map(\.id)) { await store.send(.loadLibraryInfo).finish() }
    }

    private var bottomActions: some View {
        HStack(spacing: 16) {
            Button {
                store.send(.removeButtonTapped)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 22))
                    .frame(width: 48, height: 48)
            }
            .buttonStyle(.glass)
            .buttonBorderShape(.circle)
            .accessibilityLabel("선택한 책 삭제")
            .accessibilityIdentifier("favorites-remove")

            Spacer()

            Button {
                store.send(.addToCartButtonTapped)
            } label: {
                Text("책바구니에 담기")
                    .font(.body.weight(.medium))
                    .foregroundStyle(store.selectedIDs.isEmpty ? Color.white : Color.black)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .background(Color.cartPrimary, in: .capsule)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("favorites-add-to-cart")
        }
        .disabled(store.selectedIDs.isEmpty)
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
        .background(Color.cartBackground)
    }

    private func sectionView(_ section: BookFavoriteSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.day, format: Self.dayFormat)
                .typography(.title2)
                .foregroundStyle(Color.cartTextTertiary)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 0) {
                ForEach(section.items) { item in
                    row(item)

                    if item.id != section.items.last?.id {
                        Divider()
                            .overlay(Color.cartTextTertiary.opacity(0.3))
                            .padding(.horizontal, 16)
                    }
                }
            }
            .background(Color.cartCard, in: .rect(cornerRadius: 20))
        }
    }

    private func row(_ item: BookFavoriteItem) -> some View {
        let info = store.libraryInfo[item.id]
        return BookSelectionRow(
            book: item.book,
            location: info?.location,
            availability: info?.availability,
            isSelected: store.selectedIDs.contains(item.id),
            onToggle: { store.send(.selectionToggled(item.id)) },
            onCoverRecovered: { oldURL, newURL in store.send(.coverRecovered(item.id, oldURL, newURL)) }
        )
    }

    private static let dayFormat = Date.FormatStyle(date: .abbreviated, time: .omitted)
        .locale(Locale(identifier: "en_US"))
}
