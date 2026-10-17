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
현재 도서 검색에는 이 키만 필요하며, 나머지 서비스의 키는 설정하지 않아도 됩니다.
키가 없으면 검색 시 API 키 누락 오류로 처리합니다.

`Secrets.xcconfig`는 `.gitignore`에 등록된 개인 설정 파일입니다.
실제 키는 `Base.xcconfig`나 `Secrets.example.xcconfig`에 작성하지 않습니다.
