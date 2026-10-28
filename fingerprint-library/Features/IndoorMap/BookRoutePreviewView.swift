import SwiftUI

/// 상세·바구니에서 선택한 책을 그대로 받는 PLI-96 / #116 기본 화면.
struct BookRoutePreviewView: View {
    let books: [Book]

    var body: some View {
        Group {
            if books.isEmpty {
                ContentUnavailableView(
                    "찾을 책이 없어요",
                    systemImage: "books.vertical",
                    description: Text("책 상세 또는 책바구니에서 책을 선택해 주세요.")
                )
            } else {
                List {
                    Section {
                        ContentUnavailableView(
                            "경로 표시 영역",
                            systemImage: "map",
                            description: Text("선택한 책까지의 경로가 여기에 표시될 예정이에요.")
                        )
                    }

                    Section("찾을 책 \(books.count)권") {
                        ForEach(books) { book in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(BookText.plainText(book.title))
                                    .font(.headline)
                                Text(BookText.plainText(book.author))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .accessibilityElement(children: .combine)
                        }
                    }
                }
            }
        }
        .navigationTitle("길찾기 경로 미리보기")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .accessibilityIdentifier("book-route-preview")
    }
}

#Preview {
    NavigationStack {
        BookRoutePreviewView(books: [])
    }
}
