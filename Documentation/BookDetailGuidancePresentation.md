# 도서 상세에서 길안내 화면으로 전환

## 확인한 문제

도서 상세의 안내 시작 버튼이 상세 시트를 숨기는 상태와 App의 전체 화면 모달 상태를 연속으로 변경했다. UIKit 시트의 닫힘 완료를 기다리지 않아 전체 화면 안내 표시가 거부되면, 상세 시트만 사라지고 지도·뒤로가기·찜 버튼이 남았다.

2026-11-16 05:08:29 iPhone 18 Pro 시뮬레이터 로그에서 다음 메시지를 확인했다. 이는 같은 날 05:09:17에 사용자가 제공한 빈 지도 화면과 일치하는 전환 충돌이다.

```text
Warning: Attempt to dismiss ... while a presentation or dismiss is in progress!
Attempt to present ... which is already presenting ...BookDetailSheet...
```

권한이 허용돼도 도서관 외곽에서 20m 넘게 떨어져 있으면 출발 위치 선택이 필요하다. 이 정책에 도달하기 전에 안내 부모 화면의 표시가 실패한 문제이며, 위치·층·경로 계산 정책은 수정하지 않는다.

## 시작 순서

- 상세에서 시작: 요청 저장 → 상세 시트 닫기 → UIKit 닫힘 완료 → `guidanceSheetDismissed(requestID:)` → App에 안내 시작 위임.
- 상세 안의 장바구니에서 시작: 요청 저장 → 장바구니 닫힘 `onDismiss` → 상세 시트 닫기 → UIKit 닫힘 완료 → 안내 시작 위임.
- 상세 시트가 열리는 중이면 열림 완료 뒤 닫기를 실행한다. 시트 표시 전 요청이 온 경우에는 시트를 새로 열지 않고 안내로 넘긴다.
- 요청 ID를 대조해 중복 탭·취소된 요청·이전 요청의 늦은 완료 이벤트가 새 모달을 열지 않게 한다.

안내를 여는 App의 `Modal` 소유권과 화면 구성은 유지한다. 안내 시작 시점은 고정 대기 시간이 아닌 UIKit 완료 콜백으로 결정한다.

## 검증

2026-11-16 iOS 27.2 iPhone 17 시뮬레이터에서 선택한 25개 테스트, 매개변수 포함 28회 실행 통과.

- `AppNavigationTests`: 상세 닫힘 전에는 모달이 없고, 닫힘 완료 뒤 올바른 상세의 안내가 열린다. 안내 종료 시 해당 상세에 복귀를 알린다.
- `BookDetailGuidancePresentationTests`: 중복 요청, 취소·이전 요청의 늦은 콜백, 장바구니와 상세의 닫힘 순서, 빈 요청을 검증한다.
- `BookDetailSheetHandoffTests`: 실제 UIKit 시트가 열린 상태와 열리는 도중의 안내 요청을 검증한다. 시트가 제거된 뒤 다음 모달을 열고, 종료 뒤 상세 시트가 다시 표시되는지 확인한다.
- `RouteStartFlowTests`: 20m 외부에서 출발점 선택, 위치 권한 없음, 수동 출발점 유지와 안내 시작 흐름을 검증한다.

UIKit 전환 테스트의 다음 화면은 테스트용 모달이다. 실제 출발 위치 선택 화면까지의 전체 사용자 흐름과 실기기의 위치·권한 조합은 추가 QA 대상이다. Hi-fi 바텀시트 변경은 별도 브랜치에 보관한다.

## 참고

- [UIKit dismiss(animated:completion:)](https://developer.apple.com/documentation/uikit/uiviewcontroller/dismiss(animated:completion:)): 모달을 닫은 뒤 완료 콜백을 호출한다.
- [HIG Sheets](https://developer.apple.com/design/human-interface-guidelines/sheets): 기존 시트를 닫은 뒤 다음 시트를 표시하고, 종료 후 이전 맥락으로 돌아갈 수 있도록 한다.
