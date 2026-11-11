import ComposableArchitecture
import SwiftUI

/// TCA 상태로 지도·층 선택·위치 포커싱과 로딩 상태를 표시한다.
/// MapKit 객체의 생성·갱신은 ``IndoorMapKitView``에 위임한다.
struct IndoorMapView: View {
    struct BookDetailPresentation {
        let floor: IndoorMapFloor?
        let shelves: [IndoorShelfLabel]
        let cameraRequest: IndoorMapCameraRequest?
    }

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
    var showsFloorPicker = true
    /// 하단 안내 카드가 있는 화면에서는 지도·카메라 영역을 카드 위로 제한한다.
    var extendsUnderBottomSafeArea = true
    var bookDetail: BookDetailPresentation?
    var onSelectFavoriteMarker: (HomeMapMarker) -> Void = { _ in }
    /// 별도 지도 Store를 쓰는 미리보기에도 홈과 같은 마커 목록·시설 표시 설정을 전달한다.
    var homeAnnotations: HomeMapAnnotationsFeature.State?
    var hiddenFavoriteMarkerIDs: Set<String> = []

    var body: some View {
        Group {
            if let map = store.map, let floor = bookDetail?.floor ?? store.selectedFloor {
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
                isPlacingOrigin: false, cameraRequest: cameraRequest(for: floor),
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
                highlightedFeatureIDs: bookDetail.map { Set($0.shelves.map(\.mapElementID)) } ?? highlightedFeatureIDs,
                appearance: bookDetail == nil ? appearance : .bookDetail,
                homeMarkers: homeMarkers(on: map),
                onSelectFavoriteMarker: onSelectFavoriteMarker,
                detailShelfLabels: bookDetail?.shelves ?? []
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
                        if showsFloorPicker {
                            floorPicker(map: map, floor: floor)
                        }
                    }
                    if appearance == .home, showsDestinationCard {
                        IndoorRouteControls(store: store)
                    }
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
                    .typography(.caption2)
                    .foregroundStyle(store.homeAnnotations.showsAmenities
                                     ? DS.ColorToken.primaryLight : DS.ColorToken.neutralPrimary)
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
        .accessibilityValue(store.homeAnnotations.showsAmenities ? "전체 시설 표시 중" : "기본 아이콘만 표시 중")
    }

    private func cameraRequest(for floor: IndoorMapFloor) -> IndoorMapCameraRequest? {
        guard let bookDetail else { return store.cameraRequest }
        return bookDetail.cameraRequest ?? .init(id: 0, target: .initialFloor(floor.id))
    }

    private func homeMarkers(on map: IndoorMap) -> [HomeMapMarker] {
        guard appearance == .home || bookDetail != nil else { return [] }
        let annotations = homeAnnotations ?? store.homeAnnotations
        return homeMarkerCache.markers(on: map, labels: store.shelfLabels,
            holdings: annotations.holdings, showsAmenities: annotations.showsAmenities,
            hidingFavoritesFor: bookDetail?.shelves ?? [], hiddenFavoriteMarkerIDs: hiddenFavoriteMarkerIDs)
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

    private func floorPicker(map: IndoorMap, floor: IndoorMapFloor) -> some View {
        IndoorMapFloorPicker(
            floors: map.floors, selectedFloorID: floor.id, appearance: appearance,
            onSelect: { store.send(.floorSelected($0)) })
    }
}
