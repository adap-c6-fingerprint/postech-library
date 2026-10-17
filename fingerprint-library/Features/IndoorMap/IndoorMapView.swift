import ComposableArchitecture
import SwiftUI

struct IndoorMapView: View {
    let store: StoreOf<IndoorMapFeature>
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    @State private var isPanelExpanded = false

    var body: some View {
        Group {
            if let map = store.map, let floor = store.selectedFloor {
                mapContent(map: map, floor: floor)
            } else if store.isLoading {
                ProgressView("실내지도를 불러오고 있어요")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView {
                    Label("지도를 불러오지 못했어요", systemImage: "map")
                } description: {
                    Text("C5 테스트 도면을 준비한 뒤 다시 시도해주세요.")
                } actions: {
                    Button("다시 시도") { store.send(.retryTapped) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .navigationTitle("실내지도")
        .navigationBarTitleDisplayMode(.inline)
        .task { await store.send(.task).finish() }
        .onDisappear { store.send(.disappeared) }
        .onChange(of: scenePhase) { _, phase in store.send(.sceneActiveChanged(phase == .active)) }
    }

    private func mapContent(map: IndoorMap, floor: IndoorMapFloor) -> some View {
        ZStack {
            IndoorMapKitView(
                map: map, floor: floor, selectedFeatureID: store.selectedFeatureID,
                position: store.currentPosition, showsUserLocation: store.showsNativeUserLocation,
                isPlacingOrigin: store.isPlacingOrigin, cameraRequest: store.cameraRequest,
                onSelect: { store.send(.featureSelected($0)) },
                onPlaceOrigin: { store.send(.manualPointSelected($0)) }
            )
            .ignoresSafeArea(edges: .bottom)

            VStack {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("C5 · \(floor.name)").font(.headline)
                        Text("도서관 지도 준비 중 · 임시 지도").font(.caption).foregroundStyle(.secondary)
                    }
                    .padding(12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                    Spacer(minLength: 4)
                    VStack(spacing: 10) {
                        control("지도 전체 보기", symbol: "arrow.up.left.and.arrow.down.right", id: "fit-indoor-map") {
                            store.send(.fitMapTapped)
                        }
                        control("현재 위치", symbol: "location.fill", id: "current-location") {
                            store.send(.currentLocationTapped)
                        }
                    }
                }
                Spacer()
            }
            .padding(12)

            HStack {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(map.floors.reversed()) { item in
                            Button {
                                store.send(.floorSelected(item.id))
                            } label: {
                                Text(item.name)
                                    .font(.subheadline.weight(item.id == floor.id ? .bold : .regular))
                                    .frame(minWidth: 44, minHeight: 44)
                                    .padding(.horizontal, 4)
                                    .background(item.id == floor.id ? Color(uiColor: .label) : Color.clear)
                                    .foregroundStyle(item.id == floor.id ? Color(uiColor: .systemBackground) : .primary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(item.name) 지도 보기")
                            .accessibilityAddTraits(item.id == floor.id ? [.isSelected] : [])
                            .accessibilityIdentifier("floor-\(item.ordinal)")
                        }
                    }
                }
                .frame(width: 60, height: min(CGFloat(map.floors.count) * 44, 264))
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 13))
                .shadow(color: .black.opacity(0.08), radius: 8, y: 2)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 150)
        }
        .overlay(alignment: .bottom) { informationPanel(map: map).padding(10) }
    }

    private func informationPanel(map: IndoorMap) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.snappy) { isPanelExpanded.toggle() }
            } label: {
                Capsule().fill(.tertiary).frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity).frame(height: 20)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isPanelExpanded ? "지도 정보 접기" : "지도 정보 펼치기")

            if let feature = store.selectedFeature {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(feature.name ?? categoryName(feature.category)).font(.headline)
                        Text("\(store.selectedFloor?.name ?? "") · \(categoryName(feature.category))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("닫기", systemImage: "xmark") { store.send(.featureSelected(nil)) }
                        .labelStyle(.iconOnly).frame(width: 44, height: 44)
                }
            } else {
                TimelineView(.periodic(from: .now, by: 5)) { context in
                    VStack(alignment: .leading, spacing: 4) {
                        positionStatus(at: context.date)
                    }
                }
            }

            if let message = store.locationMessage {
                Text(message).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("location-message")
            }

            HStack(spacing: 8) {
                Button(store.isPlacingOrigin ? "출발점 지정 취소" : "출발점 지정", systemImage: "mappin.and.ellipse") {
                    store.send(.manualOriginTapped)
                }
                .accessibilityIdentifier("manual-origin")
                Menu {
                    ForEach(map.floors) { floor in
                        Button(floor.name) { store.send(.manualFloorSelected(floor.id)) }
                    }
                } label: {
                    Label("현재 층 지정", systemImage: "square.3.layers.3d")
                }
                .accessibilityIdentifier("manual-current-floor")
                if store.authorization == .denied || store.authorization == .servicesDisabled {
                    Button("설정") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { openURL(url) }
                    }
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .fixedSize(horizontal: false, vertical: true)

            if isPanelExpanded {
                Divider()
                Text("시설을 눌러 정보를 확인하고, 지도를 길게 눌러 출발점을 지정할 수 있어요.")
                    .font(.subheadline).fixedSize(horizontal: false, vertical: true)
                Text("지도를 두 손가락으로 움직여 회전·기울임을 조절해보세요.")
                    .font(.caption).foregroundStyle(.secondary)
                if store.manualPosition != nil {
                    Text("수동 위치는 현재 위치 버튼을 누를 때까지 유지돼요.")
                        .font(.caption).foregroundStyle(.purple)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        .shadow(color: .black.opacity(0.12), radius: 16, y: 3)
        .gesture(DragGesture(minimumDistance: 20).onEnded { value in
            withAnimation(.snappy) { isPanelExpanded = value.translation.height < 0 }
        })
    }

    @ViewBuilder
    private func positionStatus(at date: Date) -> some View {
        if let position = store.currentPosition, position.isRecent(at: date) {
            let floor = mapFloorName(ordinal: position.floorOrdinal)
            let label = switch position.source {
            case .sensor: "현재 위치"
            case .manual: "수동 출발점"
            case .replay: "테스트 재생 위치"
            }
            Label("\(label) · \(floor)", systemImage: position.source == .manual ? "mappin.circle.fill" : "location.circle.fill")
                .font(.headline)
                .foregroundStyle(position.source == .manual ? .purple : position.source == .replay ? .orange : .blue)
                .accessibilityIdentifier("position-status")
            if position.source == .sensor {
                let accuracy = (position.horizontalAccuracy ?? 0).formatted(.number.precision(.fractionLength(0)))
                Text(position.floorOrdinal == nil ? "층 정보가 없어요. 현재 층을 직접 지정할 수 있어요." : "보고된 위치 정확도 약 \(accuracy)m")
                    .font(.caption).foregroundStyle(.secondary)
            } else if position.source == .replay {
                Text("실제 측위가 아닌 테스트 위치입니다.").font(.caption).foregroundStyle(.secondary)
            }
        } else {
            Text(store.authorization.isAuthorized ? "현재 위치를 기다리고 있어요" : "현재 위치를 켜거나 출발점을 지정해주세요")
                .font(.subheadline.weight(.semibold))
            Text("위치 정보와 지도에서 보고 있는 층은 따로 관리돼요.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func mapFloorName(ordinal: Int?) -> String {
        guard let ordinal else { return "층 정보 없음" }
        return store.map?.floors.first { $0.ordinal == ordinal }?.name ?? "지도에 없는 층"
    }

    private func control(_ label: String, symbol: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.body.weight(.semibold)).frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .background(.regularMaterial, in: Circle())
        .shadow(color: .black.opacity(0.1), radius: 5, y: 2)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }

    private func categoryName(_ category: String?) -> String {
        switch category {
        case "desk": "책상"
        case "stairs": "계단"
        case "elevator": "엘리베이터"
        case "walkway": "통로"
        case "restroom", "restroom.male", "restroom.female", "restroom.wheelchair": "화장실"
        case "breakarea": "휴식 공간"
        case "room": "공간"
        default: "시설"
        }
    }
}
