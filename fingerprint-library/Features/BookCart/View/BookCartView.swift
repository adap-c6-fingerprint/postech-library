//
//  BookCartView.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/21/26.
//

import ComposableArchitecture
import SwiftUI

struct BookCartView: View {
    @Bindable var store: StoreOf<BookCartFeature>
    var onClose: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .trailing, spacing: 4) {
                Text("총 \(store.items.count)권")
                    .typography(.body2)
                    .foregroundStyle(Color.cartTextSecondary)

                LazyVStack(alignment: .leading, spacing: 28) {
                    ForEach(store.sections) { section in
                        sectionView(section)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 24)
            .padding(.bottom, 24)
        }
        .overlay {
            if store.items.isEmpty {
                ContentUnavailableView(
                    "책바구니가 비어 있어요",
                    systemImage: "cart",
                    description: Text("찾고 싶은 책을 책바구니에 저장해두면\n빠르게 책의 위치를 찾을 수 있어요.")
                )
                .multilineTextAlignment(.center)
            }
        }
        .background { Color.cartBackground.ignoresSafeArea() }
        .navigationTitle("책바구니")
        .analyticsScreen(.cart)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarLeading) {
                    Button("뒤로", systemImage: "chevron.left", action: onClose)
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bottomActions }
        .alert(
            "길안내는 최대 \(BookCartItem.maxGuidanceCount)권까지 가능해요",
            isPresented: Binding(
                get: { store.isGuidanceLimitAlertPresented },
                set: { if !$0 { store.send(.guidanceLimitAlertDismissed) } }
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
            Button("삭제", role: .destructive) {
                store.send(.removeConfirmed)
            }
            Button("취소", role: .cancel) {}
        } message: {
            Text("이 책은 책바구니에서만 삭제돼요.\n다시 검색하여 찾아 추가할 수 있어요.")
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

            Spacer()

            NavigationLink {
                BookRoutePreviewView(
                    books: store.selectedBooks,
                    entryMode: store.selectedCount > 1 ? .preview : .direct
                )
            } label: {
                Text(store.selectedCount == 0 ? "안내 시작하기" : "안내 시작하기 (\(store.selectedCount)권)")
                    .font(.body.weight(.medium))
                    .foregroundStyle(store.canStartGuidance ? Color.black : Color.cartTextSecondary)
                    .padding(.horizontal, 14)
                    .frame(minHeight: 48)
                    .contentShape(.capsule)
            }
            .buttonStyle(.plain)
            .glassEffect(
                .regular
                    .tint(store.canStartGuidance ? Color.cartPrimary.opacity(0.7) : nil)
                    .interactive(store.canStartGuidance),
                in: .capsule
            )
            // NavigationLink는 화면 이동만 하므로, 같은 탭에서 최근 찾은 책 기록을 남긴다.
            .simultaneousGesture(TapGesture().onEnded { store.send(.guidanceLinkTapped) })
            .accessibilityIdentifier("cart-directions")
            .disabled(!store.canStartGuidance)
        }
        .disabled(store.selectedCount == 0)
        .padding(.horizontal, 28)
        .padding(.vertical, 12)
    }

    private func sectionView(_ section: BookCartSection) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(section.day, format: Self.dayFormat)
                .typography(.title2)
                .foregroundStyle(Color.cartTextSecondary)
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

    private func row(_ item: BookCartItem) -> some View {
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
extension View {
    // 책바구니 보관 한도를 넘겨 새 책을 담지 못했을 때 띄우는 팝업
    func cartLimitAlert(isPresented: Bool, onDismiss: @escaping () -> Void) -> some View {
        alert(
            "책바구니 최대 권수를 초과했어요",
            isPresented: Binding(
                get: { isPresented },
                set: { if !$0 { onDismiss() } }
            )
        ) {
            Button("확인했어요") {}
        } message: {
            Text("박태준학술정보관 책바구니에는 최대 \(BookCartItem.maxStoredCount)권까지 담을 수 있어요. 새 책을 담으시려면 기존에 담은 책 중 일부를 삭제해 주세요.")
        }
    }
}

// 피그마 책바구니 시안의 색상 토큰
extension Color {
    static let cartCard = Color(red: 0x2B / 255, green: 0x2B / 255, blue: 0x2B / 255)
    static let cartBackground = Color.backgroundDefault
    static let cartTextSecondary = Color.textSecondary
    static let cartTextTertiary = Color.textTertiary
    static let cartPrimary = Color.limeBase
}
