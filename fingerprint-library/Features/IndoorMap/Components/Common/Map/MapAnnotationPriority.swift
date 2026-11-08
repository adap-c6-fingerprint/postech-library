import MapKit

/// 선택 상태에서도 사용자 위치 > 경로 배지 > 서가 번호 > 시설·찜 순서를 유지한다.
enum MapAnnotationPriority {
    static let marker = MKAnnotationViewZPriority.defaultUnselected
    static let shelf = MKAnnotationViewZPriority(rawValue: 600)
    static let route = MKAnnotationViewZPriority(rawValue: 750)
    static let user = MKAnnotationViewZPriority.max
}
