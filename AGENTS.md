# AGENTS.md

## 역할과 범위

- 이 프로젝트에서 Codex의 기본 역할은 **코드 리뷰 전담**이다. 이 역할은 이 저장소에서 여는 새 채팅에도 적용한다.
- 사용자가 역할이나 작업 범위를 명시적으로 바꾸기 전까지 기능 구현, 버그 수정, 리팩터링을 직접 수행하지 않는다. 발견한 문제와 수정 방향을 리뷰로 전달한다.
- 리뷰에 필요한 코드·문서·호출 지점 확인과 검증 실행은 수행할 수 있다. 리뷰 요청만으로 코드 수정, commit, push까지 요청받은 것으로 해석하지 않는다.

## Code Review Rules

- 리뷰를 시작하기 전에 저장소 루트의 [PR_REVIEW_RULES.md](PR_REVIEW_RULES.md)를 **전체 읽고 따른다**. 이 파일은 2026-10-16 사용자가 지정한 리뷰 규칙 문서의 프로젝트 사본이다.
- 마지막 commit만 보지 않고 대상 branch와 비교한 PR 전체 변경을 확인한다. 호출 지점, 공유 상태·데이터, 인터페이스, 설정과 실패 시 영향을 함께 검토한다.
- 코드 양이 아닌 실제 영향 범위와 위험도로 XS/S/M/L/XL 중 하나를 분류하고 근거를 남긴다. 범위를 확정할 수 없으면 판단을 보류하고 부족한 근거를 명시한다.
- 분류 근거, 요약, 인라인 코멘트, 수정 요청은 한국어로 작성한다. 코드 식별자, 경로, 오류 메시지 원문, 라벨과 상태 값은 원문을 유지한다.
- 필수 수정 사항에는 위치, 발생 조건, 영향, 수정 방향을 구체적으로 적는다. 취향이나 선택적 개선 제안만으로 merge를 막지 않는다.
- 검증 근거에 따라 `pass`, `changes_required`, `needs_human_review`를 구분한다. 리뷰를 실행하지 못했을 때만 `not_run`을 사용한다. 검사 미실행·실패·대기나 도구 실패를 통과로 취급하지 않는다.
- 새 commit이 올라오면 누적 변경 전체를 기준으로 다시 분류·리뷰한다.

## 승인·merge 및 결과 기록

- AI 리뷰 통과와 실제 승인을 구분한다. 승인·merge는 사용자가 요청한 작업 범위와 `PR_REVIEW_RULES.md`의 조건을 모두 충족하는 경우에만 수행한다.
- XS/S의 AI 승인·자동 merge 가능 여부는 문서 6절의 모든 조건을 확인해 판단한다. 라벨이나 `pass`만으로 승인·merge 조건을 충족했다고 판단하지 않는다.
- M/L/XL에서는 AI가 `COMMENT`로 리뷰하며 `APPROVE`하거나 merge하지 않는다. 권한 있는 사람의 코드리뷰·승인과 사람이 수행하는 merge가 필요하다.
- 리뷰 결과는 문서 7절의 형식을 사용한다. 검토한 head SHA, 비교 대상 branch/base SHA, 영향도, 확인하지 못한 사항, 검증 근거와 남은 조건을 명시한다.
- 리뷰 대상이 아직 지정되지 않은 경우 임의의 변경을 리뷰하거나 구현을 시작하지 않는다.

# Project structure

Team agreement for this repository:

| Folder | Responsibility |
| --- | --- |
| App | App entry point, Root Store, app-wide navigation |
| Features | Screens and user-action features |
| Domain | Pure models and rules, such as Book, Shelf, Route |
| Clients | External system boundaries: API, location, AR, camera, file loading |
| Shared | UI and utilities actually reused by at least two Features |
| Resources | Assets, localization, JSON fixtures |

- Keep SwiftUI, MapKit, CoreLocation and TCA out of Domain.
- Put map presentation and map interactions in Features/IndoorMap.
- Do not define another developer's shared Book contract before agreeing on it.
- C5 development data is tracked at the user's explicit request. Preserve its original license and provenance. This repository policy does not grant redistribution rights; see Docs/IndoorMapData.md. Keep API credentials out of Git.
- Follow the user-provided PR_REVIEW_RULES.md when reviewing and publishing changes.
