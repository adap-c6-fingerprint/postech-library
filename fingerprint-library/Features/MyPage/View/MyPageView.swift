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
    @State private var showsAnalyticsSettings = false
    // 최근 찾은 책 화면에서 여는 책 상세에 넘긴다.

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
                .padding(.bottom, 38)
                // 피그마: 선반 아래 끝(408.8)과 "설정 및 안내"(447) 사이 간격
                SettingsSection(rows: [
                    .init(title: "소속 및 학과 정보 변경") { store.send(.editAffiliationRowTapped) },
                    .init(title: "관심 분야 변경하기") { store.send(.editInterestsRowTapped) },
                    .init(title: "데이터 수집 설정") { showsAnalyticsSettings = true },
                    .init(title: "위치 권한 설정"),
                    .init(title: "이용 안내")
                ])
                // 위치 권한 설정·이용 안내는 아직 기능명세가 없어 행만 둔다.
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
        .sheet(isPresented: $showsAnalyticsSettings) {
            AnalyticsSettingsView(isFirstChoice: false)
        }
        .navigationDestination(
            item: $store.scope(state: \.recentlyFound, action: \.recentlyFound)
        ) { recentlyFoundStore in
            RecentlyFoundBookView(store: recentlyFoundStore, mapStore: mapStore)
        }
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
