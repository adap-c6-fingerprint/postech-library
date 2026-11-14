import SwiftUI

struct RouteStartNoticeView: View {
    let notice: String
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            DisclosureGroup("출발 위치 안내") {
                noticeText
            }
        } else {
            noticeText
        }
    }

    private var noticeText: some View {
        Text(notice)
            .fixedSize(horizontal: false, vertical: true)
    }
}
