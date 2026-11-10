import SwiftUI

/// 위치 권한이 없거나 실제 위치가 목적지와 맞지 않을 때, 사용자가 출발 위치를 직접 지정하는 화면.
///
/// 지도를 움직여 화면 중앙의 십자 표식에 출발 위치를 맞추고, 멈추면 확정 버튼이 나타난다.
/// 층은 오른쪽 아래 층 선택 버튼으로 고르며 선택한 층이 사용자의 현재 층이 된다.
struct BookRouteOriginPickerView: View {
    let map: IndoorMap
    /// 안내할 책 제목. 어떤 책을 찾아가는 중인지 화면 위에 유지한다.
    let title: String
    /// "4층 337번 서가"처럼 목적지 서가를 설명하는 줄.
    let subtitle: String?
    var initialFloorID: UUID?
    let onCancel: () -> Void
    let onConfirm: (IndoorPosition) -> Void

    @State private var selectedFloorID: UUID?
    @State private var center: IndoorMapCoordinate?
    /// 지도가 멈춘 뒤에만 출발 위치를 확정할 수 있다. 움직이는 동안에는 안내 문구를 보여 준다.
    @State private var isMapSettled = false
    /// 최초 도면 맞춤이 끝났는지. 시안대로 사용자가 지도를 움직인 뒤에 확정 버튼을 보여 주기 위해 구분한다.
    @State private var hasSettledOnce = false
    @State private var cameraRequest: IndoorMapCameraRequest?

    private var selectedFloor: IndoorMapFloor? {
        map.floors.first { $0.id == selectedFloorID } ?? map.floors.first
    }

    /// 선택한 층의 도면 밖은 출발 위치로 받지 않는다. 경로 그래프가 없는 좌표로 안내를 시작하지 않기 위함이다.
    private var isCenterOnFloor: Bool {
        guard let center, let floor = selectedFloor, center.isValid else { return false }
        return floor.geometry.contains(center)
    }

    private var canConfirm: Bool { isMapSettled && isCenterOnFloor }

    var body: some View {
        ZStack(alignment: .top) {
            mapLayer
            topBarBackground
            header
            originMarker
            floorPicker
            bottomControls
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .onAppear {
            if selectedFloorID == nil {
                selectedFloorID = initialFloorID ?? map.floors.first?.id
            }
            if let id = selectedFloorID, cameraRequest == nil {
                cameraRequest = IndoorMapCameraRequest(id: 1, target: .initialFloor(id))
            }
        }
        .accessibilityIdentifier("route-origin-picker")
    }

    @ViewBuilder
    private var mapLayer: some View {
        if let floor = selectedFloor {
            IndoorMapKitView(
                map: map, floor: floor, selectedFeatureID: nil, position: nil,
                showsUserLocation: false, isPlacingOrigin: false, cameraRequest: cameraRequest,
                onSelect: { _ in }, onPlaceOrigin: { _ in },
                onCenterChanged: { coordinate, isSettled in
                    // 이동 중에는 블루닷과 확정 버튼을 숨겨 아직 좌표가 정해지지 않았음을 알린다.
                    guard isSettled else {
                        if isMapSettled { isMapSettled = false }
                        return
                    }
                    center = coordinate
                    // 처음 도면을 맞추는 카메라 이동은 사용자의 조작이 아니므로 확정 버튼을 띄우지 않는다.
                    if hasSettledOnce {
                        isMapSettled = true
                    } else {
                        hasSettledOnce = true
                    }
                },
                appearance: .home
            )
            .ignoresSafeArea()
            .accessibilityIdentifier("route-origin-picker-map")
        } else {
            ContentUnavailableView("지도를 불러오지 못했어요", systemImage: "map")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var topBarBackground: some View {
        VStack(spacing: 0) {
            LibraryTopBarBackground()
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea(.container, edges: [.top, .horizontal])
        .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .typography(.title1)
                    .lineLimit(2)
                    .accessibilityIdentifier("route-origin-picker-title")
                if let subtitle {
                    Text(subtitle)
                        .typography(.title1)
                        .foregroundStyle(DS.ColorToken.neutralTertiary)
                        .accessibilityIdentifier("route-origin-picker-shelf")
                }
            }
            Spacer(minLength: 0)
            // 시안에는 없지만, 직접 설정을 그만두고 이전 화면으로 돌아갈 수단이 필요하다.
            Button(action: onCancel) {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .glassEffect(.regular.interactive(), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("출발 위치 직접 설정 그만두기")
            .accessibilityIdentifier("route-origin-picker-cancel")
        }
        .foregroundStyle(DS.ColorToken.neutralPrimary)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    /// 화면 정중앙에 고정한 출발 표식. 지도가 아래에서 움직이고 표식은 제자리를 지킨다.
    ///
    /// 지도도 안전 영역을 무시하고 화면 전체를 채우므로, 표식의 화면 정중앙이 곧 지도의 중심 좌표다.
    private var originMarker: some View {
        markerContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }

    private var markerContent: some View {
        ZStack {
            BookRouteOriginCrosshair()
                .frame(width: 26, height: 26)
            if isMapSettled {
                // 확정 전 위치도 블루닷과 같은 표시를 써서 "여기가 내 위치"임을 읽히게 한다.
                Image("MapUserLocation")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .shadow(color: DS.ColorToken.primaryLight.opacity(0.3), radius: 1.65517)
                    .transition(.opacity)
            }
            Image("MapLocationStart")
                .resizable()
                .scaledToFit()
                .frame(width: 33, height: 45)
                // 핀의 뾰족한 끝이 십자 표식의 중심에 닿게 위로 올린다.
                .offset(y: -45 / 2)
        }
        .animation(.easeInOut(duration: 0.15), value: isMapSettled)
    }

    /// 시안 치수: 오른쪽에서 17, 안전 영역 아래쪽에서 121 떨어뜨린다.
    @ViewBuilder
    private var floorPicker: some View {
        if let floor = selectedFloor {
            IndoorMapFloorPicker(
                floors: map.floors, selectedFloorID: floor.id, appearance: .home,
                marksSelectionAsCurrent: true,
                onSelect: { id in
                    guard id != selectedFloorID else { return }
                    selectedFloorID = id
                })
                .padding(.trailing, 17)
                .padding(.bottom, 121)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        }
    }

    /// 안내 문구와 확정 버튼을 안전 영역 아래쪽에 붙인다.
    private var bottomControls: some View {
        Group {
            if canConfirm {
                confirmButton
            } else {
                guidanceMessage
            }
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    }

    /// 확정 전에는 상황과 관계없이 같은 문구를 유지한다.
    private var guidanceMessage: some View {
        Text("층을 선택한 후,\n지도를 움직여 출발 위치를 직접 설정해주세요")
            .typography(.caption1)
            .multilineTextAlignment(.center)
            .foregroundStyle(DS.ColorToken.neutralPrimary)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(width: 307, height: )
            .glassEffect(.regular, in: .rect(cornerRadius: 12))
            .accessibilityIdentifier("route-origin-picker-hint")
    }

    private var confirmButton: some View {
        Button {
            guard let position = confirmedPosition() else { return }
            onConfirm(position)
        } label: {
            Text("위치 확정하고 안내 받기")
                .typography(.button)
                .multilineTextAlignment(.center)
                .frame(width: 290, height: 20)
                .padding(.vertical, 16)
                .padding(.horizontal, 20)
        }
        .buttonStyle(.glass(.regular.tint(Color(white: 0.08).opacity(0.6))))
        .buttonBorderShape(.capsule)
        .foregroundStyle(DS.ColorToken.neutralPrimary)
        .accessibilityHint("선택한 위치를 출발지로 삼아 길안내를 시작해요")
        .accessibilityIdentifier("route-origin-picker-confirm")
    }

    private func confirmedPosition() -> IndoorPosition? {
        guard let center, let floor = selectedFloor, isCenterOnFloor else { return nil }
        // 직접 지정한 좌표는 정확도 값이 없다. RouteStartResolver가 manual 출처를 별도로 처리한다.
        return IndoorPosition(
            coordinate: center, floorOrdinal: floor.ordinal, horizontalAccuracy: nil,
            timestamp: Date(), source: .manual)
    }
}

/// 출발 핀 아래에 그리는 십자 표식. 가운데를 비워 확정된 위치의 블루닷이 그 안에 놓인다.
struct BookRouteOriginCrosshair: View {
    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
            let inner = min(geometry.size.width, geometry.size.height) / 2 * 0.42
            let outer = min(geometry.size.width, geometry.size.height) / 2
            Path { path in
                for degrees in stride(from: 45.0, to: 360.0, by: 90.0) {
                    let radians = degrees * .pi / 180
                    let direction = CGPoint(x: cos(radians), y: sin(radians))
                    path.move(to: CGPoint(x: center.x + direction.x * inner, y: center.y + direction.y * inner))
                    path.addLine(to: CGPoint(x: center.x + direction.x * outer, y: center.y + direction.y * outer))
                }
            }
            .stroke(DS.ColorToken.primaryLight, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}
