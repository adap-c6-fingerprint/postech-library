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
    @Environment(\.dismissSearch) private var dismissSearch
    
    var body: some View {
        VStack(spacing: 0) {
            categoryPicker
            searchContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .basketLimitAlert(isPresented: store.isBasketLimitAlertPresented) {
            store.send(.basketLimitAlertDismissed)
        }
        .toolbar {
            LibraryTopBar(title: "검색", onBasket: onShowBasket)
        }
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
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
                ContentUnavailableView {
                    Label("검색 결과가 없어요", systemImage: "magnifyingglass")
                } description: {
                    Text("다른 검색어로 찾아보세요.")
                } actions: {
                    Button("다시 검색") {
                        store.send(.refreshButtonTapped)
                    }
                }
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
                                },
                                onShowDirections: {
                                    store.send(.directionsButtonTapped(book))
                                })
                        }
                    }
                    .padding(16)
                }
                .scrollDismissesKeyboard(.interactively)
                .refreshable {
                    await store.send(.refreshButtonTapped).finish()
                }
            }
        }
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
