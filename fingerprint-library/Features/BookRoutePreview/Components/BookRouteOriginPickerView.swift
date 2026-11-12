import SwiftUI

struct BookRouteOriginPickerView: View {
    let map: IndoorMap
    let title: String
    let subtitle: String?
    var initialFloorID: UUID?
    let onCancel: () -> Void
    let onConfirm: (IndoorPosition) -> Void

    @State private var selectedFloorID: UUID?
    @State private var center: IndoorMapCoordinate?
    @State private var isMapSettled = false
    @State private var hasSettledOnce = false
    @State private var cameraRequest: IndoorMapCameraRequest?

    private var selectedFloor: IndoorMapFloor? {
        map.floors.first { $0.id == selectedFloorID } ?? map.floors.first
    }

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
                    guard isSettled else {
                        if isMapSettled { isMapSettled = false }
                        return
                    }
                    center = coordinate
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
                        .foregroundStyle(PobookUI.ColorToken.neutralTertiary)
                        .accessibilityIdentifier("route-origin-picker-shelf")
                }
            }
            Spacer(minLength: 0)
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
        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

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
                Image("MapUserLocation")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 15, height: 15)
                    .shadow(color: PobookUI.ColorToken.primaryLight.opacity(0.3), radius: 1.65517)
                    .transition(.opacity)
            }
            Image("MapLocationStart")
                .resizable()
                .scaledToFit()
                .frame(width: 33, height: 45)
                .offset(y: -45 / 2)
        }
        .animation(.easeInOut(duration: 0.15), value: isMapSettled)
    }

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

    private var guidanceMessage: some View {
        Text("층을 선택한 후,\n지도를 움직여 출발 위치를 직접 설정해주세요")
            .typography(.caption1)
            .multilineTextAlignment(.center)
            .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
            .padding(.vertical, 10)
            .padding(.horizontal, 16)
            .frame(width: 307, height: 65)
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
        .padding(.vertical, 16)
        .padding(.horizontal, 20)
        .frame(width: 330, height: 52)
        .foregroundStyle(PobookUI.ColorToken.neutralPrimary)
        .accessibilityHint("선택한 위치를 출발지로 삼아 길안내를 시작해요")
        .accessibilityIdentifier("route-origin-picker-confirm")
    }

    private func confirmedPosition() -> IndoorPosition? {
        guard let center, let floor = selectedFloor, isCenterOnFloor else { return nil }
        return IndoorPosition(
            coordinate: center, floorOrdinal: floor.ordinal, horizontalAccuracy: nil,
            timestamp: Date(), source: .manual)
    }
}

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
            .stroke(PobookUI.ColorToken.primaryLight, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
    }
}
