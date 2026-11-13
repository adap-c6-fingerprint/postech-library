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
    // 칩 영역 아래쪽 블러 높이
    @State private var chipScrollFrame: CGRect = .zero
    // ✅ 칩 영역(ScrollView)의 화면 기준 위치
    @State private var pageBottomInWindow: CGFloat = 0
    // ✅ 화면 맨 아래 끝(하단 안전 영역 포함)의 화면 기준 위치
    @State private var interestsHeaderHeight: CGFloat = 0
    // ✅ 선호 분류 화면 제목 블록(위·아래 여백 포함)의 높이
    private static let termsHeaderTopPadding: CGFloat = 32
    // ✅ 약관 동의 화면 제목 위 여백. 피그마 제목 위치(163)에 맞춘 값 (소속 38 ↔ 168.59 기준)
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
                    .frame(maxWidth: .infinity)
                    .contentShape(.rect)
                    // ✅ 선호 분류 화면에서 페이지 점 뒤로 내려간 칩이 눌리지 않게 막는다.
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
            // ✅ 버튼 아래 밑줄 문구가 있으면 간격 12로 두고, 그만큼 아래 여백을 줄인다.
            // 소속·선호 분류는 피그마 08.-5·08.-6 버튼 위치(784.59, 아래 끝 836.59)에 맞춰 하단 안전 영역(34) 위 3.41만 띄운다.
            .frame(maxWidth: .infinity)
            .contentShape(.rect)
            // ✅ 선호 분류 화면에서 버튼 뒤로 내려간 칩이 버튼 사이 빈 곳에서 눌리지 않게 막는다.
        }
        .onGeometryChange(for: CGFloat.self) { $0.frame(in: .global).maxY + $0.safeAreaInsets.bottom } action: { pageBottomInWindow = $0 }
        // ✅ 화면 맨 아래 끝 위치. 선호 분류 화면 아래쪽 블러 띠의 시작점이다.
        // ✅ 화면마다 내용 아래에 페이지 표시·버튼을 둔다(push 전환 시 화면과 함께 움직인다).
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
        let titleGap = max(interestsHeaderHeight - Self.interestsHeaderTopPadding, 0)
        // 칩 영역 위쪽 경계에서 제목("어떤 책에 끌리나요?") 첫 줄 윗변까지의 거리
        let bottomGap = max(pageBottomInWindow - chipScrollFrame.maxY, 0)
        // 칩 영역 아래쪽 경계에서 화면 맨 아래 끝까지의 거리
        return VStack(alignment: .leading, spacing: 0) {
            header(title: "어떤 책에 끌리나요?",
                   subtitle: "관심 있는 분야를 골라주세요.",
                   topPadding: Self.interestsHeaderTopPadding)
                // 시안 문구에 맞춰 첫 줄 마침표를 뺐다.
                .padding(.horizontal, 16)
                .padding(.bottom, 32 - topBlurHeight)
                // ✅ 기존 gradient 레이어처럼 블러 띠 높이만큼 칩 영역을 위로 넓힌다(제목과 첫 줄 간격 32는 그대로).
                .contentShape(.rect)
                // ✅ 제목 뒤로 올라간 칩이 제목 영역에서 눌리지 않게 막는다.
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { interestsHeaderHeight = $0 }
                .zIndex(1)
                // ✅ 칩과 블러 띠가 제목 뒤로 지나가도 제목은 항상 맨 위에 선명하게 그린다.

            ScrollView {
                ChipFlowLayout(spacing: 8, lineSpacing: 12) {
                    ForEach(store.preferenceNames, id: \.self) { name in
                        chip(name)
                    }
                }
                .padding(.horizontal, 10)
            }
            .contentMargins(.top, topBlurHeight, for: .scrollContent)
            // ✅ 정지 상태에서 첫 줄은 위쪽 블러 띠 아래에 놓여 선명하다(피그마와 같음). 스크롤로 올라갈 때만 흐려진다.
            .scrollIndicators(.hidden)
            // ✅ 칩 영역 오른쪽에 스크롤 바(스크롤 위치 표시 막대)를 보이지 않게 한다.
            .scrollClipDisabled()
            // ✅ 스크롤된 칩이 칩 영역에서 잘리지 않고 제목·버튼 뒤를 지나 보인다.
            .mask(alignment: .top) {
                Rectangle()
                    .frame(height: titleGap + chipScrollFrame.height + bottomGap)
                    .offset(y: -titleGap)
            }
            // ✅ 위쪽 스크롤 영역은 제목 첫 줄 윗변까지만 보이게 자른다. 아래쪽은 화면 맨 아래 끝까지 그대로 보인다.
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { chipScrollFrame = $0 }
            // ✅ 칩 영역의 화면 기준 위치. 화면 끝에서 칩 영역 경계까지의 거리를 구하는 데 쓴다.
            .overlay(alignment: .top) {
                ZStack {
                    OnboardingChipEdgeBlur(edge: .top)

                    LinearGradient(
                        stops: [
                            .init(color: Color.cartBackground, location: 0),
                            .init(color: Color.cartBackground.opacity(0), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                .frame(height: titleGap + topBlurHeight)
                .offset(y: -titleGap)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
            }
            // ✅ 위쪽은 LibraryTopBarBackground처럼 Material 블러 위에 배경색 그라데이션을 한 겹 더 얹는다.
            // 둘 다 제목 첫 줄 윗변이 가장 진하고 칩 영역 안쪽 경계 띠(30)로 갈수록 투명해진다. 배경색이 Material의 뿌연 밝기를 눌러 준다.
            .overlay(alignment: .bottom) {
                OnboardingChipEdgeBlur(edge: .bottom)
                    .frame(height: bottomGap + bottomBlurHeight)
                    .offset(y: bottomGap)
            }
            // ✅ 아래쪽 블러 띠는 화면 맨 아래 끝에서 시작해(가장 진함) 칩 영역 안쪽 경계 띠(30)까지 이어지며 연해진다.
            // 제목은 zIndex로, 페이지 점·버튼은 뒤에 그려지는 형제 뷰라서 블러 위에 선명하게 남는다.
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
//        let isBlocked = !isSelected
//        테스트 결과 preferenceLimit값이 결정되면 주석을 해제함 (밑에 modifier도~)
//        영민이 바보
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
//        .opacity(isBlocked ? 0.4 : 1)
//        .disabled(isBlocked)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
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

private struct OnboardingChipEdgeBlur: View {
    let edge: VerticalEdge

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: edge == .top ? .top : .bottom,
                    endPoint: edge == .top ? .bottom : .top
                )
            }
            // 화면 바깥쪽 끝이 가장 진하고 칩 영역 안쪽으로 갈수록 투명해진다.
            .allowsHitTesting(false)
            // ✅ 블러 띠 위에서도 탭이 아래 칩에 그대로 들어간다.
            .accessibilityHidden(true)
    }
}

// 칩을 넓은 것부터 들어갈 수 있는 첫 줄에 채운다(First-Fit Decreasing). 원래 순서와 달라도 줄 수가 가장 적어지게 조합한다.
// 칩 크기를 매번 측정하므로 기기·화면 크기·글꼴 크기(Dynamic Type)가 바뀌어도 같은 원칙으로 다시 배치된다.
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
