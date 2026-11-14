//
//  MyPageView.swift
//  fingerprint-library
//  마이페이지 화면
//
//  Created by 이시온 on 11/3/26.
//

import ComposableArchitecture
import SwiftUI

struct MyPageView: View {
    @Bindable var store: StoreOf<MyPageFeature>
    let mapStore: StoreOf<IndoorMapFeature>
    @Environment(\.openURL) private var openURL

    static let privacyPolicyURL = URL(string: "https://link.fpmaps.com/privacy-policy-pobook")!
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                shelfHeader
                    .padding(.horizontal, 16)
                    .padding(.top, 28)
                    .padding(.bottom, 28)
                RecentlyFoundBookShelf(
                    books: store.shelf.books, spines: store.shelf.spines,
                    onTap: { store.send(.addButtonTapped) }
                )
                .padding(.bottom, 20)
                SettingsSection(rows: settingsRows)
                .padding(.horizontal, 16)
                .padding(.bottom, 80)
            }
        }
        .scrollIndicators(.hidden)
        .background { Color.backgroundDefault.ignoresSafeArea() }
        .navigationTitle("마이페이지")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .toolbarBackground(.hidden, for: .navigationBar)
        .task { store.send(.shelf(.task)) }
        .analyticsScreen(.myPage)
        .navigationDestination(
            item: $store.scope(state: \.editAffiliation, action: \.editAffiliation)
        ) { editStore in
            EditMyAffiliationView(store: editStore)
        }
        .navigationDestination(
            item: $store.scope(state: \.editInterests, action: \.editInterests)
        ) { editStore in
            OnboardingView(store: editStore)
        }
        .navigationDestination(
            item: $store.scope(state: \.setupProfile, action: \.setupProfile)
        ) { setupStore in
            OnboardingView(store: setupStore)
        }
        .navigationDestination(
            item: $store.scope(state: \.diagnosticsSessions, action: \.diagnosticsSessions)
        ) { sessionsStore in
            LocationDiagnosticsSessionsView(store: sessionsStore)
        }
    }

    private var settingsRows: [SettingsSection.Row] {
        var rows: [SettingsSection.Row] = [
            .init(title: "소속 및 학과 정보 변경") { store.send(.editAffiliationRowTapped) },
            .init(title: "관심 분야 변경하기") { store.send(.editInterestsRowTapped) },
            .init(title: "위치 권한 설정") { openAppSettings() },
            .init(title: "개인정보 처리방침") { openURL(MyPageView.privacyPolicyURL) }
        ]
        // 실험 브랜치 전용: 검색창 /test 측정 모드가 켜져 있을 때만 보인다(디자인 시안 없이 추가한 항목).
        if store.isLocationDiagnosticsMode {
            rows.append(.init(title: "위치 측정 기록 내보내기") { store.send(.diagnosticsSessionsRowTapped) })
        }
        return rows
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    private var shelfHeader: some View {
        HStack {
            Text("최근 찾은 책 목록")
                .typography(.title2)
                .foregroundStyle(Color.textPrimary)
            Spacer()
            Button {
                store.send(.addButtonTapped)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.textPrimary)
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("최근 찾은 책 목록 전체 보기")
        }
    }
}
