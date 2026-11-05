# Firebase 초기 연결 — PLI-267

## 이번 변경

- Firebase Apple SDK 13.1.1을 고정 버전으로 연결한다.
- 앱 target에 FirebaseCore, FirebaseAnalyticsCore(IDFA 수집 기능 제외), FirebaseCrashlytics만 추가한다.
- 기존 MyApp의 AppFeature Store와 AppView는 그대로 두고 UIApplicationDelegateAdaptor로 Firebase를 한 번 초기화한다.
- Analytics 수집, Crashlytics 자동 보고, 자동 화면 기록, IDFV 수집, 광고 개인화 신호를 Info.plist에서 기본 비활성화한다.
- SwiftUI의 앱 delegate 자동 대행(swizzling)은 비활성화한다. Messaging/Auth/APNs는 이번에 설치하지 않는다.
- 파일이 없거나 Bundle ID가 다르면 초기화를 건너뛰고 설정 오류만 로컬 로그에 남긴다. 도서·지도·길안내는 계속 사용할 수 있다.

## 로컬 설정 파일

제공된 Firebase 프로젝트는 `pobook-6bbc4`, 앱 Bundle ID는 `com.youngmin.fingerprint-library`다.
사용자가 개발·운영 공용 프로젝트 사용을 선택했다. 실제 수집을 활성화하기 전에 빌드 환경·테스트 트래픽 구분을 별도로 구현해야 한다.

1. Firebase 콘솔 → 프로젝트 설정 → 해당 iOS 앱의 `GoogleService-Info.plist`를 받는다.
2. 파일명을 정확히 `GoogleService-Info.plist`로 두고 `fingerprint-library/GoogleService-Info.plist`에 넣는다.
3. 앱의 폴더 동기화 방식으로 해당 plist가 앱 리소스에 포함된다. 앱 Info.plist와는 다른 파일이다.

설정 파일은 로컬에 배치하고 Git에서는 제외한다. Firebase 클라이언트 설정의 식별자는 서버 관리자 비밀키가 아니지만, 저장소의 키 관리 원칙에 따라 이 변경에 포함하지 않는다. 다른 checkout/CI에서도 별도로 파일을 제공해야 한다. 파일을 GitHub에 push했다고 기대하면 안 된다.

## 아직 하지 않은 것

- 동의 UI·동의 저장·수집 활성화, 사용자 ID·학과/선호도 속성, 70개 행동 이벤트, 위치 서버 전송.
- 개발/운영 Firebase 프로젝트 분리 또는 공용 프로젝트의 트래픽 분리.
- 실제 Analytics/Crashlytics 콘솔 수신 확인·테스트 크래시·dSYM 자동 업로드 빌드 단계.

`FirebaseCrashlyticsCollectionEnabled=false`는 자동 **보고/전송**을 끄는 설정이며 SDK가 기기에 크래시 정보를 남기지 않는다는 뜻이 아니다. 향후 진단 동의 활성화 전에 미동의 기간의 대기 보고서를 폐기하는 정책도 구현해야 한다. Analytics/Crashlytics의 런타임 수집 override는 실행 간 유지될 수 있으므로 향후 동의 처리에서 매 실행의 저장된 선택을 일관되게 적용해야 한다.

## 다음 검증 단계

1. 팀 기준 Xcode에서 패키지를 resolve하고 앱을 빌드한다. Package.resolved에는 기존 dev의 버전을 유지하고 Firebase 및 전이 의존성만 추가했다. 다른 Swift toolchain이 선택하는 대체 manifest에 따라 기존 의존성 잠금이 변경될 수 있으므로 무관한 갱신을 함께 커밋하지 않는다.
2. 실제 앱 번들에 정확한 이름의 GoogleService-Info.plist가 들어갔는지 확인한다.
3. 앱 실행 시 FirebaseApp 초기화와 기존 탭/도서/길안내 회귀를 확인한다.
4. 수집 동의를 구현한 다음 동의 전 전송 차단·철회·개발 트래픽 분리를 검증한다.
5. Crashlytics 도입 완료 전 공식 안내에 따라 dSYM 생성·마지막 빌드 단계의 업로드 스크립트·sandbox 입력 파일을 구성하고 테스트 크래시를 검증한다. 현재 단계에서 크래시 보고가 완전히 준비됐다고 판단하지 않는다.

## 정적 검증

```sh
python3 -m unittest discover -s Scripts/tests -p 'test_firebase_setup.py' -v
plutil -lint fingerprint-library/Info.plist fingerprint-library.xcodeproj/project.pbxproj
```

이 검사는 설정 연결을 확인하는 검사다. iOS 컴파일·실기기 수신 확인을 대신하지 않는다.

## 이번 실행의 검증 결과

- plist/project 문법 검사, MyApp.swift 구문 검사 통과.
- Scripts/tests의 기존 검사 포함29개 통과.
- Xcode26.6에서 Firebase13.1.1을 포함한 패키지 해결 완료. FirebaseAnalyticsCore만 연결하더라도 SDK manifest가 다른 제품용 패키지를 다운로드/잠금에 포함할 수 있다. 다운로드 목록과 앱의 실제 링크 대상은 다르다.
- 시뮬레이터 빌드는 기존 ComposableArchitectureMacros·CasePathsMacros·DependenciesMacrosPlugin·PerceptionMacros·SwiftNavigationMacros의 실행 승인 요구로 의존성 그래프 단계에서 중단됐다. 매크로 검증을 우회하거나 기존 패키지 버전을 변경하지 않았다. 앱 컴파일·링크 통과로 판단하지 않는다.
- 현재 파일의 식별자 확인만으로 Firebase 콘솔의 Analytics 연결·이벤트 수신 완료를 보장하지 않는다. 콘솔의 프로젝트 설정 → 통합 → Google Analytics도 다음 수집 검증 시 확인한다.

## 공식 참고

- [Apple 프로젝트 연결](https://firebase.google.com/docs/ios/setup)
- [수집 제어와 IDFA 없는 Analytics 제품](https://firebase.google.com/docs/analytics/ios/configure-data-collection)
- [Crashlytics 동의·보고 제어](https://firebase.google.com/docs/crashlytics/ios/customize-crash-reports)
- [Crashlytics와 dSYM 설정](https://firebase.google.com/docs/crashlytics/ios/get-started)
