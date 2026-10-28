import SwiftUI

/// PLI-96 / #116 디자인 단계. 지도 그림은 예시이며 실제 경로 값은 아직 없다.
struct BookRoutePreviewView: View {
    let books: [Book]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let accent = Color(red: 0.88, green: 0.95, blue: 0.19)

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                BookRouteMapPlaceholder(accent: accent, topInset: geometry.safeAreaInsets.top)
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header
                    ScrollView {
                        if books.isEmpty {
                            ContentUnavailableView(
                                "찾을 책이 없어요",
                                systemImage: "books.vertical",
                                description: Text("책 상세 또는 책바구니에서 책을 선택해 주세요.")
                            )
                        } else {
                            VStack(alignment: .leading, spacing: 24) {
                                routeMetrics
                                routeSummary
                                bookInformation
                            }
                            .padding(.horizontal, 16)
                            .padding(.bottom, 20)
                        }
                    }
                    .scrollIndicators(.hidden)
                }
                .frame(height: geometry.size.height * 0.57)
                .frame(maxWidth: .infinity)
                .background {
                    UnevenRoundedRectangle(topLeadingRadius: 28, topTrailingRadius: 28)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .ignoresSafeArea(.container, edges: .bottom)
                }
            }
        }
        .background(Color(uiColor: .systemBackground))
        .preferredColorScheme(.dark)
        .toolbar(.hidden, for: .navigationBar, .tabBar)
        .accessibilityIdentifier("book-route-preview")
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .tint(.white)
            .accessibilityLabel("뒤로가기")

            Spacer()
            Text("경로 미리보기").font(.headline)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
        .padding(16)
    }

    private var routeMetrics: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
            : AnyLayout(HStackLayout(spacing: 12))

        return VStack(alignment: .leading, spacing: 8) {
            layout {
                HStack(spacing: 12) {
                    metric("도보", unit: "min")
                    metric("단계", unit: "steps")
                    metric("거리", unit: "m")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button("출발") { }
                    .font(.headline)
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    .controlSize(.large)
                    .fixedSize()
                    .disabled(true)
                    .accessibilityHint("경로 계산 후 사용할 수 있어요")
            }
            .padding(16)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))

            Text("경로 계산 후 시간·단계·거리가 표시돼요.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func metric(_ title: String, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("—").font(.title2.bold())
                Text(unit).font(.caption)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), 계산 전")
    }

    private var routeSummary: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("경로 요약").font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                Label("내 위치", systemImage: "location.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
                Divider().padding(.leading, 28)
                Label(books.count == 1 ? "첫 번째 책" : "선택한 책 \(books.count)권", systemImage: "book.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .orange)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
        }
    }

    private var bookInformation: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("도서 및 청구기호").font(.headline)
            ForEach(books) { book in
                HStack(alignment: .top, spacing: 16) {
                    BookCoverView(url: book.imageURL)
                        .frame(width: 72, height: 104)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    VStack(alignment: .leading, spacing: 6) {
                        Text("소장 위치 · 청구기호 확인 전")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(BookText.plainText(book.title))
                            .font(.subheadline.bold())
                            .fixedSize(horizontal: false, vertical: true)
                        Text(BookText.plainText(book.author))
                            .font(.caption).foregroundStyle(.secondary)
                        Text("대출 정보 확인 전")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(16)
                .background(Color(uiColor: .tertiarySystemBackground), in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }
}

/// 실제 IMDF·현재 위치·목적지로 오해하지 않도록 표시하는 디자인용 도면.
private struct BookRouteMapPlaceholder: View {
    let accent: Color
    let topInset: CGFloat

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topTrailing) {
                Canvas { context, size in
                    context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.15, green: 0.11, blue: 0.12)))
                    for column in 0..<4 {
                        for row in 0..<13 {
                            let shelf = CGRect(x: CGFloat(column) * size.width * 0.27 - 22,
                                               y: CGFloat(row) * 34 + CGFloat(column % 2) * 12,
                                               width: size.width * 0.18, height: 11)
                            context.fill(Path(roundedRect: shelf, cornerRadius: 2), with: .color(.white.opacity(0.10)))
                        }
                    }
                    var corridor = Path()
                    corridor.move(to: CGPoint(x: size.width * 0.60, y: 0))
                    corridor.addCurve(to: CGPoint(x: size.width * 0.64, y: size.height * 0.59),
                                      control1: CGPoint(x: size.width * 0.14, y: size.height * 0.18),
                                      control2: CGPoint(x: size.width * 0.24, y: size.height * 0.40))
                    context.stroke(corridor, with: .color(.gray.opacity(0.25)), lineWidth: 52)

                    var route = Path()
                    route.move(to: CGPoint(x: size.width * 0.48, y: size.height * 0.40))
                    route.addCurve(to: CGPoint(x: size.width * 0.55, y: size.height * 0.10),
                                   control1: CGPoint(x: size.width * 0.23, y: size.height * 0.31),
                                   control2: CGPoint(x: size.width * 0.34, y: size.height * 0.20))
                    context.stroke(route, with: .color(accent), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [3, 9]))
                }
                .accessibilityHidden(true)

                Image(systemName: "book.fill")
                    .foregroundStyle(.black)
                    .padding(12)
                    .background(accent, in: Circle())
                    .position(x: geometry.size.width * 0.55, y: geometry.size.height * 0.10)
                    .accessibilityHidden(true)
                Image(systemName: "location.north.fill")
                    .font(.title2)
                    .foregroundStyle(accent)
                    .padding(12)
                    .background(.black, in: Circle())
                    .overlay(Circle().stroke(accent, lineWidth: 3))
                    .position(x: geometry.size.width * 0.48, y: geometry.size.height * 0.40)
                    .accessibilityHidden(true)

                Text("지도 예시")
                    .font(.caption)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.ultraThinMaterial, in: Capsule())
                    .padding(16)
                    .padding(.top, topInset)
            }
        }
    }
}

#Preview("한 권 · 다크 모드") {
    NavigationStack {
        BookRoutePreviewView(books: [Book(
            id: "primo:preview", isbn: nil, controlNumber: "primo:preview",
            title: "양자역학의 기초", author: "박하린", publisher: nil,
            publicationYear: nil, description: nil, imageURL: nil
        )])
    }
}
