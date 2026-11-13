import SwiftUI

struct BookNavigationCurrentBookCard: View {
    let info: BookNavigationBookInfo
    let route: IndoorRoute

    var body: some View {
        GeometryReader { geometry in
            let coverHeight = min(186, geometry.size.height)
            let coverWidth = min(140, geometry.size.width * 0.38, coverHeight * 0.75)
            HStack(alignment: .top, spacing: 14) {
                BookCoverView(url: info.book.imageURL, isbn: info.book.isbn)
                    .frame(width: coverWidth, height: coverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("book-navigation-current-cover")
                VStack(alignment: .leading, spacing: 0) {
                    Text("현재 책")
                        .typography(.body2)
                        .foregroundStyle(BookNavigationPalette.accent)
                        .padding(.bottom, 12)
                    Text(BookText.plainText(info.book.title))
                        .typography(.bookTitle).lineLimit(2)
                        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                        .accessibilityIdentifier("book-navigation-current-title")
                        .padding(.bottom, 12)
                    Text("\(info.floorName ?? "층 확인 필요") \(info.shelf.shelfTitle)")
                        .typography(.body2.weight(.medium)).lineLimit(2)
                        .accessibilityIdentifier("book-navigation-current-shelf")
                    Text(info.callNumbers.isEmpty ? "청구기호 확인 필요" : info.callNumbers.joined(separator: " · "))
                        .typography(.body2.weight(.medium)).lineLimit(2)
                        .accessibilityIdentifier("book-navigation-current-call-number")
                    Text("\(route.distanceMeters.formatted(.number.precision(.fractionLength(0))))m · 층 이동 \(route.floorChanges.count)회")
                        .typography(.caption1).foregroundStyle(.white.opacity(0.8))
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 16)
                        .accessibilityIdentifier("book-navigation-route-metrics")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .foregroundStyle(.white)
        .accessibilityIdentifier("book-navigation-current-book")
    }
}
