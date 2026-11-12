import SwiftUI

/// 도착 정보 뒤의 흐린 서가. 화면 크기에 맞춰 그려 외부 이미지 로딩에 의존하지 않는다.
struct BookNavigationArrivalBackground: View {
    var body: some View {
        ZStack {
            Color(white: 0.08)
            Canvas { context, size in
                context.addFilter(.blur(radius: 18))
                var x: CGFloat = -30
                for index in 0..<14 {
                    let width = size.width * spineWidths[index % spineWidths.count]
                    let height = size.height * spineHeights[index % spineHeights.count]
                    let spine = CGRect(x: x, y: size.height * 0.94 - height, width: width, height: height)
                    context.fill(Path(spine), with: .color(spineColors[index % spineColors.count]))
                    x += width + 9
                }
            }
            LinearGradient(stops: [
                .init(color: .black, location: 0),
                .init(color: .black.opacity(0.35), location: 0.25),
                .init(color: .black.opacity(0.25), location: 0.7),
                .init(color: Color(red: 0.24, green: 0.18, blue: 0.15), location: 1)
            ], startPoint: .top, endPoint: .bottom)
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private let spineColors: [Color] = [
        Color(red: 0.16, green: 0.26, blue: 0.29), Color(white: 0.55),
        Color(red: 0.35, green: 0.30, blue: 0.25), Color(white: 0.18),
        Color(red: 0.15, green: 0.35, blue: 0.30), Color(white: 0.55),
        Color(red: 0.44, green: 0.39, blue: 0.29)
    ]
    private let spineWidths: [CGFloat] = [0.08, 0.1, 0.045, 0.07, 0.09]
    private let spineHeights: [CGFloat] = [0.74, 0.9, 0.82, 0.65, 0.86]
}
