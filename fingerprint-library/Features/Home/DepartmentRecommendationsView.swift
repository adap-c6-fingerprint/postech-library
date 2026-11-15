import ComposableArchitecture
import SwiftUI

struct DepartmentRecommendationsView: View {
    let store: StoreOf<HomeFeature>
    @State private var sortOrder = DepartmentBookSort.recommended

    private var title: String { store.popularBooksTitle }

    var body: some View {
        VStack(spacing: 20) {
            Picker("인기 도서 정렬", selection: $sortOrder) {
                ForEach(DepartmentBookSort.allCases, id: \.self) { order in
                    Text(order.rawValue).tag(order)
                }
            }
            .pickerStyle(.segmented)
            .environment(\.colorScheme, .dark)
            .padding(.horizontal, 16)

            switch store.departmentRecommendations {
            case .loading:
                ProgressView("추천 도서를 불러오고 있어요")
            case let .loaded(books) where books.isEmpty:
                Text("학과 추천 도서가 없어요.")
            case let .loaded(books):
                bookList(books)
            case let .failed(message):
                VStack(spacing: 12) {
                    Text(message)
                    Button("다시 시도") { store.send(.departmentRecommendationsRequested) }
                        .buttonStyle(.bordered)
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.textPrimary)
        .tint(.white)
        .background(Color.backgroundDefault.ignoresSafeArea())
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(Color.backgroundDefault, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .task(id: store.userProfile) { await store.send(.departmentRecommendationsRequested).finish() }
    }

    private func bookList(_ departmentBooks: [Book]) -> some View {
        let infoByID = store.libraryInfo.compactMapValues { state -> BookCardLibraryInfo? in
            guard case let .loaded(info) = state else { return nil }
            return info
        }
        let books = sortOrder.sorted(departmentBooks, libraryInfo: infoByID)

        return ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("인기 도서 \(books.count)권")
                    .typography(.title1)
                    .accessibilityAddTraits(.isHeader)

                LazyVStack(spacing: 0) {
                    ForEach(books) { book in
                        BookListRow(book: book, libraryInfo: infoByID[book.id]) {
                            store.send(.bookSelected(book))
                        }

                        if book.id != books.last?.id {
                            Divider()
                                .overlay(.white.opacity(0.22))
                                .padding(.horizontal, 16)
                        }
                    }
                }
                .background(Color(white: 42.0 / 255.0), in: RoundedRectangle(cornerRadius: 20))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }
}

enum DepartmentBookSort: String, CaseIterable {
    case recommended = "많이 빌린 순"
    case title = "제목 순"
    case availability = "대출 가능 순"

    func sorted(_ books: [Book], libraryInfo: [Book.ID: BookCardLibraryInfo]) -> [Book] {
        switch self {
        case .recommended:
            books
        case .title:
            books.sorted {
                BookText.plainText($0.title).localizedStandardCompare(BookText.plainText($1.title)) == .orderedAscending
            }
        case .availability:
            books.sorted {
                libraryInfo[$0.id]?.availability == .available && libraryInfo[$1.id]?.availability != .available
            }
        }
    }
}
