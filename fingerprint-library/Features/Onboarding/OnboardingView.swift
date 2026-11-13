//
//  OnboardingView.swift
//  fingerprint-library
//

import SwiftUI
import ComposableArchitecture

struct OnboardingView: View {
    @Bindable var store: StoreOf<OnboardingFeature>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private static let chipTopBlurHeight: CGFloat = 30
    private static let chipBottomBlurHeight: CGFloat = 30
    private static let chipScrollSpace = "onboardingChipScroll"
    @State private var chipViewportHeight: CGFloat = .infinity
    private static let affiliationHeaderTopPadding: CGFloat = 46
    private static let interestsHeaderTopPadding: CGFloat = 30

    var body: some View {
        Group {
            switch store.entry {
            case .firstRun:
                NavigationStack(path: navigationPath) {
                    page(.welcome)
                        .toolbar(.hidden, for: .navigationBar)
                        .navigationDestination(for: OnboardingFeature.Step.self) { step in
                            page(step)
                        }
                }
            case .changeInterests:
                page(.interests)
                    .toolbar(.visible, for: .navigationBar)
                    .toolbar(.hidden, for: .tabBar)
            case .setupFromMyPage:
                page(.affiliation)
                    .toolbar(.visible, for: .navigationBar)
                    .toolbar(.hidden, for: .tabBar)
                    .navigationDestination(isPresented: setupInterestsPresented) {
                        page(.interests)
                    }
            }
        }
        .preferredColorScheme(.dark)
        .alert(
            "저장하지 못했어요",
            isPresented: Binding(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.send(.errorAlertDismissed) } }
            )
        ) {
            Button("확인") {}
        } message: {
            Text(store.errorMessage ?? "")
        }
        .alert($store.scope(state: \.alert, action: \.alert))
        .overlay {
            if store.isSkipNoticePresented {
                skipNoticePopup
            }
        }
        .task { store.send(.task) }
    }

    private var navigationPath: Binding<[OnboardingFeature.Step]> {
        Binding(
            get: { OnboardingFeature.Step.allCases.filter { $0 != .welcome && $0.rawValue <= store.step.rawValue } },
            set: { newPath in
                let poppedCount = store.step.rawValue - newPath.count
                for _ in 0..<max(poppedCount, 0) {
                    store.send(.backButtonTapped)
                }
            }
        )
    }

    private var setupInterestsPresented: Binding<Bool> {
        Binding(
            get: { store.step == .interests },
            set: { if !$0, store.step == .interests, !store.isCompleted { store.send(.backButtonTapped) } }
        )
    }

    private func page(_ step: OnboardingFeature.Step) -> some View {
        VStack(spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize, step != .interests {
                ScrollView { pageContent(step) }
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                pageContent(step)
            }

            if Self.indicatorSteps.contains(step) {
                pageIndicator(step)
                    .padding(.bottom, 30)
            }
            let link = bottomLink(step)
            VStack(spacing: 12) {
                actionButton(step)
                if let link {
                    textLinkButton(link.title) { store.send(link.action) }
                }
            }
            .padding(.horizontal, 36)
            .padding(.bottom, link != nil ? 12 : (Self.indicatorSteps.contains(step) ? 3.41 : 24))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.cartBackground)
        .contentShape(.rect)
        .simultaneousGesture(step == .affiliation ? nextSwipeGesture : nil)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(!isBackButtonVisible(step))
    }

    private var nextSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 30)
            .onEnded { value in
                let dx = value.translation.width
                let dy = value.translation.height
                guard dx < -60, abs(dx) > abs(dy) * 1.5 else { return }
                guard store.isAffiliationComplete else { return }
                store.send(.nextButtonTapped)
            }
    }

    @ViewBuilder
    private func pageContent(_ step: OnboardingFeature.Step) -> some View {
        switch step {
        case .welcome: welcome
        case .affiliation: affiliation
        case .interests: interests
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(
                title: "읽고 싶은 책까지,\nPo:Book이 이어줄게요 📚📍",
                subtitle: "내 취향에 맞는 책을 발견하고\n도서관에서 쉽게 찾아보세요.",
                subtitleTypography: .bookTitle,
                spacing: 8,
                topPadding: 100
            )
            .padding(.horizontal, 20)

            Spacer()
            Image("PobookLogo")
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }


    private func bottomLink(_ step: OnboardingFeature.Step) -> (title: String, action: OnboardingFeature.Action)? {
        switch step {
        case .affiliation where store.entry == .firstRun:
            ("다음에 할래요", .skipButtonTapped)
        default:
            nil
        }
    }

    private func textLinkButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .typography(.body2)
                .underline()
                .foregroundStyle(Color.onboardingTextLink)
                .frame(maxWidth: .infinity)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var affiliation: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(
                title: "입력한 정보를 바탕으로\n내게 더 잘 맞는 책을 보여드릴게요.",
                subtitle: "소속과 학과를 알려주세요",
                spacing: 8,
                topPadding: Self.affiliationHeaderTopPadding
            )
            .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 24) {
                    let isParentEnabled = !store.parents.isEmpty
                    field(title: "소속", isEnabled: isParentEnabled) {
                        Menu {
                            ForEach(store.parents, id: \.self) { parent in
                                Button(parent) { store.send(.parentSelected(parent)) }
                            }
                        } label: {
                            fieldRow(store.selectedParent, placeholder: "소속을 선택해주세요", isEnabled: isParentEnabled)
                        }
                        .disabled(!isParentEnabled)
                    }

                    let isDepartmentEnabled = store.selectedParent != nil
                    field(title: "학과", isEnabled: isDepartmentEnabled) {
                        Menu {
                            ForEach(store.groups, id: \.self) { group in
                                Section(group) {
                                    ForEach(store.state.affiliationChoices(in: group), id: \.self) { path in
                                        Button(path.name) { store.send(.affiliationSelected(path)) }
                                    }
                                }
                            }
                        } label: {
                            fieldRow(
                                store.selectedAffiliation?.name,
                                placeholder: "학과를 선택해주세요",
                                isEnabled: isDepartmentEnabled
                            )
                        }
                        .disabled(!isDepartmentEnabled)
                    }
                }

                if let message = store.optionsErrorMessage {
                    Text("선택지를 불러오지 못했어요. \(message)")
                        .typography(.caption2)
                        .foregroundStyle(.red)
                }

                Text("*소속과 학과는 나중에 변경 가능해요.")
                    .typography(.caption2)
                    .foregroundStyle(Color.onboardingCaption)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var interests: some View {
        let topBlurHeight = Self.chipTopBlurHeight
        let bottomBlurHeight = Self.chipBottomBlurHeight
        let viewportHeight = chipViewportHeight
        let scrollSpace = Self.chipScrollSpace
        return VStack(alignment: .leading, spacing: 0) {
            header(title: "어떤 책에 끌리나요?",
                   subtitle: "관심 있는 분야를 골라주세요\n최대 \(OnboardingFeature.maxPreferenceCount)개까지 선택할 수 있어요",
                   topPadding: Self.interestsHeaderTopPadding)
                .padding(.horizontal, 16)
                .padding(.bottom, 32 - topBlurHeight)

            ScrollView {
                ChipFlowLayout(spacing: 8, lineSpacing: 12) {
                    ForEach(store.preferenceNames, id: \.self) { name in
                        chip(name)
                            .visualEffect { content, proxy in
                                let frame = proxy.frame(in: .named(scrollSpace))
                                let isUnderEdge = frame.midY < topBlurHeight || frame.midY > viewportHeight - bottomBlurHeight
                                return content.blur(radius: isUnderEdge ? 5 : 0)
                            }
                    }
                }
                .padding(.horizontal, 10)
            }
            .contentMargins(.top, topBlurHeight, for: .scrollContent)
            .coordinateSpace(.named(Self.chipScrollSpace))
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { chipViewportHeight = $0 }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var skipNoticePopup: some View {
        ZStack {
            Color.black.opacity(0.2)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("맞춤 정보 설정을 건너뛰었어요.")
                        .font(.body.weight(.semibold))
                    Text("마이페이지에서 언제든지\n다시 설정할 수 있어요.")
                        .font(.body)
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 24)

                Button {
                    store.send(.skipNoticeConfirmed)
                } label: {
                    Text("확인했어요")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color.limeBase, in: .capsule)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
            }
            .padding(14)
            .frame(width: 300)
            .background(.white, in: .rect(cornerRadius: 34))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityAddTraits(.isModal)
        }
    }

    private func header(
        title: String,
        subtitle: String,
        subtitleTypography: PobookUI.Typography = .title2,
        spacing: CGFloat = PobookUI.Spacing._4,
        topPadding: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: spacing) {
            Text(title)
                .typography(.title1)
                .foregroundStyle(Color.onboardingTextPrimary)
            Text(subtitle)
                .typography(subtitleTypography)
                .foregroundStyle(Color.textTertiary)
        }
        .padding(.top, topPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
    }



    private func isBackButtonVisible(_ step: OnboardingFeature.Step) -> Bool {
        switch step {
        case .welcome: false
        case .affiliation: true
        case .interests: true
        }
    }

    private func field<Content: View>(title: String, isEnabled: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .typography(.body2)
                .foregroundStyle(isEnabled ? Color.onboardingTextPrimary : Color.onboardingCaption)
            content()
        }
    }

    private func fieldRow(_ value: String?, placeholder: String, isEnabled: Bool) -> some View {
        let foreground = isEnabled ? Color.onboardingTextPrimary : Color.onboardingDisabledText
        return HStack {
            Text(value ?? placeholder)
                .typography(.body2)
                .foregroundStyle(foreground)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(foreground)
                .accessibilityHidden(true)
        }
        .padding(.leading, 20)
        .padding(.trailing, 23)
        .frame(minHeight: 52)
        .background(isEnabled ? Color.onboardingField : Color.onboardingDisabledField, in: .rect(cornerRadius: 20))
    }

    private func chip(_ name: String) -> some View {
        let isSelected = store.selectedPreferences.contains(name)
        let isBlocked = !isSelected && store.isPreferenceLimitReached
        return Button {
            store.send(.preferenceToggled(name))
        } label: {
            Text(name)
                .typography(.body2)
                .foregroundStyle(isSelected ? Color.cartBackground : Color.onboardingTextPrimary)
                .padding(.horizontal, 25)
                .frame(minHeight: 52)
                .contentShape(.capsule)
                .background(isSelected ? Color.cartPrimary : Color.onboardingField, in: .capsule)
        }
        .buttonStyle(.plain)
        .opacity(isBlocked ? 0.4 : 1)
        .disabled(isBlocked)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityHint(isBlocked ? "최대 \(OnboardingFeature.maxPreferenceCount)개까지 선택할 수 있어요" : "")
    }

    private static let indicatorSteps: [OnboardingFeature.Step] = [.affiliation, .interests]

    private func pageIndicator(_ page: OnboardingFeature.Step) -> some View {
        HStack(spacing: 9) {
            ForEach(Self.indicatorSteps, id: \.self) { step in
                Circle()
                    .fill(Color.onboardingTextPrimary.opacity(step == page ? 1 : 0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\((Self.indicatorSteps.firstIndex(of: page) ?? 0) + 1) / \(Self.indicatorSteps.count) 단계")
    }

    private func actionButton(_ step: OnboardingFeature.Step) -> some View {
        let isPrimary = (step == .affiliation && store.isAffiliationComplete)
            || (step == .interests && store.canFinish)
        return Button {
            switch step {
            case .welcome: store.send(.startButtonTapped)
            case .affiliation: store.send(.nextButtonTapped)
            case .interests: store.send(.finishButtonTapped)
            }
        } label: {
            Text(actionTitle(step))
                .font(.body.weight(.semibold))
                .foregroundStyle(isPrimary ? Color.cartBackground : Color.onboardingTextPrimary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(isPrimary ? Color.cartPrimary : Color.onboardingActionTint).interactive(),
            in: .capsule
        )
        .disabled(!isActionEnabled(step))
    }

    private func actionTitle(_ step: OnboardingFeature.Step) -> String {
        switch step {
        case .welcome: "시작하기"
        case .affiliation: store.isAffiliationComplete ? "다음으로" : "선택을 완료해주세요"
        case .interests: store.canFinish ? "시작하기" : "선택을 완료해주세요"
        }
    }

    private func isActionEnabled(_ step: OnboardingFeature.Step) -> Bool {
        switch step {
        case .welcome: true
        case .affiliation: store.isAffiliationComplete
        case .interests: store.canFinish
        }
    }
}

private struct ChipFlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = rows(for: subviews, width: proposal.width ?? .infinity)
        let height = rows.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(for: subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func rows(for subviews: Subviews, width: CGFloat) -> [Row] {
        let sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        let widestFirst = subviews.indices.sorted { sizes[$0].width != sizes[$1].width ? sizes[$0].width > sizes[$1].width : $0 < $1 }
        var rows: [Row] = []
        for index in widestFirst {
            let size = sizes[index]
            if let rowIndex = rows.firstIndex(where: { $0.width + spacing + size.width <= width }) {
                rows[rowIndex].width += spacing + size.width
                rows[rowIndex].height = max(rows[rowIndex].height, size.height)
                rows[rowIndex].indices.append(index)
            } else {
                rows.append(Row(indices: [index], width: size.width, height: size.height))
            }
        }
        for rowIndex in rows.indices {
            rows[rowIndex].indices.sort()
        }
        return rows
    }
}

private extension Color {
    static let onboardingTextPrimary = Color.textPrimary
    static let onboardingField = PobookUI.ColorToken.Field.background
    static let onboardingCaption = PobookUI.ColorToken.Field.caption
    static let onboardingActionTint = PobookUI.ColorToken.Field.actionTint
    static let onboardingDisabledField = PobookUI.ColorToken.Field.disabledBackground
    static let onboardingDisabledText = PobookUI.ColorToken.Field.disabledText
    static let onboardingTextLink = PobookUI.ColorPrimitive.Grayscale._300
}


#Preview("08-1 시작") {
    OnboardingView(
        store: Store(initialState: OnboardingFeature.State()) { OnboardingFeature() }
    )
}

#Preview("08-3 소속") {
    OnboardingView(
        store: Store(initialState: {
            var state = OnboardingFeature.State()
            state.step = .affiliation
            return state
        }()) { OnboardingFeature() }
    )
}

#Preview("08-5 선호 분류") {
    OnboardingView(
        store: Store(initialState: {
            var state = OnboardingFeature.State()
            state.step = .interests
            return state
        }()) { OnboardingFeature() }
    )
}
