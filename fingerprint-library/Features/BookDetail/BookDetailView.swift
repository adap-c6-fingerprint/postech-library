import SwiftUI
import ComposableArchitecture

struct BookDetailView: View {
    let store: StoreOf<BookDetailFeature>

    var body: some View {
        List {
            Section {
                HStack(alignment: .top, spacing: 16) {
                    BookCoverView(url: store.book.imageURL)
                    .frame(width: 80, height: 116)
                    .background(Color.gray.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    VStack(alignment: .leading, spacing: 8) {
                        Text(BookText.plainText(store.book.title)).font(.headline)
                        Text(BookText.plainText(store.book.author))
                            .font(.subheadline).foregroundStyle(.secondary)
                        if let publisher = store.book.publisher, !publisher.isEmpty {
                            Text(BookText.plainText(publisher)).font(.caption)
                        }
                        if let year = store.book.publicationYear, !year.isEmpty {
                            Text(year).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section("책 정보") {
                if store.isLoading || !store.hasLoaded {
                    ProgressView("책 정보를 불러오고 있어요")
                        .frame(maxWidth: .infinity, minHeight: 80)
                } else if let message = store.errorMessage {
                    VStack(alignment: .leading, spacing: 12) {
                        Label(message, systemImage: "exclamationmark.circle")
                            .foregroundStyle(.secondary)
                        if store.isbn13 != nil {
                            Button("다시 시도") { store.send(.retryButtonTapped) }
                                .buttonStyle(.bordered)
                        }
                    }
                } else if let description = store.description {
                    Text(description.text).textSelection(.enabled)
                    Link(destination: description.sourceURL) {
                        Label("책 소개 제공: Yes24 · 원문 보기", systemImage: "arrow.up.right.square")
                            .font(.footnote)
                    }
                } else {
                    Text("이 책의 정보가 아직 제공되지 않아요.")
                        .foregroundStyle(.secondary)
                }
            }
            
            Section("연관 도서") {
                switch store.relatedBooksState {
                case .idle:
                    Text("연관 도서 조회를 기다리고 있어요.")
                        .foregroundStyle(.secondary)
                    
                case .loading:
                    ProgressView("연관 도서를 불러오고 있어요.")
                    
                case let .loaded(books):
                    if books.isEmpty {
                        Text("연관 도서가 아직 없어요.")
                    } else {
                        ForEach(books) { book in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(BookText.plainText(book.title))
                                    .font(.headline)
                                
                                Text(BookText.plainText(book.author))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                case let .failed(message):
                    VStack {
                        Text(message)
                            .foregroundStyle(.secondary)
                        
                        Button("다시 시도") {
                            store.send(.retryRelatedBooksButtonTapped)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }
        }
        .navigationTitle("도서 상세")
        .navigationBarTitleDisplayMode(.inline)
        // TODO: 상세 페이지 디자인을 적용하면 하단 액션바의 장바구니 버튼으로 옮긴다.
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button {
                    store.send(.addToBasketButtonTapped)
                } label: {
                    Image(systemName: "cart.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color(red: 0xF9 / 255, green: 0xF9 / 255, blue: 0xF9 / 255))
                        .frame(width: 50, height: 50)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular.tint(Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)).interactive(),
                    in: .circle
                )
                .accessibilityLabel("장바구니에 담기")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
        }
        .task { await store.send(.loadDescription).finish() }
        .task { await store.send(.loadRelatedBooks).finish() }
    }
}
