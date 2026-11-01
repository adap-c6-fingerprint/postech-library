//
//  OnboardingView.swift
//  fingerprint-library
//

import SwiftUI
import ComposableArchitecture

struct OnboardingView: View {
    let store: StoreOf<OnboardingFeature>

    var body: some View {
        VStack(spacing: 0) {
            switch store.step {
            case .welcome: welcome
            case .affiliation: affiliation
            case .interests: interests
            }

            pageIndicator
                .padding(.bottom, 20)
            actionButton
                .padding(.horizontal, 36)
                .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.basketBackground)
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
        .task { store.send(.task) }
        // ✅ 소속·선호 분류 선택지를 앱에 넣은 하드데이터에서 읽는다.
    }

    // MARK: - 단계별 화면

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(
                title: "읽고 싶은 책까지,\nPo:Book이 이어줄게요 📚📍",
                subtitle: "내 취향에 맞는 책을 발견하고\n도서관에서 쉽게 찾아보세요."
            )
            .padding(.horizontal, 20)

            Spacer()
            Image("PobookLogo")
                .frame(maxWidth: .infinity)
            Spacer()
        }
    }

    private var affiliation: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(
                title: "소속을 알려주세요",
                subtitle: "소속을 알려주면 관련 분야의 책을\n더 잘 추천할 수 있어요."
            )
            .padding(.bottom, 32)

            // ✅ 상위 소속 → 그룹 → 최종 소속 3단계로 고른다. 앞 단계를 고르기 전에는 다음 단계를 고를 수 없다.
            VStack(alignment: .leading, spacing: 24) {
                field(title: "소속") {
                    Menu {
                        ForEach(store.parents, id: \.self) { parent in
                            Button(parent) { store.send(.parentSelected(parent)) }
                        }
                    } label: {
                        fieldRow(store.selectedParent, placeholder: "소속을 선택해주세요", isEnabled: !store.parents.isEmpty)
                    }
                    .disabled(store.parents.isEmpty)
                }

                field(title: "세부 분류") {
                    Menu {
                        ForEach(store.groups, id: \.self) { group in
                            Button(group) { store.send(.groupSelected(group)) }
                        }
                    } label: {
                        fieldRow(store.selectedGroup, placeholder: "세부 분류를 선택해주세요", isEnabled: store.selectedParent != nil)
                    }
                    .disabled(store.selectedParent == nil)
                }

                field(title: "학과·부서") {
                    Menu {
                        ForEach(store.affiliationChoices, id: \.self) { path in
                            Button(path.name) { store.send(.affiliationSelected(path)) }
                        }
                    } label: {
                        fieldRow(
                            store.selectedAffiliation?.name,
                            placeholder: "학과·부서를 선택해주세요",
                            isEnabled: store.selectedGroup != nil
                        )
                    }
                    .disabled(store.selectedGroup == nil)
                }

                if let message = store.optionsErrorMessage {
                    Text("선택지를 불러오지 못했어요. \(message)")
                        .font(.system(size: 12))
                        .foregroundStyle(.red)
                }

                Text("*소속은 나중에 변경 가능해요.")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.onboardingCaption)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
    }

    private var interests: some View {
        VStack(alignment: .leading, spacing: 0) {
            header(title: "어떤 책에 끌리나요?", subtitle: "관심 있는 분야를 골라주세요")
                .padding(.horizontal, 6)
                .padding(.bottom, 32)

            ScrollView {
                ChipFlowLayout(spacing: 8, lineSpacing: 12) {
                    ForEach(store.preferenceNames, id: \.self) { name in
                        chip(name)
                    }
                    // ✅ 도서관 분류(LCC) 대신 서점 기준 선호 분류 20개를 보여준다.
                }
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .padding(.horizontal, 10)
    }

    // MARK: - 구성 요소

    private func header(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Color.onboardingTextPrimary)
            Text(subtitle)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.basketTextTertiary)
        }
        .lineSpacing(6)
        .padding(.top, 100)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func field<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(Color.onboardingTextPrimary)
            content()
        }
    }

    private func fieldRow(_ value: String?, placeholder: String, isEnabled: Bool) -> some View {
        HStack {
            Text(value ?? placeholder)
                .font(.system(size: 16))
                .foregroundStyle(Color.onboardingTextPrimary)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Color.onboardingTextPrimary)
        }
        .padding(.leading, 20)
        .padding(.trailing, 23)
        .frame(height: 52)
        .background(Color.onboardingField, in: .rect(cornerRadius: 20))
        .opacity(isEnabled ? 1 : 0.4)
    }

    private func chip(_ name: String) -> some View {
        let isSelected = store.selectedPreferences.contains(name)
        return Button {
            store.send(.preferenceToggled(name))
        } label: {
            Text(name)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? Color.basketBackground : Color.onboardingTextPrimary)
                .padding(.horizontal, 25)
                .frame(height: 52)
                .contentShape(.capsule)
                .background(isSelected ? Color.basketPrimary : Color.onboardingField, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var pageIndicator: some View {
        HStack(spacing: 9) {
            ForEach(OnboardingFeature.Step.allCases, id: \.self) { step in
                Circle()
                    .fill(Color.onboardingTextPrimary.opacity(step == store.step ? 1 : 0.3))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("\(store.step.rawValue + 1) / \(OnboardingFeature.Step.allCases.count) 단계")
    }

    private var actionButton: some View {
        let isPrimary = store.step == .interests && store.canFinish
        // 관심사를 하나 이상 고르면 버튼을 강조색으로 바꾼다.
        return Button {
            switch store.step {
            case .welcome: store.send(.startButtonTapped)
            case .affiliation: store.send(.nextButtonTapped)
            case .interests: store.send(.finishButtonTapped)
            }
        } label: {
            Text(actionTitle)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(isPrimary ? Color.basketBackground : Color.onboardingTextPrimary)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(isPrimary ? Color.basketPrimary : Color.onboardingActionTint).interactive(),
            in: .capsule
        )
        .disabled(!isActionEnabled)
    }

    private var actionTitle: String {
        switch store.step {
        case .welcome: "시작하기"
        case .affiliation: store.isAffiliationComplete ? "다음으로" : "선택을 완료해주세요"
        case .interests: "시작하기"
        }
    }

    private var isActionEnabled: Bool {
        switch store.step {
        case .welcome: true
        case .affiliation: store.isAffiliationComplete
        case .interests: store.canFinish
        }
    }
    // ✅ 학부·대학원별 학과 묶음(departmentSections)은 하드데이터의 세부 분류로 대체했다.
}

// 칩을 한 줄에 들어가는 만큼 놓고 넘치면 다음 줄로 넘긴다.
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
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextWidth = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if nextWidth > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

// 피그마 온보딩 시안의 색상 토큰 (배경·강조색은 장바구니 토큰을 함께 쓴다)
private extension Color {
    static let onboardingTextPrimary = Color(red: 0xF9 / 255, green: 0xF9 / 255, blue: 0xF9 / 255)
    static let onboardingField = Color(red: 0x24 / 255, green: 0x24 / 255, blue: 0x24 / 255)
    static let onboardingCaption = Color(red: 0x77 / 255, green: 0x77 / 255, blue: 0x77 / 255)
    static let onboardingActionTint = Color(red: 0x33 / 255, green: 0x33 / 255, blue: 0x33 / 255)
}
