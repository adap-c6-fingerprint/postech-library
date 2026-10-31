# Primo holdings simulation

Created 2026-10-28 from the read-only POSTECH response and the scoped contract in
`postman/contracts/primo-holdings.openapi.json`. The local mock list was empty;
no owning-team workspace was available, so its published mock was not reused.

## Purpose

Run the production Swift HTTP service against the `library` member, including
the actual bibliographic sample, mismatched record, empty result and upstream
errors. Error cases use synthetic MMS IDs; the handler documents them.

## Execution

From the repository root, start in one terminal:

```sh
postman simulation run postman/simulations/primo-holdings/primo-holdings.sim.yaml --port 47575 --output ndjson --no-history > /tmp/primo-sim.ndjson
```

Once the `listening` event reports port 47575, compile and run in another:

```sh
swiftc -swift-version 6 -parse-as-library fingerprint-library/Clients/Network/HTTPClient.swift fingerprint-library/Clients/Network/BookAPIClient.swift fingerprint-library/Shared/AppConfiguration.swift fingerprint-library/Clients/Book/Client/PrimoAPIClient.swift fingerprint-library/Domain/Book/BookHolding.swift fingerprint-library/Domain/Book/BookCardLibraryInfo.swift fingerprint-library/Clients/Book/Client/PrimoHoldingsMapper.swift fingerprint-library/Clients/Book/Client/PrimoBookHoldingsService.swift Scripts/verify-primo-holdings.swift -o /tmp/primo-holdings-proof
/tmp/primo-holdings-proof http://127.0.0.1:47575/library
```

The proof checks request counts through the mock's diagnostic endpoint.
Restart the simulation before a second run to reset counts. Stop it with Ctrl-C.
No credentials, workspace binding or public deployment are needed.

## Assumptions

- The handler contains a reduced public bibliographic response captured on
  2026-10-28. It proves compatibility with that response shape, not all holdings
  in the catalog or live availability. (observed 2026-10-28)
- Synthetic failure IDs model the HTTP statuses and invalid-body behavior the
  client handles. These are local scenarios, not observed live failures.
  (reasoned 2026-10-28, `default.js`)
- This validates the service's real URLSession transport, parser and retries.
  It does not validate a deployed proxy, device network policy or shelf placement.
  (observed 2026-10-28)

## Observations

<!-- begin:observations -->
2026-10-30: 공통 `HTTPClient`와 `PrimoAPIClient`를 사용하는 실제 소장 서비스를 Swift 6으로 컴파일해 기존 시뮬레이션에서 실행했다. 기존 응답 변환·401·잘못된 JSON·503 최대 3회·429 두 번째 요청 회복이 통과했고, 요청 이벤트 12건을 확인했다. 실제 프록시나 실서버를 호출한 결과는 아니다. 구조화된 검증 기록은 `primo-holdings.context.yaml`에 추가했다.
2026-10-28 (#88): `library` served the production Swift 6 HTTP service and
recommendation-card conversion. Location, call number, availability from the
same holding and additional locations passed alongside the existing fault
cases. No other members exist. This does not exercise the app's key/proxy
configuration or live provider availability.
2026-10-28: `library` served the production client's new mixed-document fault
case as well as the existing cases. Missing/null pnx, control and recordid
before a valid target no longer hide its holdings. This defensive payload was
synthetic; it was not observed from the provider. Swift 6 HTTP execution passed.
2026-10-28: `library` served every tested request; there were no other members.
The production service passed the live-sample shape, exact ID rejection, empty
result, 401 without retry, invalid JSON without retry, 503 bounded retries and
429 recovery. Swift compilation used language mode 6.
<!-- end:observations -->

## What didn't work

- 2026-10-28: local URLSession raised `NSPOSIXErrorDomain Code=1` under the
  command sandbox; no request reached the simulation. Running the same compiled
  binary with local-network permission passed.
- 2026-10-28: `postman mock generate` wrote its files but exited after
  `SecItemCopyMatching failed -50` under the command sandbox. The local simulation
  ran with normal keychain access; no new account or workspace was created.
