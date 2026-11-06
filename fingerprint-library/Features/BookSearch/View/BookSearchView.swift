//
//  BookSearchView.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import SwiftUI
import ComposableArchitecture

struct BookSearchView: View {
    @Bindable var store: StoreOf<BookSearchFeature>
    let onShowBasket: () -> Void
    var onShowFavorites: (() -> Void)? = nil
    var onShowProfile: (() -> Void)? = nil
    @Environment(\.dismissSearch) private var dismissSearch
    @Dependency(\.bookLocationCacheClient) private var bookLocationCacheClient
    
    var body: some View {
        VStack(spacing: 0) {
            categoryPicker
            searchContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(white: 17.0 / 255.0))
        .safeAreaInset(edge: .top, spacing: 0) {
            LibraryTabTopBar(
                title: "검색",
                onFavorites: { onShowFavorites?() },
                onBasket: onShowBasket,
                onProfile: { onShowProfile?() }
            )
            .padding(.bottom, 16)
            // 홈·추천 탭과 같은 상단 바를 같은 위치에 놓고, 아래 자료 유형 선택과 16pt 띄운다.
        }
        .toolbar(.hidden, for: .navigationBar)
        // 검색창은 탭바(role: .search)에 있으므로 내비게이션 바를 숨겨도 된다. 홈 지도 화면과 같은 방식이다.
        .basketLimitAlert(isPresented: store.isBasketLimitAlertPresented) {
            store.send(.basketLimitAlertDismissed)
        }
    }

    private var categoryPicker: some View {
        Picker("자료 유형", selection: Binding(
            get: { store.category },
            set: { store.send(.categoryChanged($0)) }
        )) {
            ForEach(BookSearchCategory.allCases, id: \.self) { category in
                Text(category.rawValue).tag(category)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var searchContent: some View {
        Group {
            if store.isLoading && store.books.isEmpty {
                ProgressView("책을 찾고 있어요")
            } else if !store.hasSearched
                        || store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                recentItems
            } else if store.errorMessage != nil {
                searchStatus(
                    title: "검색 실패",
                    message: "검색 중 문제가 발생했어요.\n다시 시도해주세요."
                )
            } else if store.visibleBooks.isEmpty {
                searchStatus(
                    title: "검색 결과 없음",
                    message: store.category == .all
                        ? "결과가 없어요. 새로운 검색을 시도해보세요."
                        : "불러온 결과에 해당 자료 유형이 없어요.\n다른 유형을 선택하거나 새로 검색해보세요."
                )
            } else {
                searchResults
            }
        }
    }

    private var searchResults: some View {
        let books = store.visibleBooks
        let holdings = bookLocationCacheClient.loadRecent(Set(books.map(\.recordKey)))

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("검색 결과 \(books.count)건")
                    .typography(.title1)
                    .foregroundStyle(.white)
                    .accessibilityAddTraits(.isHeader)

                LazyVStack(spacing: 0) {
                    ForEach(books) { book in
                        BookListRow(
                            book: book,
                            libraryInfo: holdings[book.recordKey].map { BookCardLibraryInfo(holdings: $0) },
                            onShowDetail: {
                                store.send(.bookSelected(book))
                            }
                        )

                        if book.id != books.last?.id {
                            Divider()
                                .overlay(.white.opacity(0.22))
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color(white: 42.0 / 255.0))
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 16)
        }
        .scrollDismissesKeyboard(.interactively)
        .refreshable {
            await store.send(.refreshButtonTapped).finish()
        }
    }

    private func searchStatus(title: String, message: String) -> some View {
        VStack(spacing: 8) {
            Text(title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.white)
                .accessibilityAddTraits(.isHeader)

            Text(message)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.8))
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        // 상단 필터와 하단 검색창 사이에서 시안의 메시지 중심을 맞춘다.
        .padding(.bottom, 96)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var recentItems: some View {
        if store.recentBooks.isEmpty {
            ContentUnavailableView(
                "최근 항목이 없어요",
                systemImage: "books.vertical",
                description: Text("검색 결과에서 선택한 책이 여기에 표시돼요.")
            )
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("최근 항목")
                        .font(.title3.bold())
                        .accessibilityAddTraits(.isHeader)

                    LazyVStack(spacing: 0) {
                        ForEach(store.recentBooks) { book in
                            RecentSearchBookRow(
                                book: book,
                                libraryInfo: store.recentBookInfo[book.id],
                                onSelect: {
                                    dismissSearch()
                                    store.send(.bookSelected(book))
                                }
                            )
                            if book.id != store.recentBooks.last?.id {
                                Divider().padding(.horizontal, 16)
                            }
                        }
                    }
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .scrollDismissesKeyboard(.interactively)
            .task {
                await store.send(.loadRecentBookInfo).finish()
            }
            .onDisappear {
                store.send(.recentBookInfoCancelled)
            }
            .refreshable {
                await store.send(.loadRecentBookInfo).finish()
            }
        }
    }
}

#Preview("검색 결과 없음") {
    BookSearchStatusPreview(errorMessage: nil)
}

#Preview("검색 실패") {
    BookSearchStatusPreview(errorMessage: "미리보기 오류")
}

private struct BookSearchStatusPreview: View {
    let errorMessage: String?

    var body: some View {
        NavigationStack {
            BookSearchView(
                store: Store(initialState: BookSearchFeature.State(
                    query: "검색어", errorMessage: errorMessage, hasSearched: true
                )) {
                    BookSearchFeature()
                },
                onShowBasket: {}
            )
        }
        .searchable(text: .constant("검색어"), prompt: "책 제목이나 저자를 검색하세요")
        .searchPresentationToolbarBehavior(.avoidHidingContent)
        .preferredColorScheme(.dark)
    }
}
