# External services, tools and platforms

## Runtime — what the shipped app depends on

**One provider only: the Premier League.**

| Service | Endpoints used | Purpose | Auth |
|---|---|---|---|
| Fantasy Premier League public API | `/api/bootstrap-static/` — players, prices, form, stats, gameweeks<br>`/api/fixtures/` — fixture list with difficulty ratings<br>`/api/entry/{id}/` — a team's public profile<br>`/api/entry/{id}/event/{gw}/picks/` — that team's squad | All player and fixture data; optional import of a user's existing team | None — public, no key, no sign-in |
| Premier League image CDN (`resources.premierleague.com`) | `/premierleague/photos/players/110x140/p{code}.png` | Player photographs | None |

Both are read-only HTTPS `GET` requests made directly from the device. Nothing
is ever uploaded.

## Not used

- **Authentication** — none. No accounts, no Sign in with Apple, no OAuth, no Keychain.
- **Payments** — none. No StoreKit, no in-app purchases or subscriptions.
- **AI / ML services** — none. The projection model and squad optimiser are
  plain Swift running on the device; no model is called over a network.
- **Analytics, crash reporting, attribution** — none.
- **Advertising** — none. No ad SDK, no SKAdNetwork.
- **Backend / cloud** — none. The developer operates no server, no database and
  no API. All state lives on the device (`UserDefaults` and one JSON file in the
  app's Documents folder).
- **Push notifications, maps, storage, sync** — none. No CloudKit.

## Third-party code

**None.** No Swift Package Manager, CocoaPods or Carthage dependencies, and no
vendored libraries. The entire app imports only Apple's `Foundation` and
`SwiftUI`; the built binary links nothing beyond `libSystem` and its own dylib.

## Development tooling (not shipped, not contacted at runtime)

- Xcode / Swift / SwiftUI — build and UI
- XcodeGen — generates the `.xcodeproj` from `project.yml`
- Core Graphics — used by `Tools/GenerateAppIcon.swift` to render the app icon
- Git and GitHub — source control
- App Store Connect / TestFlight — distribution
