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
    private let onDefer: () -> Void
    private var callNumberScreen: CallNumberScreen?
    // 아래로 3초 이상 당기면 여는 기존 청구기호 화면(BookNavigationArrivalView)에 넘길 값. 미리보기에서는 nil
    @Environment(\.dismiss) private var dismiss
    @State private var isCallNumberScreenPresented = false
    @State private var isBookHelpPresented = false
    @State private var pullHoldTask: Task<Void, Never>?

    private struct CallNumberScreen {
        let session: BookNavigationSession
        let currentStopIndex: Int
        let onCancel: () -> Void
    }

    init(session: BookNavigationSession, currentStopIndex: Int,
         bookInformation: BookNavigationBookInfo? = nil,
         spine: BookNavigationFeature.SpinePhase? = nil,
         onTask: @escaping () -> Void = {},
         onContinue: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {},
         onDefer: @escaping () -> Void = {},
         onCancel: @escaping () -> Void = {}) {
        self.init(bookInformation: bookInformation ?? BookNavigationBookInfo(session: session, stopIndex: currentStopIndex),
                  isIntermediateStop: currentStopIndex < session.stops.count - 1,
                  spine: spine, onTask: onTask, onContinue: onContinue, onFinish: onFinish, onDefer: onDefer)
        callNumberScreen = CallNumberScreen(session: session, currentStopIndex: currentStopIndex, onCancel: onCancel)
    }

    init(bookInformation: BookNavigationBookInfo?, isIntermediateStop: Bool,
         spine: BookNavigationFeature.SpinePhase?,
         onTask: @escaping () -> Void = {},
         onContinue: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {},
         onDefer: @escaping () -> Void = {}) {
        self.bookInformation = bookInformation
        self.isIntermediateStop = isIntermediateStop
        self.spine = spine
        self.onTask = onTask
        self.onContinue = onContinue
        self.onFinish = onFinish
        self.onDefer = onDefer
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.backgroundDefault.ignoresSafeArea()
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                shelf
                    .frame(height: Design.spineHeight)
                    .ignoresSafeArea(.container, edges: .horizontal)
                findingActions
                    .padding(.top, Design.shelfToButton)
                    .padding(.horizontal, Design.buttonHorizontalPadding)
                    .padding(.bottom, Design.buttonBottomPadding)
            }
            // 책장은 하단 버튼 위에 붙고, 화면이 작으면 위쪽 안내 문구 뒤로 겹친다. (피그마 주석: 높이 고정)
            VStack(alignment: .leading, spacing: 0) {
                BookNavigationTopBar(
                    backLabel: "길안내로 돌아가기",
                    backIdentifier: "book-navigation-arrival-back",
                    onBack: { dismiss() }
                )
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
        .contentShape(.rect)
        .simultaneousGesture(pullDownToCallNumberScreen)
        .navigationDestination(isPresented: $isCallNumberScreenPresented) {
            if let screen = callNumberScreen {
                BookNavigationArrivalView(
                    session: screen.session, currentStopIndex: screen.currentStopIndex,
                    bookInformation: bookInformation,
                    onContinue: onContinue, onFinish: onFinish, onCancel: screen.onCancel
                )
            }
        }
        .navigationDestination(isPresented: $isBookHelpPresented) {
            if let info = bookInformation {
                BookNavigationBookHelpView(
                    info: info, hasNextStop: isIntermediateStop,
                    onContinue: onContinue, onDefer: onDefer
                )
            }
        }
        // 기존 화면의 뒤로가기는 이 책등 화면으로 돌아온다. 찾았어요·안내 취소는 기존과 같은 상위 동작을 쓴다.
        .onDisappear { cancelPullHold() }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { onTask() }
        .accessibilityIdentifier("book-navigation-arrival")
    }

    // MARK: - 아래로 당겨 기존 청구기호 화면 열기

    private var pullDownToCallNumberScreen: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                let isPullingDown = value.translation.height >= Design.pullDistance
                    && value.translation.height > abs(value.translation.width)
                if isPullingDown {
                    startPullHold()
                } else {
                    cancelPullHold()
                }
            }
            .onEnded { _ in cancelPullHold() }
    }
    // 15) 책찾기 화면 문서: 아래로 3초 이상 당기고 있으면 기존 청구기호 화면을 보여준다. 손을 떼거나 덜 당기면 취소한다.

    private func startPullHold() {
        guard callNumberScreen != nil, pullHoldTask == nil, !isCallNumberScreenPresented else { return }
        pullHoldTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Design.pullHoldSeconds))
            guard !Task.isCancelled else { return }
            pullHoldTask = nil
            isCallNumberScreenPresented = true
        }
    }

    private func cancelPullHold() {
        pullHoldTask?.cancel()
        pullHoldTask = nil
    }

    // MARK: - 상단

    private func heading(_ info: BookNavigationBookInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if spineImage == nil, !title.isEmpty {
                Text(shelfTitle(info))
                    .typography(Design.headingCaption)
                    .accessibilityIdentifier("book-navigation-shelf")
                Text(title)
                    .typography(.title1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("book-navigation-title")
            } else {
                Text("여기는")
                    .typography(Design.headingCaption)
                Text(shelfTitle(info))
                    .typography(.title1)
                    .accessibilityIdentifier("book-navigation-shelf")
            }
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
        let prefix = Text("책등에서 \(keyText)")
        guard !rest.isEmpty else {
            let tail: String = keyParticle + " 찾으세요."
            return Text("\(prefix)\(Text(tail))")
        }
        let restParticle: String = Self.objectParticle(after: rest)
        let tail: String = keyParticle + " 먼저 찾고,\n이어서 " + rest + restParticle + " 확인하세요."
        return Text("\(prefix)\(Text(tail))")
        // 강조한 Text를 보간해 스타일을 유지하고, 문장을 나눠 타입 검사 부담을 줄인다.
    }
    // 피그마: "책등에서 PR2993을 먼저 찾고, / 이어서 .F2.P45를 확인하세요." (PR2993만 굵은 흰 글씨)

    // MARK: - 책장

    private var shelf: some View {
        GeometryReader { geometry in
            let spineWidth = spineWidth
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
                spineView(width: spineWidth)
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
    private func spineView(width: CGFloat) -> some View {
        if let image = spineImage {
            Image(uiImage: image)
                .resizable()
                .frame(width: width, height: Design.spineHeight)
                .accessibilityLabel("\(title) 책등")
                .accessibilityIdentifier("book-navigation-spine")
        } else {
            placeholderSpine(width: width)
        }
        // 불러오는 중·책등 없음·이미지로 바꾸지 못한 경우 모두 bookSpinePlaceHolder 에셋으로 그린다.
    }

    private func placeholderSpine(width: CGFloat) -> some View {
        Image(.bookSpinePlaceHolder)
            .resizable()
            .frame(width: width, height: Design.spineHeight)
            .accessibilityLabel(title)
        // 책등 이미지가 없으면 최근 찾은 책 책장과 같이 bookSpinePlaceHolder 에셋으로 대신 그린다.
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

    private var findingActions: some View {
        VStack(spacing: Design.findingActionSpacing) {
            findButton
            Button {
                cancelPullHold()
                isBookHelpPresented = true
            } label: {
                Text("못 찾았어요.")
                    .typography(.body2)
                    .underline()
                    .foregroundStyle(Color.textTertiary)
                    .frame(minHeight: 28)
            }
            .buttonStyle(.plain)
            .disabled(bookInformation == nil)
            .accessibilityIdentifier("book-navigation-not-found")
        }
    }

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

    private var spineImage: UIImage? {
        guard case let .loaded(image) = spine, image.size.height > 0,
              image.size.width / image.size.height < Design.maxSpineAspectRatio else { return nil }
        return image
    }
    // Yes24는 책등이 없을 때 빈 값 대신 표지 모양의 "이미지 준비중" 그림을 준다.
    // 진짜 책등은 세로로 길쭉하므로, 길쭉하지 않은 그림은 책등이 없는 책으로 보고 bookSpinePlaceHolder로 그린다.

    private var spineWidth: CGFloat {
        if let image = spineImage {
            return Design.spineHeight * image.size.width / image.size.height
            // 피그마 주석: 높이는 고정하고, 너비는 책등 원본 비율을 따른다.
        }
        return Design.spineHeight * Design.placeholderAspectRatio
        // 대체 에셋은 "책표지 준비중" 글자가 찌그러지지 않게 원본 비율을 지킨다. (411 높이에서 약 47)
    }

    private var title: String {
        guard let info = bookInformation else { return "" }
        return BookText.plainText(info.book.title).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callNumber(_ info: BookNavigationBookInfo) -> BookNavigationArrivalCallNumber? {
        info.callNumbers.lazy.compactMap { BookNavigationArrivalCallNumber($0) }.first
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
        static let maxSpineAspectRatio: CGFloat = 0.3
        // 책등으로 인정하는 최대 가로÷세로 비율. 실제 책등은 대략 0.05~0.25이고, Yes24 "이미지 준비중" 그림은 표지처럼 세로로 조금 긴 모양(약 0.5~0.7)이다.
        static let placeholderAspectRatio: CGFloat = 188 / 1644
        // bookSpinePlaceHolder.png 원본 크기(가로 188 × 세로 1644 px)
        // 피그마 기준도서(image 129) 크기 25 × 411
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
        static let topBarToHeading: CGFloat = 27.4
        static let headingToInstruction: CGFloat = 20
        static let shelfToButton: CGFloat = 47
        static let buttonHorizontalPadding: CGFloat = 36
        static let buttonBottomPadding: CGFloat = 18
        static let findingActionSpacing: CGFloat = 12
        static let pullDistance: CGFloat = 60
        // 이만큼 아래로 당긴 상태를 유지해야 3초를 센다. 살짝 스친 터치는 무시한다.
        static let pullHoldSeconds: Double = 3
        static let headingCaption = DS.Typography(style: DS.FontStyle.Medium, size: DS.FontSize._20,
                                                  lineHeight: DS.LineHeight._20, letterSpacing: DS.LetterSpacing._20)
        // 피그마 "여기는": Pretendard Medium 20 / 28 / -0.4
    }
}

#if DEBUG
// MARK: - 미리보기 (서버 없이 화면만 확인한다)

extension BookNavigationBookInfo {
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
        holdings = [BookHolding(holdingID: nil, institutionCode: "82POSTECH_INST", libraryCode: "MAIN",
                                locationCode: "c4b", locationName: "단행본 4층",
                                callNumber: callNumber, availability: "available")]
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
    return .loaded(image)
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

#Preview("책등 없음 · 서가와 책 제목") {
    NavigationStack {
        BookNavigationBookFindingView(
            bookInformation: .init(previewTitle: "푸울에 풍덩", callNumber: "PR2993 .F2 .P45"),
            isIntermediateStop: true, spine: .unavailable)
    }
}
#endif
