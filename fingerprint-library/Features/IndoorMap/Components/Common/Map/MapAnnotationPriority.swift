import MapKit

/// 선택 상태에서도 사용자 위치 > 경로 배지 > 시설·찜 > 서가 번호 순서를 유지한다.
enum MapAnnotationPriority {
    static let shelf = MKAnnotationViewZPriority.min
    static let marker = MKAnnotationViewZPriority.defaultUnselected
    static let route = MKAnnotationViewZPriority(rawValue: 750)
    static let user = MKAnnotationViewZPriority.max
}
