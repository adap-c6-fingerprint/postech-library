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
        // 탭바와 검색 탭 버튼을 숨기고 하단에는 피그마 하단 액션바만 둔다.
        .toolbar(.hidden, for: .tabBar)
        .safeAreaInset(edge: .bottom) { actionBar }
        .basketLimitAlert(isPresented: store.isBasketLimitAlertPresented) {
            store.send(.basketLimitAlertDismissed)
        }
        .task { await store.send(.loadDescription).finish() }
        .task { await store.send(.loadRelatedBooks).finish() }
    }

    // 피그마 하단 액션바: 어두운 글래스 텍스트 버튼과 장바구니 심볼 버튼
    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                store.send(.startGuidanceButtonTapped)
            } label: {
                Text("바로 안내 시작")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Color.detailActionText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Color.detailActionTint).interactive(), in: .capsule)

            Button {
                store.send(.addToBasketButtonTapped)
            } label: {
                Image(systemName: "cart.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Color.detailActionText)
                    .frame(width: 50, height: 50)
            }
            .buttonStyle(.plain)
            .glassEffect(.regular.tint(Color.detailActionTint).interactive(), in: .circle)
            .accessibilityLabel("장바구니에 담기")
        }
        // 홈 인디케이터 안전 영역(34pt) 위에 붙어 피그마의 하단 여백과 맞는다.
        .padding(.horizontal, 16)
    }
}

// 피그마 하단 액션바 색상 토큰 (Text Primary, Gray 700)
private extension Color {
    static let detailActionText = Color(red: 0xF9 / 255, green: 0xF9 / 255, blue: 0xF9 / 255)
    static let detailActionTint = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)
}
