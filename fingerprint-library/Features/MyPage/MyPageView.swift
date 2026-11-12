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
    // 최근 찾은 책 화면에서 여는 책 상세에 넘긴다.
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
                // 피그마 주석: + 버튼, 책, 선반 중 어느 곳을 눌러도 최근 찾은 책 화면으로 간다.
                .padding(.bottom, 20)
                SettingsSection(rows: [
                    .init(title: "소속 및 학과 정보 변경") { store.send(.editAffiliationRowTapped) },
                    .init(title: "관심 분야 변경하기") { store.send(.editInterestsRowTapped) },
                    .init(title: "위치 권한 설정") { openAppSettings() },
                    .init(title: "개인정보 처리방침") { openURL(MyPageView.privacyPolicyURL) }
                    // 피그마 09.마이페이지: 온보딩 약관 화면과 같은 개인정보 처리방침 페이지를 연다.
                ])
                // 이용 안내 행은 대응 화면이 없어 눌러도 반응이 없으므로 뺐다. (앱스토어 리젝 사유가 될 수 있음)
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
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }
    // 설정 앱의 Po:Book 페이지를 연다. 이 페이지의 "위치" 항목에서 위치 권한을 바꾼다.
    // iOS는 위치 권한 화면으로 바로 가는 공개 주소를 주지 않아서 앱 설정 페이지까지만 연다.

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
