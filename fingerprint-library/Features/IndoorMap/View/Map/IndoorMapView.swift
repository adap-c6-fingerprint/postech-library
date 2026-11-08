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

    /// 남은 높이에 세로 목록이 들어가지 않으면 가로로 펼쳐 스크롤 없이 모든 층을 표시한다.
    private func floorPicker(map: IndoorMap, floor: IndoorMapFloor) -> some View
    {
        let isHome = appearance == .home
        let height = CGFloat(map.floors.count) * 34
        return ViewThatFits(in: .vertical) {
            VStack(alignment: .leading, spacing: 0) {
                floorButtons(map: map, floor: floor)
            }
            .padding(0)
            .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            .frame(width: isHome ? 61 : 56)
            HStack(spacing: 0) {
                floorButtons(map: map, floor: floor)
            }
            .fixedSize()
        }
        .background(isHome ? .clear : Color(uiColor: .systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.floorAmenitiesToggle))
        .glassEffect(isHome ? .regular : .identity, in: .rect(cornerRadius: DS.Radius.floorAmenitiesToggle))
        .overlay {
            GeometryReader { geometry in
                if map.floors.count > 1 {
                    Path { path in
                        let size = geometry.size
                        let horizontal = size.width > size.height
                        for index in 1..<map.floors.count {
                            let fraction = CGFloat(index) / CGFloat(map.floors.count)
                            if horizontal {
                                let x = size.width * fraction
                                path.move(to: CGPoint(x: x, y: 0))
                                path.addLine(to: CGPoint(x: x, y: size.height))
                            } else {
                                let y = size.height * fraction
                                path.move(to: CGPoint(x: 0, y: y))
                                path.addLine(to: CGPoint(x: size.width, y: y))
                            }
                        }
                    }
                    .stroke(isHome ? Color.white.opacity(0.35) : Color(uiColor: .separator), lineWidth: 1)
                }
            }
            .allowsHitTesting(false)
        }
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.floorAmenitiesToggle)
                .strokeBorder(Color(uiColor: .separator).opacity(0.6))
        )
        .shadow(color: .black.opacity(0.1), radius: 2.5, x: 1, y: 1)
    }

    /// 세로·가로 배치 모두 34pt 높이와 같은 글자 여백을 사용한다.
    private func floorButtons(map: IndoorMap, floor: IndoorMapFloor) -> some View {
        let buttonWidth: CGFloat
        let selectedBackground: Color
        let selectedText: Color
        let unselectedText: Color

        // 홈 지도에는 F 표기와 디자인 토큰을, 일반 지도에는 층 이름과 시스템 테마를 사용한다.
        switch appearance {
        case .home:
            buttonWidth = 61
            selectedBackground = DS.ColorToken.primaryLight
            selectedText = DS.ColorToken.neutralDark
            unselectedText = DS.ColorToken.neutralPrimary
        case .standard, .bookDetail:
            buttonWidth = 56
            selectedBackground = Color(uiColor: .label)
            selectedText = Color(uiColor: .systemBackground)
            unselectedText = .primary
        }

        return ForEach(map.floors.reversed()) { item in
            let isSelected = item.id == floor.id
            Button {
                store.send(.floorSelected(item.id))
            } label: {
                Text(appearance == .home ? "\(item.ordinal + 1)F" : item.name)
                    .typography(isSelected ? .caption1.weight(.semibold) : .caption1)
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.vertical, 10)
                    .padding(.horizontal, DS.Spacing._16)
                    .frame(width: buttonWidth, height: 34)
                    .background(isSelected ? selectedBackground : .clear)
                    .foregroundStyle(isSelected ? selectedText : unselectedText)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(item.name) 지도 보기")
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
            .accessibilityIdentifier("floor-\(item.ordinal)")
        }
    }
}
