import SwiftUI
import UIKit

/// 도착한 서가 앞에서 실제 책등 이미지와 청구기호 번호표로 찾을 책을 보여준다. (피그마 "7. 책장 앞에서 책 찾기")
/// 진행 동작은 상위 안내 상태(BookNavigationFeature)가 처리한다.
struct BookNavigationBookFindingView: View {
    private let isIntermediateStop: Bool
    private let bookInformation: BookNavigationBookInfo?
    private let spine: BookNavigationFeature.SpinePhase?
    private let onTask: () -> Void
    private let onContinue: () -> Void
    private let onFinish: () -> Void
    @Environment(\.dismiss) private var dismiss

    init(session: BookNavigationSession, currentStopIndex: Int,
         bookInformation: BookNavigationBookInfo? = nil,
         spine: BookNavigationFeature.SpinePhase? = nil,
         onTask: @escaping () -> Void = {},
         onContinue: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {}) {
        self.init(bookInformation: bookInformation ?? BookNavigationBookInfo(session: session, stopIndex: currentStopIndex),
                  isIntermediateStop: currentStopIndex < session.stops.count - 1,
                  spine: spine, onTask: onTask, onContinue: onContinue, onFinish: onFinish)
    }

    init(bookInformation: BookNavigationBookInfo?, isIntermediateStop: Bool,
         spine: BookNavigationFeature.SpinePhase?,
         onTask: @escaping () -> Void = {},
         onContinue: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {}) {
        self.bookInformation = bookInformation
        self.isIntermediateStop = isIntermediateStop
        self.spine = spine
        self.onTask = onTask
        self.onContinue = onContinue
        self.onFinish = onFinish
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.backgroundDefault.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                shelf
                    .frame(height: Design.spineHeight)
                    .ignoresSafeArea(.container, edges: .horizontal)
                findButton
                    .padding(.top, Design.shelfToButton)
                    .padding(.horizontal, Design.buttonHorizontalPadding)
                    .padding(.bottom, Design.buttonBottomPadding)
            }
            // 책장은 하단 버튼 위에 붙고, 화면이 작으면 위쪽 안내 문구 뒤로 겹친다. (피그마 주석: 높이 고정)
            VStack(alignment: .leading, spacing: 0) {
                topBar
                if let info = bookInformation {
                    heading(info)
                        .padding(.top, Design.topBarToHeading)
                    instruction(info)
                        .padding(.top, Design.headingToInstruction)
                }
            }
            .padding(.horizontal, Design.horizontalPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { onTask() }
        .accessibilityIdentifier("book-navigation-arrival")
    }

    // MARK: - 상단

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("길안내로 돌아가기")
            .accessibilityIdentifier("book-navigation-arrival-back")
            Spacer()
        }
        .frame(height: Design.topBarHeight)
    }

    private func heading(_ info: BookNavigationBookInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("여기는")
                .typography(Design.headingCaption)
            Text(shelfTitle(info))
                .typography(.title1)
                .accessibilityIdentifier("book-navigation-shelf")
        }
        .foregroundStyle(Color.textPrimary)
    }

    private func instruction(_ info: BookNavigationBookInfo) -> some View {
        instructionText(info)
            .typography(.body1)
            .foregroundStyle(Color.textTertiary)
            .shadow(color: .black.opacity(0.58), radius: 10, x: 2, y: 2)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("book-navigation-instruction")
    }

    private func instructionText(_ info: BookNavigationBookInfo) -> Text {
        guard let number = callNumber(info) else { return Text("책등의 청구기호를 순서대로 확인해 주세요") }
        let key = number.classification + number.number
        let rest = number.suffix.filter { !$0.isWhitespace }
        let keyText = Text(key)
            .font(.custom("Pretendard-Bold", fixedSize: DS.FontSize._18))
            .foregroundColor(Color.textPrimary)
        let keyParticle: String = Self.objectParticle(after: key)
        let prefix: Text = Text("책등에서 ") + keyText
        guard !rest.isEmpty else {
            let tail: String = keyParticle + " 찾으세요."
            return prefix + Text(tail)
        }
        let restParticle: String = Self.objectParticle(after: rest)
        let tail: String = keyParticle + " 먼저 찾고,\n이어서 " + rest + restParticle + " 확인하세요."
        return prefix + Text(tail)
        // Text 덧셈과 문자열 보간을 한 식에 섞으면 타입 검사가 느려져 나눠 계산한다.
    }
    // 피그마: "책등에서 PR2993을 먼저 찾고, / 이어서 .F2.P45를 확인하세요." (PR2993만 굵은 흰 글씨)

    // MARK: - 책장

    private var shelf: some View {
        GeometryReader { geometry in
            let image = loadedSpineImage
            let imageSize = (image ?? UIImage(resource: .bookSpinePlaceholder)).size
            let spineWidth = Design.spineHeight * imageSize.width / imageSize.height
            // 책등 위 번호표가 왼쪽 확대 번호표보다 커지지 않도록 배율을 제한한다.
            let ratio = min(spineWidth / Design.referenceSpineWidth, 1 / Design.smallLabelScale)
            let spineRight = geometry.size.width - Design.spineTrailingInset
            let spineLeft = spineRight - spineWidth
            let smallLabelWidth = Design.smallLabelWidth * ratio
            let smallLabelHeight = Design.smallLabelHeight * ratio
            let smallLabelBottom = Design.spineHeight - Design.smallLabelBottomInset * ratio
            let smallLabelTop = smallLabelBottom - smallLabelHeight
            ZStack(alignment: .topLeading) {
                Image(.extraBooksLeft)
                    .resizable()
                    .frame(width: Design.extraBooksLeftSize.width, height: Design.extraBooksLeftSize.height)
                    .offset(x: spineLeft - Design.extraBooksLeftSize.width,
                            y: Design.spineHeight - Design.extraBooksLeftSize.height)
                // 피그마 주석: 기준선은 기준도서 좌측 세로선. 기준도서가 두꺼워지면 화면 밖 왼쪽으로 밀려난다.
                Image(.extraBooksRight)
                    .resizable()
                    .frame(width: Design.extraBooksRightSize.width, height: Design.extraBooksRightSize.height)
                    .offset(x: spineRight, y: Design.spineHeight - Design.extraBooksRightSize.height)
                // 피그마 주석: 기준선은 기준도서 우측 세로선. 우측 보조도서는 고정한다.
                spineView(image: image, width: spineWidth)
                    .offset(x: spineLeft)
                if let info = bookInformation, let number = callNumber(info) {
                    BookNavigationCallNumberLabel(callNumber: number, width: smallLabelWidth,
                                                  scale: Design.smallLabelScale * ratio,
                                                  emphasizesFirstLine: false)
                        .offset(x: spineRight - smallLabelWidth, y: smallLabelTop)
                        .accessibilityHidden(true)
                    // 정상 책등의 두께를 따르되 확대 번호표 크기까지만 늘어난다.
                    lightBeam(smallLabel: CGRect(x: spineRight - smallLabelWidth, y: smallLabelTop,
                                                 width: smallLabelWidth, height: smallLabelHeight))
                    BookNavigationCallNumberLabel(callNumber: number, width: BookNavigationCallNumberLabel.Design.width,
                                                  scale: 1)
                        .shadow(color: .black.opacity(0.25), radius: 7.5, x: 2, y: 2)
                        .offset(x: Design.largeLabelOrigin.x, y: Design.largeLabelOrigin.y)
                        .accessibilityIdentifier("book-navigation-call-number")
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height, alignment: .topLeading)
        }
        .clipped()
    }

    @ViewBuilder
    private func spineView(image: UIImage?, width: CGFloat) -> some View {
        switch spine {
        case .loaded, .unavailable:
            Image(uiImage: image ?? UIImage(resource: .bookSpinePlaceholder))
                .resizable()
                .frame(width: width, height: Design.spineHeight)
                .accessibilityLabel(image == nil ? "책등 이미지 준비 중" : "\(title) 책등")
                .accessibilityIdentifier("book-navigation-spine")
        case .loading, nil:
            Rectangle()
                .fill(Color.gray.opacity(0.4))
                .frame(width: width, height: Design.spineHeight)
                .accessibilityLabel("책등 불러오는 중")
        }
    }

    /// 확대 번호표에서 책등 위 작은 번호표로 이어지는 빛. 피그마 주석: 책 두께에 따라 꼭짓점을 조절한다.
    private func lightBeam(smallLabel: CGRect) -> some View {
        Canvas { context, _ in
            let large = CGRect(origin: Design.largeLabelOrigin,
                               size: CGSize(width: BookNavigationCallNumberLabel.Design.width,
                                            height: BookNavigationCallNumberLabel.Design.height))
            var path = Path()
            path.move(to: CGPoint(x: smallLabel.maxX, y: smallLabel.minY + 1))
            path.addLine(to: CGPoint(x: large.maxX - 2, y: large.minY + 1))
            path.addLine(to: CGPoint(x: large.maxX - 7, y: large.maxY - 0.5))
            path.addLine(to: CGPoint(x: smallLabel.minX - 16, y: smallLabel.maxY - 0.5))
            path.addLine(to: CGPoint(x: smallLabel.maxX, y: smallLabel.maxY - 0.5))
            path.closeSubpath()
            // 피그마 Vector 6641의 다섯 꼭짓점을 두 번호표의 모서리에 맞춰 옮긴다.
            let bounds = path.boundingRect
            context.fill(path, with: .linearGradient(
                Gradient(colors: [Design.beamStart, Design.beamEnd]),
                startPoint: CGPoint(x: bounds.minX + bounds.width * 0.0095, y: bounds.minY + bounds.height * 0.4046),
                endPoint: CGPoint(x: bounds.minX + bounds.width * 0.9778, y: bounds.minY + bounds.height * 0.8616)
            ))
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    // MARK: - 하단

    private var findButton: some View {
        Button(action: isIntermediateStop ? onContinue : onFinish) {
            Text("찾았어요!")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(Color.backgroundDefault)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Color.limeBase).interactive(), in: .capsule)
        .disabled(bookInformation == nil)
        .accessibilityIdentifier(isIntermediateStop ? "book-navigation-next-stop" : "book-navigation-finish")
    }

    // MARK: - 값

    private var loadedSpineImage: UIImage? {
        guard case let .loaded(data) = spine, let image = UIImage(data: data),
              image.size.height > 0, image.size.width > 0,
              image.size.width / image.size.height <= Design.maximumSpineAspectRatio else { return nil }
        return image
    }
    // 표지처럼 넓은 이미지가 들어오면 책등 대신 준비 중 이미지를 사용한다.
    // 정상 책등은 높이를 고정하고 원본 너비 비율을 유지한다.

    private var title: String {
        guard let info = bookInformation else { return "" }
        return BookText.plainText(info.book.title).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callNumber(_ info: BookNavigationBookInfo) -> BookNavigationArrivalCallNumber? {
        info.callNumbers.lazy.compactMap(BookNavigationArrivalCallNumber.init).first
    }

    private func shelfTitle(_ info: BookNavigationBookInfo) -> String {
        [info.floorName, "\(info.shelf.realNumber)번 서가"].compactMap { $0 }.joined(separator: " ")
    }
    // 예: "4층 337번 서가"

    /// 마지막 글자의 받침 유무로 목적격 조사(을/를)를 고른다. 숫자·영문은 읽는 소리 기준이다.
    private static func objectParticle(after text: String) -> String {
        guard let last = text.last(where: { $0.isLetter || $0.isNumber }) else { return "를" }
        if let scalar = last.unicodeScalars.first, (0xAC00...0xD7A3).contains(scalar.value) {
            return (scalar.value - 0xAC00) % 28 == 0 ? "를" : "을"
        }
        // 한글은 종성 유무로 판단한다.
        if "013678".contains(last) { return "을" }
        // 영(0) 일 삼 육 칠 팔은 받침이 있다.
        if "LMNRlmnr".contains(last) { return "을" }
        // 엘 엠 엔 알은 받침이 있다.
        return "를"
    }

    private enum Design {
        static let spineHeight: CGFloat = 411
        static let referenceSpineWidth: CGFloat = 25
        // 피그마 기준도서(image 129) 크기 25 × 411
        static let maximumSpineAspectRatio: CGFloat = 1.0 / 3.0
        // 가로:세로 1:3보다 넓은 이미지는 책등으로 표시하지 않는다.
        static let spineTrailingInset: CGFloat = 78
        // 402pt 화면에서 기준도서 우측 세로선이 x = 324
        static let extraBooksLeftSize = CGSize(width: 298.75, height: 382.75)
        static let extraBooksRightSize = CGSize(width: 79, height: 382.75)
        // 피그마 주석: 4X로 내보낸 에셋(1195 × 1531, 316 × 1531)을 화면 비율에 맞춘다.
        static let smallLabelWidth: CGFloat = 26.427
        static let smallLabelHeight: CGFloat = 59
        static let smallLabelBottomInset: CGFloat = 5
        static let smallLabelScale: CGFloat = 59 / BookNavigationCallNumberLabel.Design.height
        static let largeLabelOrigin = CGPoint(x: 68, y: 166)
        // 책장 영역(기준도서 윗면 = 0) 기준 확대 번호표 위치
        static let beamStart = Color(red: 0xD9 / 255, green: 0xD9 / 255, blue: 0xD9 / 255).opacity(0.2)
        static let beamEnd = Color(red: 0x73 / 255, green: 0x73 / 255, blue: 0x73 / 255).opacity(0.2)
        static let horizontalPadding: CGFloat = 16
        static let topBarHeight: CGFloat = 48
        static let topBarToHeading: CGFloat = 27.4
        static let headingToInstruction: CGFloat = 20
        static let shelfToButton: CGFloat = 47
        static let buttonHorizontalPadding: CGFloat = 36
        static let buttonBottomPadding: CGFloat = 18
        static let headingCaption = DS.Typography(style: DS.FontStyle.Medium, size: DS.FontSize._20,
                                                  lineHeight: DS.LineHeight._20, letterSpacing: DS.LetterSpacing._20)
        // 피그마 "여기는": Pretendard Medium 20 / 28 / -0.4
    }
}

#if DEBUG
// MARK: - 미리보기 (서버 없이 화면만 확인한다)

private extension BookNavigationBookInfo {
    init(previewTitle: String, callNumber: String) {
        let floorID = UUID()
        book = Book(id: "preview-book", isbn: nil, controlNumber: nil, title: previewTitle, author: "이승우",
                    publisher: nil, publicationYear: nil, description: nil, imageURL: nil)
        shelf = IndoorShelfLabel(fixtureNumber: "preview-337", realNumber: "337", side: .a, sequence: 0,
                                 floorID: floorID, mapElementID: .init(kind: .fixture, sourceID: UUID()),
                                 geometry: .point(.init(latitude: 0, longitude: 0)),
                                 content: .callNumberRange(start: "PR1", end: "PR9999"))
        candidateShelves = [shelf]
        floorName = "4층"
        locationNames = []
        callNumbers = [callNumber]
    }
    // 실제 화면은 길안내 세션에서 만들지만, 미리보기는 피그마 예시 값(4층 337번 서가, PR2993 .F2 .P45)으로 바로 만든다.
}

private func previewSpine(width: CGFloat) -> BookNavigationFeature.SpinePhase {
    let size = CGSize(width: width, height: 411)
    let image = UIGraphicsImageRenderer(size: size).image { context in
        UIColor(red: 0.42, green: 0.27, blue: 0.78, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
    return image.pngData().map(BookNavigationFeature.SpinePhase.loaded) ?? .unavailable
}
// 책등 API 대신 단색 이미지를 쓴다. 너비를 바꿔 책 두께에 따른 배치(피그마 주석)를 확인한다.

#Preview("책등 25pt (피그마 기준)") {
    NavigationStack {
        BookNavigationBookFindingView(
            bookInformation: .init(previewTitle: "결정 시간", callNumber: "PR2993 .F2 .P45"),
            isIntermediateStop: false, spine: previewSpine(width: 25))
    }
}

#Preview("두꺼운 책등 70pt") {
    NavigationStack {
        BookNavigationBookFindingView(
            bookInformation: .init(previewTitle: "결정 시간", callNumber: "PR2993 .F2 .P45"),
            isIntermediateStop: false, spine: previewSpine(width: 70))
    }
}

#Preview("책등 없음") {
    NavigationStack {
        BookNavigationBookFindingView(
            bookInformation: .init(previewTitle: "결정 시간", callNumber: "QA76.73 .P98 2021"),
            isIntermediateStop: true, spine: .unavailable)
    }
}
#endif
