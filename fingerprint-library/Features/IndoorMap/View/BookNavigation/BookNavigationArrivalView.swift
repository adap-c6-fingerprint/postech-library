import SwiftUI

/// 도착한 서가에서 책등의 청구기호와 표지를 대조한다. 진행 동작은 상위 안내 상태가 처리한다.
struct BookNavigationArrivalView: View {
    let session: BookNavigationSession
    let currentStopIndex: Int
    private let bookInformation: BookNavigationBookInfo?
    private let onContinue: () -> Void
    private let onFinish: () -> Void
    private let onCancel: () -> Void
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .largeTitle) private var numberSize: CGFloat = 44

    init(session: BookNavigationSession, currentStopIndex: Int,
         bookInformation: BookNavigationBookInfo? = nil,
         onContinue: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {},
         onCancel: @escaping () -> Void = {}) {
        self.session = session
        self.currentStopIndex = currentStopIndex
        self.bookInformation = bookInformation ?? BookNavigationBookInfo(session: session, stopIndex: currentStopIndex)
        self.onContinue = onContinue
        self.onFinish = onFinish
        self.onCancel = onCancel
    }

    var body: some View {
        GeometryReader { geometry in
            let spacingScale = min(1, geometry.size.height / 760)
            ZStack {
                BookNavigationArrivalBackground().ignoresSafeArea()
                VStack(spacing: 0) {
                    topBar
                    ScrollView {
                        if let info = bookInformation {
                            VStack(spacing: 0) {
                                heading(info)
                                    .padding(.top, 16 * spacingScale)
                                callNumbers(info)
                                    .padding(.horizontal, -16)
                                    .padding(.top, 44 * spacingScale)
                                searchInstruction(info)
                                    .padding(.top, 36 * spacingScale)
                                BookCoverView(url: info.book.imageURL, isbn: info.book.isbn)
                                    .id(info.book.imageURL)
                                    .frame(width: min(230, geometry.size.width * 0.58),
                                           height: min(330, geometry.size.height * 0.42))
                                    .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .rotationEffect(.degrees(5))
                                    .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                                    .accessibilityLabel("\(title(info)) 책 표지")
                                    .accessibilityIdentifier("book-navigation-arrival-cover")
                                    .padding(.top, 56 * spacingScale)
                                    .padding(.bottom, 16)
                            }
                            .padding(.horizontal, 28)
                            .frame(maxWidth: .infinity)
                        } else {
                            ContentUnavailableView("도착 정보를 확인해 주세요", systemImage: "books.vertical")
                                .padding(.top, 60)
                        }
                    }
                    .scrollIndicators(.hidden)
                    .scrollBounceBehavior(.basedOnSize)
                    actions
                }
            }
        }
        .foregroundStyle(.white)
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .accessibilityIdentifier("book-navigation-arrival")
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 20, weight: .medium))
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("길안내로 돌아가기")
                .accessibilityIdentifier("book-navigation-arrival-back")
                Spacer()
            }
            if bookInformation != nil, session.stops.count > 1 {
                Text("\(currentStopIndex + 1)/\(session.stops.count)")
                    .font(.body)
                    .padding(.horizontal, 16).padding(.vertical, 9)
                    .background(.white.opacity(0.12), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.3), lineWidth: 0.5))
                    .accessibilityLabel("총 \(session.stops.count)권 중 \(currentStopIndex + 1)번째 책")
                    .accessibilityIdentifier("book-navigation-arrival-progress")
            }
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 12)
        .buttonStyle(.plain)
    }

    private func heading(_ info: BookNavigationBookInfo) -> some View {
        VStack(spacing: 6) {
            Text(title(info))
                .font(.title.bold())
                .accessibilityIdentifier("book-navigation-book-title")
            Text(author(info))
                .font(.title3)
        }
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func callNumbers(_ info: BookNavigationBookInfo) -> some View {
        VStack(spacing: 16) {
            if info.callNumbers.isEmpty {
                Text("청구기호 확인 필요")
                    .font(.title3.bold())
                Text("\(info.floorName ?? "층 정보 확인 필요") · 서가 \(info.shelf.realNumber)-\(info.shelf.side.rawValue)")
                    .font(.subheadline)
                    .accessibilityIdentifier("book-navigation-shelf")
            } else {
                ForEach(info.callNumbers, id: \.self) { rawValue in
                    if let number = BookNavigationArrivalCallNumber(rawValue) {
                        callNumber(number)
                    } else {
                        Text(rawValue)
                            .font(.title2.bold())
                            .foregroundStyle(BookNavigationPalette.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .multilineTextAlignment(.center)
        .accessibilityIdentifier("book-navigation-call-number")
    }

    private func callNumber(_ number: BookNavigationArrivalCallNumber) -> some View {
        HStack(spacing: 8) {
            chip(number.classification)
            highlightedNumber(number.number)
            suffixChips(number)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("청구기호 \(number.rawValue)")
    }

    private func suffixChips(_ number: BookNavigationArrivalCallNumber) -> some View {
        ForEach(Array(number.suffix.split(whereSeparator: \.isWhitespace).enumerated()), id: \.offset) { _, part in
            chip(String(part))
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.title3.weight(.medium))
            .foregroundStyle(.black)
            .padding(.horizontal, 9).padding(.vertical, 7)
            .background(BookNavigationPalette.accent, in: RoundedRectangle(cornerRadius: 7))
            .fixedSize(horizontal: false, vertical: true)
    }

    private func highlightedNumber(_ number: String) -> some View {
        Text(number)
            .font(.system(size: numberSize, weight: .bold))
            .foregroundStyle(BookNavigationPalette.accent)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .overlay {
                GeometryReader { geometry in
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: 24))
                        path.addLine(to: .zero)
                        path.addLine(to: CGPoint(x: 24, y: 0))
                        path.move(to: CGPoint(x: geometry.size.width - 24, y: geometry.size.height))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height))
                        path.addLine(to: CGPoint(x: geometry.size.width, y: geometry.size.height - 24))
                    }
                    .stroke(BookNavigationPalette.accent, style: StrokeStyle(lineWidth: 5, lineCap: .square))
                }
                .accessibilityHidden(true)
            }
    }

    private func searchInstruction(_ info: BookNavigationBookInfo) -> some View {
        Group {
            if let first = info.callNumbers.first, let number = BookNavigationArrivalCallNumber(first) {
                (Text("책등에서 ") + Text(number.number).foregroundColor(BookNavigationPalette.accent)
                    + Text("을 먼저 찾은 후\n뒤의 숫자들을 이어서 찾으세요"))
            } else {
                Text("책등의 청구기호를 순서대로 확인해 주세요")
            }
        }
        .font(.subheadline)
        .lineSpacing(4)
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var actions: some View {
        VStack(spacing: 8) {
            if bookInformation != nil {
                Button("찾았어요!", action: isIntermediateStop ? onContinue : onFinish)
                    .font(.body.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .padding(.vertical, 2)
                    .background(LinearGradient(colors: [Color(white: 0.04), Color(white: 0.11)],
                                               startPoint: .top, endPoint: .bottom), in: Capsule())
                    .overlay(Capsule().stroke(.white.opacity(0.18), lineWidth: 0.5))
                    .accessibilityIdentifier(isIntermediateStop ? "book-navigation-next-stop" : "book-navigation-finish")
            }
            if isIntermediateStop || bookInformation == nil {
                Button("안내 취소", action: onCancel)
                    .font(.subheadline)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("book-navigation-arrival-cancel")
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 32).padding(.bottom, 12)
    }

    private var isIntermediateStop: Bool { currentStopIndex < session.stops.count - 1 }

    private func title(_ info: BookNavigationBookInfo) -> String {
        let text = BookText.plainText(info.book.title).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "제목 정보 없음" : text
    }

    private func author(_ info: BookNavigationBookInfo) -> String {
        let text = BookText.plainText(info.book.author).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? "저자 정보 없음" : text
    }
}
