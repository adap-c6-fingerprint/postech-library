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
- Keep the locally imported C5 Apple sample data out of Git. See Docs/IndoorMapData.md.
- Follow the user-provided PR_REVIEW_RULES.md when reviewing and publishing changes.
