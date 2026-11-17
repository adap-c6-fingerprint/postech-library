# PobookUI 디자인 토큰

2026-11-16 사용자가 [C6 Hi-fi Figma](https://www.figma.com/design/rqB4cSlpvGlTQ01AsdGK1p/-C6-%EC%8B%A4%EB%82%B4%EC%A7%80%EB%8F%84--Figma?m=dev)에서 내보낸 JSON을 기준으로 대조했다. 공용 정의는 `UI/PobookUI`에서 관리한다.

| Figma 내보내기 | Swift 정의 | 확인 결과 |
|---|---|---|
| Color _ Primitive Token | `PobookUI.ColorPrimitive` | 기존 색상과 일치 |
| Color _ Semantic & Component Token | `PobookUI.ColorToken` | 누락된 `RouteBar`, `BookSticker` 추가. 다른 내보내기 값은 기존 정의와 일치 |
| Radius | `PobookUI.Radius` | 기존 값과 일치 |
| Spacing | `PobookUI.Spacing` | 기존 값과 일치 |
| Typography _ Foundation | `FontFamily`, `FontStyle`, `FontSize`, `LineHeight`, `LetterSpacing` | 기존 기반 값과 일치. JSON의 소수점 표현 오차는 기존 값으로 정규화 |

앱에서 별도로 정의한 색상·타이포그래피는 내보내기에 없다는 이유로 삭제하지 않는다. 각 화면의 스타일 변경은 해당 Hi-fi 시안과 확인된 토큰을 기준으로 진행한다.

## 내비게이션 진행 바

| Figma 이름 | Swift 토큰 | 값 |
|---|---|---|
| routebar/background | `ColorToken.RouteBar.background` | `#777777` |
| routebar/walk-guide-text | `ColorToken.RouteBar.walkGuideText` | `#B6B6B6` |
| routebar/elevator-guide-text | `ColorToken.RouteBar.elevatorGuideText` | `#005207` |

진행 바의 배경과 구간 레이블에 위 토큰을 적용한다. 진행에 따라 레이블을 흰색·검정으로 바꾸지 않는다. 마커는 사용자 요청에 따라 24×24pt로 고정하고, 글자 확대에 맞춘 문구 측정과 폭 부족 시 가로 스크롤은 유지한다.

서체는 제공된 Foundation의 `Pretendard`를 사용한다. 내보내기에는 `Guidance` 조합이 없었으나 이후 사용자가 `Font.custom(Pretendard, size: 8).weight(.semibold)`를 제공했다. 이 속성을 `PobookUI.Typography.guidance`로 정의하고 진행 바의 구간 레이블·문구 폭 계산에 함께 적용한다. 기본 8pt SemiBold이며 추가 자간·행간 없이 폰트의 자연 행간을 사용한다. 다른 화면의 `caption2`는 기존 12pt 정의를 유지한다.

[`Font.custom(_:size:)`](https://developer.apple.com/documentation/swiftui/font/custom(_:size:))와 같이 본문 스타일을 기준으로 글자 확대에 대응한다. 기본 8pt는 Typography HIG의 iOS 권장 최소 11pt보다 작지만 사용자 제공 시안 값을 우선하며, 글자 확대와 진행 바의 VoiceOver 설명을 유지한다.

참고 HIG: [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Color](https://developer.apple.com/design/human-interface-guidelines/color). 마커 고정 크기는 사용자 지정 규격이며, 실제 시뮬레이터·기기에서 기본/확대 글자와 밝은/어두운 모드의 표시 확인이 필요하다.
