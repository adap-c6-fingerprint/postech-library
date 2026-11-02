import SwiftUI

struct RecentSearchBookRow: View {
    let book: Book
    let libraryInfo: BookSearchFeature.RecentBookInfoState?
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 20) {
                BookCoverView(url: book.imageURL, isbn: book.isbn, allowsRetry: false)
                    .frame(width: 72, height: 110)
                    .background(Color.primary.opacity(0.04))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 6) {
                    Text(BookText.plainText(book.title))
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)

                    Text(BookText.plainText(locationText))
                        .font(.system(size: 16))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text(BookText.plainText(book.author))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 8)
                    availabilityText
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint("책 소개 보기")
        .accessibilityIdentifier("recent-search-book-\(book.id)")
    }

    private var locationText: String {
        switch libraryInfo {
        case .loaded(let info):
            return info.location ?? (info.holdings.isEmpty ? "소장 정보 없음" : "위치 정보 없음")
        case .failed, .unavailable:
            return book.subLocation ?? "소장 정보 확인 불가"
        case .none, .loading:
            return book.subLocation ?? "소장 정보 확인 중"
        }
    }

    @ViewBuilder
    private var availabilityText: some View {
        switch libraryInfo {
        case .loaded(let info):
            switch info.availability {
            case .available:
                Text("대출 가능").foregroundStyle(.green)
            case .unavailable:
                Text("이용 불가").foregroundStyle(.red)
            case .unknown:
                Text("대출 상태 확인 필요").foregroundStyle(.secondary)
            }
        case .none, .loading:
            Text("대출 상태 확인 중").foregroundStyle(.secondary)
        case .failed, .unavailable:
            Text("대출 상태 확인 필요").foregroundStyle(.secondary)
        }
    }
}
