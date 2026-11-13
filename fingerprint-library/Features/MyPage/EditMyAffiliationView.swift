//
//  EditMyAffiliationView.swift
//  fingerprint-library
//
//  Created by 이시온 on 11/3/26.
//
//  마이페이지 > 소속 및 학과 정보 변경 화면
//  온보딩의 소속 선택 화면(OnboardingView.affiliation)과 같은 구성을 쓴다.
//

import ComposableArchitecture
import SwiftUI

struct EditMyAffiliationView: View {
    let store: StoreOf<EditMyAffiliationFeature>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if dynamicTypeSize.isAccessibilitySize {
                ScrollView { formContent }
                    .scrollBounceBehavior(.basedOnSize)
            } else {
                formContent
            }
            Spacer()
            changeButton
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
        }
        .padding(.horizontal, 16)
        .background { Color.backgroundDefault.ignoresSafeArea() }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
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
    }

    private var formContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.top, 38)
                .padding(.bottom, 32)
            fields
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: PobookUI.Spacing._4) {
            Text("소속과 학과를 변경할래요")
                .typography(.title1)
                .foregroundStyle(Color.textPrimary)
            Text("학과를 알려주면 관련 분야의 책을\n더 잘 추천할 수 있어요.")
                .typography(.title2)
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var fields: some View {
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

                let isDepartmentEnabled = store.selectedParent != nil && !store.affiliationChoices.isEmpty
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
                        fieldRow(store.selectedAffiliation?.name, placeholder: "학과를 선택해주세요", isEnabled: isDepartmentEnabled)
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
                .foregroundStyle(Color.editAffiliationCaption)
        }
    }

    private func field<Content: View>(title: String, isEnabled: Bool, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .typography(.body2)
                .foregroundStyle(isEnabled ? Color.textPrimary : Color.editAffiliationCaption)
            content()
        }
    }

    private func fieldRow(_ value: String?, placeholder: String, isEnabled: Bool) -> some View {
        let foreground = isEnabled ? Color.textPrimary : Color.editAffiliationDisabledText
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
        .background(
            isEnabled ? Color.editAffiliationField : Color.editAffiliationDisabledField,
            in: .rect(cornerRadius: 20)
        )
    }

    private var changeButton: some View {
        Button {
            store.send(.changeButtonTapped)
        } label: {
            Text("변경하기")
                .typography(.button)
                .multilineTextAlignment(.center)
                .foregroundStyle(store.canSave ? Color.backgroundDefault : Color.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 52)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .glassEffect(
            .regular.tint(store.canSave ? Color.limeBase : Color.editAffiliationActionTint).interactive(),
            in: .capsule
        )
        .disabled(!store.canSave)
    }
}

private extension Color {
    static let editAffiliationField = PobookUI.ColorToken.Field.background
    static let editAffiliationCaption = PobookUI.ColorToken.Field.caption
    static let editAffiliationActionTint = PobookUI.ColorToken.Field.actionTint
    static let editAffiliationDisabledField = PobookUI.ColorToken.Field.disabledBackground
    static let editAffiliationDisabledText = PobookUI.ColorToken.Field.disabledText
}
