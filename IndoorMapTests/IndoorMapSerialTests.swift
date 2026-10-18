import Testing

/// TestStore의 전역 main executor 설정과 실제 스레드 검사가 겹치지 않게 한다.
/// TestStore를 사용하는 새 suite도 이 상위 suite 안에 선언한다.
@Suite(.serialized)
struct IndoorMapSerialTests {}
