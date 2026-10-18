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
                Picker(
                    "이동 방법",
                    selection: Binding(
                        get: { store.routePreference }, set: { store.send(.routePreferenceChanged($0)) }
                    )
                ) {
                    Text("최단 거리").tag(RoutePreference.shortestDistance)
                    Text("엘리베이터 우선").tag(RoutePreference.elevatorPreferred)
                }
                .pickerStyle(.segmented)

                if let route = store.route {
                    Text(
                        route.isAlreadyAtDestination
                            ? "등록된 서가 도착점과 출발점이 같아요."
                            : "\(route.usesEstimatedDistances ? "예상 거리" : "경로 거리") 약 \(route.distanceMeters.formatted(.number.precision(.fractionLength(0))))m"
                    )
                    .font(.subheadline.weight(.semibold))
                    .accessibilityIdentifier("route-distance")
                    if !route.floorChanges.isEmpty {
                        Text("층 이동 \(route.floorChanges.count)회 · 층 버튼으로 각 층의 경로를 확인하세요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if route.usesEstimatedDistances {
                        Text("층간 거리는 C5 시연용 추정값입니다.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if route.start.distanceToGraphMeters >= 1 {
                        Text("현재 위치에서 약 \(Int(route.start.distanceToGraphMeters.rounded()))m 떨어진 통로부터 계산했어요.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Text("계산 당시 출발점 기준의 경로 미리보기입니다.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = store.routeError {
                    Text(error).font(.caption).foregroundStyle(.red).accessibilityIdentifier("route-error")
                }
                if store.currentPosition == nil {
                    Text("현재 위치를 확인하고 있어요.").font(.caption).foregroundStyle(.secondary)
                }
                Button {
                    store.send(.routeRequested)
                } label: {
                    HStack {
                        if store.isRouting { ProgressView() }
                        Text(store.route == nil ? "경로 보기" : "현재 위치에서 다시 계산")
                    }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isRouting || store.currentPosition == nil)
                .accessibilityIdentifier("calculate-route")
            }
            .padding(14)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
            .confirmationDialog(
                "엘리베이터 우선 경로가 없어요. 계단을 포함해 다시 찾을까요?",
                isPresented: Binding(
                    get: { store.requiresStairConfirmation },
                    set: {
                        if !$0 { store.send(.dismissStairConfirmation) }
                    }), titleVisibility: .visible
            ) {
                Button("계단 포함해서 찾기") { store.send(.useStairsTapped) }
                Button("취소", role: .cancel) { store.send(.dismissStairConfirmation) }
            }
        }
    }
}
