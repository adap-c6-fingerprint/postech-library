import SwiftUI

/// 안내·도착 화면에서 같은 목적지의 제목·위치·청구기호를 함께 표시한다.
struct BookNavigationBookInformationView: View {
    let info: BookNavigationBookInfo
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 6 : 8) {
            Text(title)
                .font(compact ? .title2.bold() : .headline)
                .lineLimit(compact ? 3 : nil)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("book-navigation-book-title")
            if compact {
                Text("\(info.floorName ?? "층 정보 확인 필요") \(info.callNumbers.isEmpty ? "청구기호 확인 필요" : info.callNumbers.joined(separator: " · "))")
                    .font(.title3).foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("book-navigation-call-number")
                Text("서가 \(info.shelf.realNumber)-\(info.shelf.side.rawValue)")
                    .font(.caption).foregroundStyle(.white.opacity(0.7))
                    .accessibilityIdentifier("book-navigation-shelf")
            } else {
            Text(BookText.plainText(info.book.author))
                .font(.subheadline).foregroundStyle(.secondary)
            Text("\(info.floorName ?? "층 정보 확인 필요") · 서가 \(info.shelf.realNumber)-\(info.shelf.side.rawValue)")
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("book-navigation-shelf")
            ForEach(info.locationNames, id: \.self) { location in
                Text(BookText.plainText(location))
                    .font(.subheadline).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("청구기호").font(.caption).foregroundStyle(.secondary)
                if info.callNumbers.isEmpty {
                    Text("이 서가의 청구기호 확인이 필요해요")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(info.callNumbers, id: \.self) { number in
                        Text(number).font(.body.monospaced())
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .accessibilityIdentifier("book-navigation-call-number")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var title: String {
        let text = BookText.plainText(info.book.title).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "제목 정보 없음" : text
    }
}
