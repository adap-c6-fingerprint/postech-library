import ComposableArchitecture
import SwiftUI

/// TCA 상태로 지도·층 선택·위치 포커싱과 로딩 상태를 표시한다.
/// MapKit 객체의 생성·갱신은 ``IndoorMapKitView``에 위임한다.
struct IndoorMapView: View {
    let store: StoreOf<IndoorMapFeature>
    /// 홈에서는 선택한 서가 카드를, 경로 화면에서는 계산한 경로와 목적지를 표시하도록 구분한다.
    var showsDestinationCard = true
    /// 경로 시트가 차지하는 하단 영역. 카메라 맞춤과 지도 조작 UI의 배치에 함께 적용한다.
    var bottomContentInset: CGFloat = 0

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
                    Text(store.loadError ?? "도서관 지도를 불러올 수 없어요. 다시 시도해주세요.")
                } actions: {
                    Button("다시 시도") { store.send(.retryTapped) }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
    }

    /// 지도 위에 조작 UI를 배치하고, 실제 위치의 층과 별개인 조회 층을 전달한다.
    private func mapContent(map: IndoorMap, floor: IndoorMapFloor) -> some View {
        GeometryReader { geometry in
            ZStack {
                IndoorMapKitView(
                    map: map, floor: floor, selectedFeatureID: nil,
                    position: store.currentPosition,
                    showsUserLocation: store.showsNativeUserLocation,
                    isPlacingOrigin: false, cameraRequest: store.cameraRequest,
                    onSelect: { _ in },
                    onPlaceOrigin: { _ in },
                    shelves: showsDestinationCard
                        ? store.mockShelves : store.routeDestination.map { [$0] } ?? [],
                    selectedShelfKey: showsDestinationCard
                        ? store.selectedShelfKey : store.routeDestinationKey,
                    onSelectShelf: { if showsDestinationCard { store.send(.shelfSelected($0)) } },
                    route: showsDestinationCard ? nil : store.route,
                    viewportInsets: .init(top: 60, left: 0, bottom: bottomContentInset, right: 0),
                    shelfLabels: store.shelfLabels
                )
                .ignoresSafeArea(.container, edges: .bottom)

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Spacer()
                        Button {
                            store.send(.currentLocationTapped)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "scope")
                                    .font(.title3.weight(.medium))
                                if !showsDestinationCard {
                                    Text(currentFloorLabel)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                }
                            }
                            .padding(.horizontal, showsDestinationCard ? 0 : 14)
                            .frame(minWidth: 48, minHeight: 48)
                            .background(Color(uiColor: .systemBackground), in: Capsule())
                            .overlay(
                                Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.4))
                            )
                            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("현재 위치로 지도 이동")
                        .accessibilityIdentifier("recenter-location")
                    }

                    if let message = store.locationMessage {
                        Text(message)
                            .font(.caption)
                            .padding(10)
                            .background(
                                Color(uiColor: .systemBackground),
                                in: RoundedRectangle(cornerRadius: 12)
                            )
                            .accessibilityIdentifier("map-location-status")
                    }

                    if let message = store.shelfLabelError {
                        HStack {
                            Text(message)
                            Button("다시 시도") { store.send(.retryShelfLabelsTapped) }
                        }
                        .font(.caption)
                        .padding(10)
                        .background(Color(uiColor: .systemBackground), in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityIdentifier("map-shelf-label-status")
                    }

                    Spacer(minLength: 0)
                    floorPicker(
                        map: map, floor: floor,
                        maxHeight: max(44, geometry.size.height - bottomContentInset - 200)
                    )
                    if showsDestinationCard {
                        IndoorRouteControls(store: store)
                    }
                }
                .padding(16)
                .padding(.bottom, bottomContentInset)
            }
        }
    }

    /// 실제 위치의 ordinal에 대응하는 표시 이름을 사용한다. 조회 중인 층을 현재 위치로 표시하지 않는다.
    private var currentFloorLabel: String {
        guard let ordinal = store.currentPosition?.floorOrdinal,
            let floor = store.map?.floors.first(where: { $0.ordinal == ordinal })
        else {
            return "현재 위치 확인"
        }
        return "현재위치 · \(floor.name)"
    }

    /// 위층부터 층 버튼을 표시하고 작은 표시 영역에서는 선택한 층을 스크롤로 드러낸다.
    private func floorPicker(map: IndoorMap, floor: IndoorMapFloor, maxHeight: CGFloat) -> some View
    {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(map.floors.reversed()) { item in
                        Button {
                            store.send(.floorSelected(item.id))
                        } label: {
                            Text(item.name)
                                .font(.subheadline.weight(item.id == floor.id ? .bold : .regular))
                                .frame(width: 56, height: 44)
                                .background(
                                    item.id == floor.id ? Color(uiColor: .label) : Color.clear
                                )
                                .foregroundStyle(
                                    item.id == floor.id
                                        ? Color(uiColor: .systemBackground) : .primary
                                )
                                .overlay(alignment: .bottom) {
                                    Rectangle().fill(Color(uiColor: .separator).opacity(0.3)).frame(
                                        height: 0.5)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(item.name) 지도 보기")
                        .accessibilityAddTraits(item.id == floor.id ? [.isSelected] : [])
                        .accessibilityIdentifier("floor-\(item.ordinal)")
                        .id(item.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .frame(width: 56, height: min(CGFloat(map.floors.count) * 44, maxHeight))
            .background(Color(uiColor: .systemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    Color(uiColor: .separator).opacity(0.6))
            )
            .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
            .onAppear { proxy.scrollTo(floor.id, anchor: .center) }
            .onChange(of: floor.id) { _, id in proxy.scrollTo(id, anchor: .center) }
            .onChange(of: maxHeight) { _, _ in proxy.scrollTo(floor.id, anchor: .center) }
        }
    }
}
