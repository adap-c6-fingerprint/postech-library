import SwiftUI

/// 지도를 사용자 위치로 되돌리는 원형 버튼. 홈 지도와 도서 길안내가 같은 모양을 쓴다.
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
