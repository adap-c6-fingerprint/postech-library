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
                title: "소속과 학과를 알려주세요",
                subtitle: "학과를 알려주면 관련 분야의 책을\n더 잘 추천할 수 있어요."
            )
            .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 24) {
                field(title: "소속") {
                    Menu {
                        ForEach(PostechStatus.allCases) { status in
                            Button(status.koreanName) { store.send(.statusSelected(status)) }
                        }
                    } label: {
                        fieldRow(store.status?.koreanName, placeholder: "소속을 선택해주세요", isEnabled: true)
                    }
                }

                if store.status?.requiresDepartment ?? true {
                    field(title: "학과") {
                        Menu {
                            ForEach(departmentSections, id: \.title) { section in
                                Section(section.title) {
                                    ForEach(section.departments, id: \.self) { department in
                                        Button(department.koreanName) {
                                            store.send(.departmentSelected(department))
                                        }
                                    }
                                }
                            }
                        } label: {
                            fieldRow(
                                store.department?.koreanName,
                                placeholder: "학과를 선택해주세요",
                                isEnabled: store.status != nil
                            )
                        }
                        .disabled(store.status == nil)
                        // 소속을 고르기 전에는 학과를 고를 수 없다.
                    }
                }

                Text("*소속과 학과는 나중에 변경 가능해요.")
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
                    ForEach(UserInterest.allCases) { interest in
                        chip(interest)
                    }
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

    private func chip(_ interest: UserInterest) -> some View {
        let isSelected = store.selectedInterests.contains(interest)
        return Button {
            store.send(.interestToggled(interest))
        } label: {
            Text(interest.koreanName)
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? Color.basketBackground : Color.onboardingTextPrimary)
                .padding(.horizontal, 25)
                .frame(height: 52)
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
        // 관심사를 하나 이상 고르면 시작하기 버튼을 강조색으로 바꾼다.
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

    private var departmentSections: [(title: String, departments: [PostechDepartment])] {
        switch store.status {
        case .undergraduate:
            PostechDepartment.Undergraduate.Field.allCases.map { field in
                (title: field.koreanName, departments: PostechDepartment.Undergraduate.allCases
                    .filter { $0.field == field }
                    .map(PostechDepartment.undergraduate))
            }
        case .graduate:
            PostechDepartment.Graduate.School.allCases.map { school in
                (title: school.koreanName, departments: PostechDepartment.Graduate.allCases
                    .filter { $0.school == school }
                    .map(PostechDepartment.graduate))
            }
        case .staff, .appleDeveloperAcademy, nil:
            []
        }
    }
    // 학부는 계열별, 대학원은 대학원 종류별로 묶어 보여준다.
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
