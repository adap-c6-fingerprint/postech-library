import ComposableArchitecture
import SwiftUI

struct IndoorRouteSettingsView: View {
    let store: StoreOf<IndoorMapFeature>
    @ScaledMetric(relativeTo: .body) private var collapsedHeight: CGFloat = 310

    var body: some View {
        VStack(spacing: 0) {
            Text("선택한 서가까지 찾아가요")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
                .background(Color(uiColor: .systemBackground))

            GeometryReader { geometry in
                let height = sheetHeight(in: geometry.size.height)
                ZStack(alignment: .bottom) {
                    IndoorMapView(
                        store: store, showsDestinationCard: false, bottomContentInset: height + 12)
                    routeSheet(height: height)
                }
            }
        }
        .navigationTitle("경로 설정")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .toolbarBackground(Color(uiColor: .systemBackground), for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .confirmationDialog(
            "엘리베이터 우선 경로가 없어요. 계단을 포함해 다시 찾을까요?",
            isPresented: Binding(
                get: { store.requiresStairConfirmation },
                set: { if !$0 { store.send(.dismissStairConfirmation) } }
            ), titleVisibility: .visible
        ) {
            Button("계단 포함해서 찾기") { store.send(.useStairsTapped) }
            Button("취소", role: .cancel) { store.send(.dismissStairConfirmation) }
        }
    }

    private func sheetHeight(in availableHeight: CGFloat) -> CGFloat {
        store.isRouteSheetExpanded
            ? availableHeight * 0.76 : min(collapsedHeight, availableHeight * 0.48)
    }

    private func routeSheet(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                toggleSheet()
            } label: {
                Capsule()
                    .fill(Color(uiColor: .systemGray3))
                    .frame(width: 44, height: 4)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(store.isRouteSheetExpanded ? "방문 순서 접기" : "방문 순서 펼치기")
            .accessibilityIdentifier("route-sheet-toggle")
            .gesture(
                DragGesture(minimumDistance: 15).onEnded { value in
                    if abs(value.translation.height) > 20 {
                        store.send(
                            .routeSheetExpansionChanged(value.translation.height < 0),
                            animation: .easeInOut(duration: 0.25))
                    }
                }
            )

            Text("방문 순서").font(.title3.bold())
            HStack(spacing: 8) {
                if store.isRouting { ProgressView().controlSize(.small) }
                Text(store.routeSummary).font(.subheadline).foregroundStyle(.secondary)
            }
            .padding(.top, 6)
            .padding(.bottom, 16)
            .accessibilityIdentifier("route-distance")

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    visitOrder
                    routeNotes
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .accessibilityIdentifier("route-visit-order")

            VStack(alignment: .leading, spacing: 10) {
                Menu {
                    Button {
                        store.send(.routePreferenceChanged(.shortestDistance))
                    } label: {
                        Label(
                            "최단 거리",
                            systemImage: store.routePreference == .shortestDistance
                                ? "checkmark" : "figure.walk")
                    }
                    Button {
                        store.send(.routePreferenceChanged(.elevatorPreferred))
                    } label: {
                        Label(
                            "엘리베이터 우선",
                            systemImage: store.routePreference == .elevatorPreferred
                                ? "checkmark" : "arrow.up.arrow.down")
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(
                            store.routePreference == .elevatorPreferred ? "엘리베이터 우선경로" : "최단 거리 경로")
                        Image(systemName: "chevron.down").font(.caption.bold())
                    }
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 16)
                    .frame(minHeight: 44)
                    .background(Color(uiColor: .systemBackground), in: Capsule())
                    .overlay(Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.5)))
                }
                .accessibilityIdentifier("route-preference")

                Button {
                    store.send(.routeRequested)
                } label: {
                    Text(store.route == nil ? "경로 다시 찾기" : "현재 위치에서 다시 계산")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 48)
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .background(
                            store.isRouting || store.currentPosition == nil
                                ? Color.gray : Color(uiColor: .label))
                }
                .buttonStyle(.plain)
                .disabled(store.isRouting || store.currentPosition == nil)
                .accessibilityIdentifier("calculate-route")
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .frame(height: height)
        .background(
            Color(uiColor: .systemBackground),
            in: UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
        )
        .shadow(color: .black.opacity(0.06), radius: 12, y: -3)
        .accessibilityIdentifier("route-settings-sheet")
    }

    private var visitOrder: some View {
        VStack(alignment: .leading, spacing: 0) {
            visitRow(title: "출발 위치", detail: startFloorName, isStart: true, isLast: false)
            if let destination = store.routeDestination {
                visitRow(
                    title: destination.name,
                    detail: store.map?.floors.first { $0.id == destination.floorID }?.name ?? "",
                    isStart: false, isLast: true
                )
            }
        }
    }

    private var startFloorName: String {
        if let route = store.route {
            return store.map?.floors.first { $0.id == route.start.floorID }?.name ?? ""
        }
        return store.map?.floors.first { $0.ordinal == store.currentPosition?.floorOrdinal }?.name
            ?? "위치 확인 중"
    }

    private func visitRow(title: String, detail: String, isStart: Bool, isLast: Bool) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(spacing: 0) {
                Circle()
                    .fill(isStart ? Color.blue : Color.blue.opacity(0.2))
                    .frame(width: 18, height: 18)
                    .padding(4)
                    .overlay(Circle().strokeBorder(Color.blue.opacity(0.5)))
                if !isLast {
                    Rectangle()
                        .fill(Color.blue.opacity(0.5))
                        .frame(width: 1, height: 34)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            .padding(.top, 2)
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var routeNotes: some View {
        if let route = store.route {
            if !route.floorChanges.isEmpty {
                Text("층 이동 \(route.floorChanges.count)회 · 층 버튼으로 경로를 확인하세요.")
            }
            if route.usesEstimatedDistances { Text("층간 거리는 C5 시연용 추정값입니다.") }
            if route.start.distanceToGraphMeters >= 1 {
                Text(
                    "출발 위치에서 약 \(Int(route.start.distanceToGraphMeters.rounded()))m 떨어진 통로부터 계산했어요."
                )
            }
        }
        if let error = store.routeError {
            Text(error).foregroundStyle(.red).accessibilityIdentifier("route-error")
        }
        if store.currentPosition == nil { Text("현재 위치 버튼을 눌러 위치를 확인해주세요.") }
    }

    private func toggleSheet() {
        store.send(
            .routeSheetExpansionChanged(!store.isRouteSheetExpanded),
            animation: .easeInOut(duration: 0.25))
    }
}
