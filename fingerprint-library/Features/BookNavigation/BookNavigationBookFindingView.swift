import SwiftUI
import UIKit

struct BookNavigationBookFindingView: View {
    private let isIntermediateStop: Bool
    private let bookInformation: BookNavigationBookInfo?
    private let spine: BookNavigationFeature.SpinePhase?
    private let onTask: () -> Void
    private let onContinue: () -> Void
    private let onFinish: () -> Void
    private let onDefer: () -> Void
    private var callNumberScreen: CallNumberScreen?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isCallNumberScreenPresented = false
    @State private var isBookHelpPresented = false
    @State private var pullHoldTask: Task<Void, Never>?

    private struct CallNumberScreen {
        let routePlan: RoutePlan
        let currentStopIndex: Int
        let onCancel: () -> Void
    }

    init(routePlan: RoutePlan, currentStopIndex: Int,
         bookInformation: BookNavigationBookInfo? = nil,
         spine: BookNavigationFeature.SpinePhase? = nil,
         onTask: @escaping () -> Void = {},
         onContinue: @escaping () -> Void = {}, onFinish: @escaping () -> Void = {},
         onDefer: @escaping () -> Void = {},
         onCancel: @escaping () -> Void = {}) {
        self.init(bookInformation: bookInformation ?? BookNavigationBookInfo(routePlan: routePlan, stopIndex: currentStopIndex),
                  isIntermediateStop: currentStopIndex < routePlan.stops.count - 1,
                  spine: spine, onTask: onTask, onContinue: onContinue, onFinish: onFinish, onDefer: onDefer)
        callNumberScreen = CallNumberScreen(routePlan: routePlan, currentStopIndex: currentStopIndex, onCancel: onCancel)
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
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView {
                    VStack(spacing: 0) {
                        findingHeader
                        shelf
                            .frame(height: Design.spineHeight)
                            .padding(.top, Design.headingToInstruction)
                        findingActions
                            .padding(.top, Design.shelfToButton)
                            .padding(.horizontal, Design.buttonHorizontalPadding)
                            .padding(.bottom, Design.buttonBottomPadding)
                    }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
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
                findingHeader
            }
        }
        .contentShape(.rect)
        .simultaneousGesture(pullDownToCallNumberScreen)
        .navigationDestination(isPresented: $isCallNumberScreenPresented) {
            if let screen = callNumberScreen {
                BookNavigationArrivalView(
                    routePlan: screen.routePlan, currentStopIndex: screen.currentStopIndex,
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
        .onDisappear { cancelPullHold() }
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
        .task { onTask() }
        .accessibilityIdentifier("book-navigation-arrival")
    }

    private var findingHeader: some View {
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

    private func heading(_ info: BookNavigationBookInfo) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if spineImage == nil, !title.isEmpty {
                Text(shelfTitle(info))
                    .typography(.shelfHeading)
                    .accessibilityIdentifier("book-navigation-shelf")
                Text(title)
                    .typography(.title1)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("book-navigation-title")
            } else {
                Text("여기는")
                    .typography(.shelfHeading)
                Text(shelfTitle(info))
                    .typography(.title1)
                    .accessibilityIdentifier("book-navigation-shelf")
            }
        }
        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
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
            .font(PobookUI.Typography.body1.weight(.bold).font(for: dynamicTypeSize))
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
    }

    private var shelf: some View {
        GeometryReader { geometry in
            let spineWidth = spineWidth
            let spineRight = geometry.size.width - Design.spineTrailingInset
            let spineLeft = spineRight - spineWidth
            let smallLabel = CGRect(x: spineLeft,
                y: Design.spineHeight - Design.smallLabelBottomInset - Design.smallLabelHeight,
                width: spineWidth, height: Design.smallLabelHeight)
            let number = bookInformation.flatMap { callNumber($0) }
            let largeLayout = number.map {
                BookNavigationCallNumberLabel.enlargedLayout(for: $0,
                    maximumWidth: max(BookNavigationCallNumberLabelLayout.Metrics.minimumWidth,
                                      spineLeft - Design.horizontalPadding * 2))
            }
            let largeLabel = largeLayout.map { layout in
                CGRect(x: min(Design.largeLabelOrigin.x,
                              max(Design.horizontalPadding, spineLeft - Design.horizontalPadding - layout.size.width)),
                       y: Design.largeLabelOrigin.y, width: layout.size.width, height: layout.size.height)
            }
            ZStack(alignment: .topLeading) {
                Image(.extraBooksLeft)
                    .resizable()
                    .frame(width: Design.extraBooksLeftSize.width, height: Design.extraBooksLeftSize.height)
                    .offset(x: spineLeft - Design.extraBooksLeftSize.width,
                            y: Design.spineHeight - Design.extraBooksLeftSize.height)
                Image(.extraBooksRight)
                    .resizable()
                    .frame(width: Design.extraBooksRightSize.width, height: Design.extraBooksRightSize.height)
                    .offset(x: spineRight, y: Design.spineHeight - Design.extraBooksRightSize.height)
                spineView(width: spineWidth)
                    .offset(x: spineLeft)
                if let number, let largeLayout, let largeLabel {
                    BookNavigationCallNumberLabel(callNumber: number,
                        layout: BookNavigationCallNumberLabel.spineLayout(from: largeLayout, size: smallLabel.size),
                        emphasizesFirstLine: false)
                        .offset(x: smallLabel.minX, y: smallLabel.minY)
                        .accessibilityHidden(true)
                    lightBeam(smallLabel: smallLabel, largeLabel: largeLabel)
                    BookNavigationCallNumberLabel(callNumber: number, layout: largeLayout)
                        .shadow(color: .black.opacity(0.25), radius: 7.5, x: 2, y: 2)
                        .offset(x: largeLabel.minX, y: largeLabel.minY)
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
    }

    private func placeholderSpine(width: CGFloat) -> some View {
        Image(.bookSpinePlaceHolder)
            .resizable()
            .frame(width: width, height: Design.spineHeight)
            .accessibilityLabel(title)
    }

    private func lightBeam(smallLabel: CGRect, largeLabel: CGRect) -> some View {
        Canvas { context, _ in
            var path = Path()
            path.move(to: CGPoint(x: smallLabel.maxX, y: smallLabel.minY + 1))
            path.addLine(to: CGPoint(x: largeLabel.maxX - 2, y: largeLabel.minY + 1))
            path.addLine(to: CGPoint(x: largeLabel.maxX - 7, y: largeLabel.maxY - 0.5))
            path.addLine(to: CGPoint(x: smallLabel.minX - 16, y: smallLabel.maxY - 0.5))
            path.addLine(to: CGPoint(x: smallLabel.maxX, y: smallLabel.maxY - 0.5))
            path.closeSubpath()
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

    private var findingActions: some View {
        VStack(spacing: Design.findingActionSpacing) {
            findButton
            LibraryUnderlinedButton(title: "못 찾았어요.") {
                cancelPullHold()
                isBookHelpPresented = true
            }
            .disabled(bookInformation == nil)
            .accessibilityIdentifier("book-navigation-not-found")
        }
    }

    private var findButton: some View {
        Button(action: isIntermediateStop ? onContinue : onFinish) {
            Text("찾았어요!")
                .typography(.button)
                .foregroundStyle(Color.backgroundDefault)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.tint(Color.limeBase).interactive(), in: .capsule)
        .disabled(bookInformation == nil)
        .accessibilityIdentifier(isIntermediateStop ? "book-navigation-next-stop" : "book-navigation-finish")
    }

    private var spineImage: UIImage? {
        guard case let .loaded(image) = spine, image.size.height > 0,
              image.size.width / image.size.height < Design.maxSpineAspectRatio else { return nil }
        return image
    }

    private var spineWidth: CGFloat {
        if let image = spineImage {
            return Design.spineHeight * image.size.width / image.size.height
        }
        return Design.spineHeight * Design.placeholderAspectRatio
    }

    private var title: String {
        guard let info = bookInformation else { return "" }
        return BookText.plainText(info.book.title).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func callNumber(_ info: BookNavigationBookInfo) -> BookNavigationArrivalCallNumber? {
        info.callNumbers.lazy.compactMap { BookNavigationArrivalCallNumber($0) }.first
    }

    private func shelfTitle(_ info: BookNavigationBookInfo) -> String {
        [info.floorName, info.shelf.shelfTitle].compactMap { $0 }.joined(separator: " ")
    }

    private static func objectParticle(after text: String) -> String {
        guard let last = text.last(where: { $0.isLetter || $0.isNumber }) else { return "를" }
        if let scalar = last.unicodeScalars.first, (0xAC00...0xD7A3).contains(scalar.value) {
            return (scalar.value - 0xAC00) % 28 == 0 ? "를" : "을"
        }
        if "013678".contains(last) { return "을" }
        if "LMNRlmnr".contains(last) { return "을" }
        return "를"
    }

    private enum Design {
        static let spineHeight: CGFloat = 411
        static let maxSpineAspectRatio: CGFloat = 0.3
        static let placeholderAspectRatio: CGFloat = 188 / 1644
        static let spineTrailingInset: CGFloat = 78
        static let extraBooksLeftSize = CGSize(width: 298.75, height: 382.75)
        static let extraBooksRightSize = CGSize(width: 79, height: 382.75)
        static let smallLabelHeight: CGFloat = 59
        static let smallLabelBottomInset: CGFloat = 5
        static let largeLabelOrigin = CGPoint(x: 68, y: 166)
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
        static let pullHoldSeconds: Double = 3
    }
}

#if DEBUG

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
}

private func previewSpine(width: CGFloat) -> BookNavigationFeature.SpinePhase {
    let size = CGSize(width: width, height: 411)
    let image = UIGraphicsImageRenderer(size: size).image { context in
        UIColor(red: 0.42, green: 0.27, blue: 0.78, alpha: 1).setFill()
        context.fill(CGRect(origin: .zero, size: size))
    }
    return .loaded(image)
}

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
