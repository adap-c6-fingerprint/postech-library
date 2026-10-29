import ComposableArchitecture
import SwiftUI

/// 홈 지도에서 선택한 서가의 경로 진입 카드 또는 길찾기 자료의 실패·준비 전 상태를 표시한다.
/// 이 View는 경로를 계산하지 않고 사용자 조작을 TCA Action으로 전달한다.
struct IndoorRouteControls: View {
    let store: StoreOf<IndoorMapFeature>

    var body: some View {
        if let destination = store.routeDestination {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label(destination.name, systemImage: "books.vertical.fill")
                        .font(.subheadline.bold())
                    Spacer()
                    Button {
                        store.send(.routeCleared)
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .accessibilityLabel("경로 닫기")
                }
                Text(store.map?.floors.first { $0.id == destination.floorID }?.name ?? "서가 위치")
                    .font(.caption).foregroundStyle(.secondary)
                Button {
                    store.send(.routeSettingsTapped)
                } label: {
                    Text("경로 보기")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .background(Color(uiColor: .label))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("open-route-settings")
            }
            .padding(16)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
        } else if let message = store.navigationLoadError {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "info.circle")
                    .accessibilityHidden(true)
                Text(message)
                    .font(.caption)
                Spacer(minLength: 0)
                Button("다시 시도") { store.send(.retryNavigationTapped) }
                    .font(.caption.weight(.semibold))
            }
            .padding(12)
            .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
            .accessibilityIdentifier("map-navigation-status")
        }
    }
}
