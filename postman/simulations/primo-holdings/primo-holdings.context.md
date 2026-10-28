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
swiftc -swift-version 6 -parse-as-library fingerprint-library/Domain/Book/BookHolding.swift fingerprint-library/Clients/Book/PrimoHoldingsMapper.swift fingerprint-library/Clients/Book/PrimoBookHoldingsService.swift Scripts/verify-primo-holdings.swift -o /tmp/primo-holdings-proof
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
