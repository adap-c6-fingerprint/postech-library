//
//  BookBasketView.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/21/26.
//

import ComposableArchitecture
import SwiftUI

struct BookBasketView: View {
    let books: [Book]
    let onDeletedSelected: (Set<Book.ID>) -> Void
    let onShowDirections: (Set<Book.ID>) -> Void
    
    @State private var selectedBookIDs: Set<Book.ID> = []
    
    private var isAllSelected: Bool {
        !books.isEmpty && books.allSatisfy {
            selectedBookIDs.contains($0.id)
        }
    }

    private var selectedBooks: [Book] {
        books.filter { selectedBookIDs.contains($0.id) }
    }
    
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 8) {
                NavigationLink {
                    BookRoutePreviewView(books: selectedBooks)
                } label: {
                    Text("선택한 \(selectedBooks.count)권 경로 미리보기")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.bordered)
                .disabled(selectedBooks.isEmpty)
                .accessibilityIdentifier("basket-route-preview")
                Text("길안내는 한 번에 최대 \(BookRouteSelection.maximumBookCount)권까지 가능해요.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    onShowDirections(selectedBookIDs)
                } label: {
                    Text("길안내 받기 (\(selectedBookIDs.count)/\(BookRouteSelection.maximumBookCount)권)")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!BookRouteSelection.allows(bookCount: selectedBookIDs.count))
                .accessibilityIdentifier("basket-directions")
            }
            .padding(16)
            .background(Color(.systemGroupedBackground))
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Button {
                    if isAllSelected {
                        selectedBookIDs.removeAll()
                    } else {
                        selectedBookIDs = Set(books.map(\.id))
                    }
                    .labelStyle(.iconOnly)
                    .disabled(store.selectedCount == 0)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
                ToolbarItem(placement: .bottomBar) {
                    Button {
                        store.send(.startGuidanceButtonTapped)
                    } label: {
                        Text(
                            store.selectedCount == 0
                            ? "안내 시작하기"
                            : "안내 시작하기 (\(store.selectedCount)권)"
                        )
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.black)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Color.basketPrimary)
                    // 선택한 책이 0권이면 길안내를 시작하지 않는다.
                    .disabled(store.selectedCount == 0)
                    .accessibilityValue("\(store.selectedCount)권 선택됨")
                }
            } else {
                ToolbarItem(placement: .bottomBar) {
                    Button(
                        "길안내할 책 선택",
                        systemImage: "circle.grid.2x2.topleft.checkmark.filled"
                    ) {
                        store.send(.selectButtonTapped)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(store.items.isEmpty)
                }
                ToolbarSpacer(.flexible, placement: .bottomBar)
            }
        }
        .alert(
            "길안내는 최대 \(BookBasketItem.maxGuidanceCount)권까지 가능해요",
            isPresented: Binding(
                get: { store.isSelectionLimitAlertPresented },
                set: { if !$0 { store.send(.selectionLimitAlertDismissed) } }
            )
        ) {
            Button("확인했어요") {}
        } message: {
            Text("다른 책을 선택하려면 추가한 책을 해제하고 다시 시도해보세요.")
        }
        .alert(
            "선택한 책 \(store.selectedCount)권을 삭제할까요?",
            isPresented: Binding(
                get: { store.isRemoveAlertPresented },
                set: { if !$0 { store.send(.removeAlertDismissed) } }
            )
        ) {
            Button("삭제하기", role: .destructive) {
                store.send(.removeConfirmed)
            }
            Button("취소하기", role: .cancel) {}
        } message: {
            Text("장바구니에서만 삭제돼요. 도서관 소장 정보에는 영향이 없어요.")
        }
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

    @ViewBuilder
    private func row(_ item: BookBasketItem) -> some View {
        if store.isSelectingForGuidance {
            Button {
                store.send(.selectionToggled(item.id))
            } label: {
                HStack(spacing: 21) {
                    selectionMark(isSelected: store.selectedIDs.contains(item.id))
                    bookInfo(item)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(
                store.selectedIDs.contains(item.id) ? .isSelected : []
            )
        } else {
            bookInfo(item)
        }
    }

    private func selectionMark(isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 24))
            .symbolRenderingMode(.palette)
            .foregroundStyle(isSelected ? Color.white : Color.basketTextTertiary, Color.blue)
            .frame(width: 24, height: 24)
            .accessibilityHidden(true)
    }

    private func bookInfo(_ item: BookBasketItem) -> some View {
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

extension View {
    // 장바구니 보관 한도를 넘겨 새 책을 담지 못했을 때 띄우는 팝업
    func basketLimitAlert(isPresented: Bool, onDismiss: @escaping () -> Void) -> some View {
        alert(
            "장바구니 최대 권수를 초과했어요",
            isPresented: Binding(
                get: { isPresented },
                set: { if !$0 { onDismiss() } }
            )
        ) {
            Button("확인했어요") {}
        } message: {
            Text("박태준학술정보관 장바구니에는 최대 \(BookBasketItem.maxStoredCount)권까지 담을 수 있어요. 새 책을 담으시려면 기존에 담은 책 중 일부를 삭제해 주세요.")
        }
    }
}

// 피그마 장바구니 시안의 색상 토큰
extension Color {
    static let basketBackground = Color(red: 0x12 / 255, green: 0x12 / 255, blue: 0x12 / 255)
    static let basketCard = Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2B / 255)
    static let basketTextSecondary = Color(red: 0xF3 / 255, green: 0xF3 / 255, blue: 0xF3 / 255)
    static let basketTextTertiary = Color(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD9 / 255)
    static let basketPrimary = Color(red: 0xDD / 255, green: 0xF5 / 255, blue: 0x3C / 255)
}
