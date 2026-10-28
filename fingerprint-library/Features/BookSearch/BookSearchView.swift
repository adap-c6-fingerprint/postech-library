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
    let isEditingSearch: Bool
    let onSelectRecentQuery: (String) -> Void
    let onShowBasket: () -> Void
    
    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("책을 찾고 있어요")
            } else if isEditingSearch || !store.hasSearched
                        || store.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                searchHistory
            } else if store.errorMessage != nil {
                ContentUnavailableView {
                    Label(
                        "검색을 완료하지 못했어요",
                        systemImage: "exclamationmark.magnifyingglass"
                    )
                } description: {
                    Text("잠시 후 다시 시도해 주세요.")
                } actions: {
                    Button("다시 시도") {
                        store.send(.searchButtonTapped)
                    }
                }
            } else if store.books.isEmpty {
                ContentUnavailableView(
                    "검색 결과가 없어요",
                    systemImage: "magnifyingglass",
                    description: Text("다른 검색어로 찾아보세요.")
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.books) { book in
                            BookSearchResultRow(
                                book: book,
                                isFavorite: store.favoriteBookKeys.contains(book.recordKey),
                                onShowDetail: {
                                    store.send(.bookSelected(book))
                                },
                                onToggleFavorite: {
                                    store.send(.favoriteButtonTapped(book))
                                },
                                onAddToBasket: {
                                    store.send(.addToBasket(book))
                                })
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
        .toolbar {
            if store.hasSearched && !isEditingSearch {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("검색 결과 새로고침", systemImage: "arrow.clockwise") {
                        store.send(.refreshButtonTapped)
                    }
                    .labelStyle(.iconOnly)
                    .disabled(store.isLoading)
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            
            if !store.basketBooks.isEmpty {
                Button {
                    onShowBasket()
                } label: {
                    Label(
                        "책바구니 바로가기 (\(store.basketBooks.count)권)",
                        systemImage: "basket"
                    )
                    .frame(maxWidth: .infinity, minHeight: 44)
                }
                .glassEffect()
                .buttonStyle(.glassProminent)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(.bar)
            }
        }
        .basketLimitAlert(isPresented: store.isBasketLimitAlertPresented) {
            store.send(.basketLimitAlertDismissed)
        }
    }

    @ViewBuilder
    private var searchHistory: some View {
        if matchingRecentQueries.isEmpty {
            ContentUnavailableView(
                "어떤 책을 찾으시나요?",
                systemImage: "books.vertical",
                description: Text("제목이나 저자 이름을 입력하고 검색해 주세요.")
            )
        } else {
            List {
                Section("최근 검색어") {
                    ForEach(matchingRecentQueries, id: \.self) { keyword in
                        Button {
                            onSelectRecentQuery(keyword)
                        } label: {
                            Label(keyword, systemImage: "clock")
                                .foregroundStyle(.primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                        .accessibilityHint("이 검색어로 도서 검색")
                    }
                }
            }
            .listStyle(.plain)
            .scrollDismissesKeyboard(.interactively)
        }
    }

    private var matchingRecentQueries: [String] {
        let keyword = store.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty else { return store.recentQueries }
        return store.recentQueries.filter { $0.localizedStandardContains(keyword) }
    }
}
