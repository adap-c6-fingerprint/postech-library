import ComposableArchitecture
import SwiftUI

/// TCA 상태로 지도·층 선택·위치 포커싱과 로딩 상태를 표시한다.
/// MapKit 객체의 생성·갱신은 ``IndoorMapKitView``에 위임한다.
struct IndoorMapView: View {
    let store: StoreOf<IndoorMapFeature>
    @State private var homeMarkerCache = HomeMapMarkerCache()
    /// 홈에서는 선택한 서가 카드를, 경로 화면에서는 계산한 경로와 목적지를 표시하도록 구분한다.
    var showsDestinationCard = true
    /// 책 상세에서는 다른 화면에서 계산한 서가·경로를 책 위치로 오인하지 않게 숨긴다.
    var showsRoute = true
    /// 경로 시트가 차지하는 하단 영역. 카메라 맞춤과 지도 조작 UI의 배치에 함께 적용한다.
    var bottomContentInset: CGFloat = 0
    var topContentInset: CGFloat = 0
    var appearance: IndoorMapKitView.Appearance = .standard
    var highlightedFeatureIDs: Set<IndoorMapElement.ID> = []
    var showsCurrentLocationButton = true
    /// 하단 안내 카드가 있는 화면에서는 지도·카메라 영역을 카드 위로 제한한다.
    var extendsUnderBottomSafeArea = true

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
        ZStack(alignment: .bottomTrailing) {
            IndoorMapKitView(
                map: map, floor: floor, selectedFeatureID: nil,
                position: store.currentPosition,
                showsUserLocation: store.showsNativeUserLocation,
                isPlacingOrigin: false, cameraRequest: store.cameraRequest,
                onSelect: { _ in },
                onPlaceOrigin: { _ in },
                shelves: showsDestinationCard
                    ? store.mockShelves : (showsRoute ? store.routeDestination.map { [$0] } ?? [] : []),
                selectedShelfKey: showsDestinationCard
                    ? store.selectedShelfKey : (showsRoute ? store.routeDestinationKey : nil),
                onSelectShelf: { if showsDestinationCard { store.send(.shelfSelected($0)) } },
                route: !showsDestinationCard && showsRoute ? store.route : nil,
                viewportInsets: .init(top: 60 + topContentInset, left: appearance == .home ? 77 : 0,
                                      bottom: bottomContentInset, right: 0),
                shelfLabels: store.shelfLabels,
                highlightedFeatureIDs: highlightedFeatureIDs,
                appearance: appearance,
                homeMarkers: homeMarkers(on: map)
            )
            .ignoresSafeArea(.container, edges: extendsUnderBottomSafeArea ? .bottom : [])

            VStack(alignment: .leading, spacing: 12) {
                if showsCurrentLocationButton, appearance == .standard {
                    HStack {
                        Spacer()
                        currentLocationButton
                    }
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
                HStack(alignment: .bottom, spacing: 12) {
                    VStack(alignment: .leading, spacing: 12) {
                        if appearance == .home { amenitiesButton }
                        floorPicker(map: map, floor: floor)
                    }
                    .frame(width: appearance == .home ? 61 : nil, alignment: .leading)
                    if appearance == .home, showsDestinationCard { IndoorRouteControls(store: store) }
                    Spacer(minLength: 0)
                }
                .padding(.trailing, appearance == .home && showsCurrentLocationButton ? 62 : 0)
                if showsDestinationCard, appearance == .standard {
                    IndoorRouteControls(store: store)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(.leading, 16)
            .padding(.trailing, appearance == .home ? 25 : 16)
            .padding(.top, 16 + topContentInset)
            .padding(.bottom, (appearance == .home ? 20 : 16) + bottomContentInset)

            if appearance == .home, showsCurrentLocationButton {
                currentLocationButton
                    .padding(.trailing, 25)
                    .padding(.bottom, 20 + bottomContentInset)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var amenitiesButton: some View {
        Button { store.send(.homeAnnotations(.amenitiesTapped)) } label: {
            HStack(alignment: .center, spacing: 10) {
                Text("편의시설")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(store.homeAnnotations.showsAmenities
                        ? Color(red: 0.88, green: 0.95, blue: 0.19) : .white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.25)
            }
            .padding(.horizontal, 4)
            .frame(width: 61, height: 34, alignment: .center)
            .background(Color(red: 0.6, green: 0.6, blue: 0.6).opacity(0.17))
            .cornerRadius(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("map-amenities")
        .accessibilityValue(store.homeAnnotations.showsAmenities ? "표시 중" : "숨김")
    }

    private func homeMarkers(on map: IndoorMap) -> [HomeMapMarker] {
        guard appearance == .home else { return [] }
        return homeMarkerCache.markers(on: map, labels: store.shelfLabels,
            holdings: store.homeAnnotations.holdings, showsAmenities: store.homeAnnotations.showsAmenities)
    }

    private var currentLocationButton: some View {
        Button { store.send(.currentLocationTapped) } label: {
            if appearance == .home {
                HStack(alignment: .center, spacing: 4) {
                    Image(systemName: "scope").font(.title3.weight(.medium))
                }
                .padding(0)
                .frame(width: 50, height: 50, alignment: .center)
                .cornerRadius(1000)
                .glassEffect(.regular, in: .circle)
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "scope").font(.title3.weight(.medium))
                    if !showsDestinationCard {
                        Text(currentFloorLabel).font(.subheadline.weight(.medium)).lineLimit(1)
                    }
                }
                .padding(.horizontal, showsDestinationCard ? 0 : 14)
                .frame(minWidth: 48, minHeight: 48)
                .background(Color(uiColor: .systemBackground), in: Capsule())
                .overlay(Capsule().strokeBorder(Color(uiColor: .separator).opacity(0.4)))
                .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("현재 위치로 지도 이동")
        .accessibilityIdentifier("recenter-location")
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

    /// 위층부터 모든 층 버튼을 한 번에 표시하고 각 버튼의 터치 높이를 확보한다.
    private func floorPicker(map: IndoorMap, floor: IndoorMapFloor) -> some View
    {
        let isHome = appearance == .home
        return VStack(alignment: .leading, spacing: 0) {
            ForEach(map.floors.reversed()) { item in
                Button {
                    store.send(.floorSelected(item.id))
                } label: {
                    Text(isHome ? "\(item.ordinal + 1)F" : item.name)
                        .font(.subheadline.weight(item.id == floor.id ? .bold : .regular))
                        .frame(width: isHome ? 61 : 56)
                        .frame(minHeight: 44)
                        .background(
                            item.id == floor.id
                                ? (isHome ? Color(red: 0.88, green: 0.95, blue: 0.19) : Color(uiColor: .label))
                                : Color.clear
                        )
                        .foregroundStyle(
                            item.id == floor.id
                                ? (isHome ? .black : Color(uiColor: .systemBackground))
                                : (isHome ? .white : .primary)
                        )
                        .overlay(alignment: .bottom) {
                            Rectangle().fill(Color(uiColor: .separator).opacity(0.3)).frame(height: 0.5)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(item.name) 지도 보기")
                .accessibilityAddTraits(item.id == floor.id ? [.isSelected] : [])
                .accessibilityIdentifier("floor-\(item.ordinal)")
            }
        }
        .padding(0)
        .frame(width: isHome ? 61 : 56, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(isHome ? .clear : Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .glassEffect(isHome ? .regular : .identity, in: .rect(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12).strokeBorder(Color(uiColor: .separator).opacity(0.6))
        )
        .shadow(color: .black.opacity(isHome ? 0.1 : 0.08), radius: isHome ? 2.5 : 4,
                x: isHome ? 1 : 0, y: isHome ? 1 : 2)
    }
}
