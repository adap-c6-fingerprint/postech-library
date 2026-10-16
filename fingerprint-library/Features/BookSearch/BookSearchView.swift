//
//  BookSearchView.swift
//  fingerprint-library
//
//  Created by Youngmin Cho on 10/15/26.
//

import SwiftUI
import ComposableArchitecture

struct BookSearchView: View {
    let store: StoreOf<BookSearchFeature>

    var body: some View {
        NavigationStack {
            List {
                if store.isLoading {
                    ProgressView("검색 중이에요")
                } else if let message = store.errorMessage {
                    Text(message)
                        .foregroundStyle(.red)
                } else {
                    ForEach(store.books) { book in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(book.title)
                                .font(.headline)

                            Text(book.author)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)

                            if let publisher = book.publisher {
                                Text(publisher)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("책 검색")
            .searchable(
                text: Binding(
                    get: { store.query },
                    set: { store.send(.queryChanged($0)) }
                ),
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "책 이름을 입력하세요"
            )
            .onSubmit(of: .search) {
                store.send(.searchButtonTapped)
            }
        }
    }
}
