import ComposableArchitecture
import SwiftUI

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
        }
    }
}
