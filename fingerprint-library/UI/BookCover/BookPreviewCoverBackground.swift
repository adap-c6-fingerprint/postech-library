import SwiftUI

struct BookPreviewCoverBackground: View {
    let book: Book
    var cachedURL: URL?

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color(white: 0.06)
                BookCoverView(url: book.imageURL, isbn: book.isbn, cachedURL: cachedURL, allowsRetry: false)
                    .frame(width: geometry.size.width, height: geometry.size.height * 0.7)
                    .scaleEffect(1.8)
                    .blur(radius: 60)
                LinearGradient(stops: [
                    .init(color: .black.opacity(0.35), location: 0),
                    .init(color: .black.opacity(0.45), location: 0.3),
                    .init(color: Color(white: 0.06), location: 0.65),
                    .init(color: Color(white: 0.06), location: 1)
                ], startPoint: .top, endPoint: .bottom)
            }
            .clipped()
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
