# postech-library
포스텍 도서관 메인 어플리케이션

## 로컬 API 키 설정

프로젝트 루트의 `Base.xcconfig`를 Debug와 Release에서 공통으로 사용합니다.
이 파일은 Git으로 공유하며, 같은 폴더에 `Secrets.xcconfig`가 있으면 로컬 설정을 추가로 읽습니다.
`Secrets.xcconfig`가 없어도 앱을 빌드할 수 있습니다.

실제 도서 검색을 사용하려면 프로젝트 루트에서 예시 파일을 복사합니다.

```sh
cp Secrets.example.xcconfig Secrets.xcconfig
```

생성한 `Secrets.xcconfig`의 `NATIONAL_LIBRARY_API_KEY`에 국립중앙도서관 API 키를 입력합니다.
도서 상세 화면의 책 소개를 사용하려면 `YES24_API_KEY`도 입력합니다.
키가 없으면 검색 시 API 키 누락 오류로 처리합니다.

`Secrets.xcconfig`는 `.gitignore`에 등록된 개인 설정 파일입니다.
실제 키는 `Base.xcconfig`나 `Secrets.example.xcconfig`에 작성하지 않습니다.

## 도서 상세와 책 소개

홈 → 도서 검색 → 검색 결과의 표지나 책 정보를 누르면 기본 상세 화면이 열립니다.
선택한 책의 ISBN으로 Yes24 상품 상세 API를 조회하고 책 소개와 원문 링크를 표시합니다.
ISBN13을 우선하며 ISBN10은 ISBN13으로 변환합니다. ISBN이 없거나 유효하지 않으면 요청하지 않습니다.
소개 없음과 조회 실패를 구분하며, 실패한 요청은 상세 화면에서 다시 시도할 수 있습니다.
검색 결과로 돌아오면 진행 중인 상세 조회를 취소하고 검색 결과와 책바구니를 보존합니다.

API 형식과 출처 표시는 [Yes24 상품 상세 API](https://developers.yes24.com/api-doc/goods-item-detail)와
[이용약관](https://developers.yes24.com/support/terms)을 기준으로 합니다.
