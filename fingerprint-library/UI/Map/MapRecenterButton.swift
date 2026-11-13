import SwiftUI

struct MapRecenterButton: View {
    var accessibilityIdentifier = "recenter-location"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "scope").font(.title3)
                .frame(width: 48, height: 48).glassEffect(.regular, in: .circle)
        }
        .accessibilityLabel("현재 위치로 지도 이동")
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
