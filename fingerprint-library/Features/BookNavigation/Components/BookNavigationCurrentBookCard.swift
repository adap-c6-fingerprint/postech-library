import SwiftUI

struct BookNavigationCurrentBookCard: View {
    let info: BookNavigationBookInfo
    let route: IndoorRoute

    var body: some View {
        GeometryReader { geometry in
            let coverHeight = 186.0 /*min(186, geometry.size.height)*/
            let coverWidth = 140.0 /*min(140, geometry.size.width * 0.38, coverHeight * 0.75)*/
            HStack(alignment: .top) {
                BookCoverView(url: info.book.imageURL, isbn: info.book.isbn)
                    .frame(width: coverWidth, height: coverHeight)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .accessibilityIdentifier("book-navigation-current-cover")

                Spacer()

                VStack(alignment: .leading, spacing: 7) {
                    Text("현재 책")
                        .typography(.body2)
                        .foregroundStyle(PobookUI.ColorToken.primaryLight)
                    Text(BookText.plainText(info.book.title))
                        .typography(.bookTitle).lineLimit(2)
                        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
                        .accessibilityIdentifier("book-navigation-current-title")
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(info.floorName ?? "층 확인 필요") \(info.shelf.shelfTitle)")
                                .typography(.body2).lineLimit(2)
                                .foregroundStyle(PobookUI.ColorToken.BookDetails.textPlace)
                                .accessibilityIdentifier("book-navigation-current-shelf")
                            Text(info.callNumbers.isEmpty ? "청구기호 확인 필요" : info.callNumbers.joined(separator: " · "))
                                .typography(.body2).lineLimit(2)
                                .foregroundStyle(PobookUI.ColorToken.BookDetails.textPlace)
                                .accessibilityIdentifier("book-navigation-current-call-number")
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        Text("\(route.distanceMeters.formatted(.number.precision(.fractionLength(0))))m · 층 이동 \(route.floorChanges.count)회")
                            .typography(.caption1).foregroundStyle(PobookUI.ColorToken.BookDetails.textDistance)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("book-navigation-route-metrics")
                    }
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
                .frame(maxWidth: 216, alignment: .topLeading)
            }
            .frame(width: 370, alignment: .top)
        }
        .foregroundStyle(.white)
        .accessibilityIdentifier("book-navigation-current-book")
    }
}
