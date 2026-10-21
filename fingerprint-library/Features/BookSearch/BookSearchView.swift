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

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("책을 찾고 있어요")
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
            } else if !store.hasSearched {
                ContentUnavailableView(
                    "어떤 책을 찾으시나요?",
                    systemImage: "books.vertical",
                    description: Text("제목이나 저자 이름을 입력해 주세요.")
                )
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
                                onShowDetail: {
                                    store.send(.bookSelected(book))
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
        .safeAreaInset(edge: .bottom) {
            if store.hasSearched && !store.isLoading
                && store.errorMessage == nil && !store.books.isEmpty {
                NavigationLink {
                    BookBasketView(
                        books: store.basketBooks,
                        onDeletedSelected: { bookIDs in
                            store.send(.removeFromBasket(bookIDs))
                        }
                    )
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
        .navigationTitle(
            store.hasSearched ? "검색 결과" : "책 검색"
        )
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $store.scope(state: \.detail, action: \.detail)) { detailStore in
            BookDetailView(store: detailStore)
        }
        .searchable(
            text: Binding(
                get: {
                    return store.query
                },
                set: { newQuery in
                    store.send(.queryChanged(newQuery))
                }
            ),
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "제목이나 저자 이름"
        )
        .onSubmit(of: .search) {
            store.send(.searchButtonTapped)
        }
    }
}
