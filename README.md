# FPL Picker

An iOS app that builds a legal Fantasy Premier League squad for you from live
FPL data — budget, favourite clubs and as much or as little input as you want.

## Running it

```bash
open FPLPicker.xcodeproj
```

Pick any iPhone simulator and hit run. Or from the command line:

```bash
xcodebuild -project FPLPicker.xcodeproj -scheme FPLPicker -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

The Xcode project is generated from `project.yml`. After adding or renaming
source files, regenerate it:

```bash
xcodegen generate
```

Requires iOS 17+ and a network connection — all data is fetched live.

## App Store submission notes

- `ITSAppUsesNonExemptEncryption` is set to `false` in the generated Info.plist
  (via `INFOPLIST_KEY_ITSAppUsesNonExemptEncryption` in `project.yml`), so App
  Store Connect stops asking the export-compliance question on every upload. The
  app uses no encryption beyond the HTTPS that the operating system provides,
  which is exempt.
- The App Privacy questionnaire can be answered **Data Not Collected** — see
  [PRIVACY.md](PRIVACY.md).

## How it works

### 1. The survey

Six questions on first launch. The first asks whether you already have a real
FPL team; four gauge how much football you actually know; the last asks how much
you want to decide yourself. Every bit of jargon in the questions is defined
inline, with a **Jargon buster** (`Glossary.swift`) one tap away that explains
xG, xA, FDR, EO, hits, price changes and the rest in plain English — reachable
later from the inputs screen too.

The knowledge questions produce a score and a recommended mode, which you can
override before continuing:

| Mode | You provide | The app decides |
|---|---|---|
| **Do It For Me** | Nothing | Everything, at the standard £100.0m |
| **Guided** | Budget, clubs you want players from | Everything else |
| **Full Control** | Risk appetite, fixture horizon, form weighting, club cap, must-haves, blocklist | The optimisation |

The answer is saved, so later launches go straight to the inputs screen. The
mode chip in the header switches modes or retakes the survey at any time.

### 2. Working from a team you already own

Answering "yes" to the first question opens **Your current team**, where you can
either:

- **Import with your FPL team ID** — the number in the address when you view
  your team on the FPL site. The app fetches your squad, bank and squad value
  from `/entry/{id}/` and `/entry/{id}/event/{gw}/picks/`. Before the season
  starts FPL publishes neither, so the app says so plainly and points you at the
  manual route.
- **Pick the 15 by hand** — position by position, with players already chosen
  and anyone who'd break the three-per-club rule visibly blocked rather than
  hidden.

Either way you set your **bank** and **free transfers**, and the squad is saved
so you don't have to type it in again.

`TransferPlanner` then works out what to change. It scores every legal single
swap by how much it improves your best XI (the same objective the optimizer
uses), takes the best, re-plans, and repeats up to your free transfers. It will
suggest one transfer beyond them only when that move alone beats the 4-point
hit, and says so explicitly. Each suggestion can be applied individually or all
at once, and the count of free transfers left updates as you go.

Saved teams reload the same way, so suggestions work for them too.

### 3. Live data

`FPLService` fetches the official endpoints — no key needed:

- `https://fantasy.premierleague.com/api/bootstrap-static/` — players, prices,
  form, ownership, per-90 stats, gameweeks
- `https://fantasy.premierleague.com/api/fixtures/` — fixture list with
  difficulty ratings

Numeric fields arrive inconsistently as strings or numbers, so `LooseDouble`
accepts either.

### 4. Projection

`ProjectionEngine` scores every player as expected points per gameweek:

- **Scoring rate** — a blend of recent form, season-long points per game and
  points per 90, anchored against FPL's own `ep_next`
- **Underlying stats** — xG/xA per 90, clean-sheet and save rates, weighted by
  position, so players due a return aren't overlooked
- **Fixtures** — average difficulty over the next N gameweeks, plus double and
  blank gameweek adjustments
- **Minutes security** — share of available minutes played
- **Availability** — injury, suspension and doubt status
- **Risk appetite** — rewards low ownership (differentials) or high ownership
  (the template), depending on the dial
- **Penalty duty** — a nudge for first-choice penalty takers

### 5. Optimisation

`SquadOptimizer` builds a genuinely legal squad, not just a value ranking:

- £100.0m (or your budget), 2 GKP / 5 DEF / 5 MID / 3 FWD, max 3 per club
- Search starts from the cheapest legal squad — always feasible — then does
  best-improvement hill climbing on single-player swaps, with eight random
  perturbation restarts to escape local optima
- Each candidate squad is scored by its best legal starting XI (every formation
  is tried), with the captain counted twice and bench players at 12%. Cheap
  bench fodder therefore falls out naturally rather than being hardcoded
- Must-have players are locked; blocklisted players never enter the pool
- A fixed seed keeps results reproducible for identical inputs

The result screen shows the pitch, formation, captain and vice, bench in
substitution order, spend, projected points and the reasoning behind each pick.

### 6. Editing by hand

Tap any player on the pitch or bench to open them, then:

- **Make captain / vice** — starters only; the armband swaps if you pick the
  current vice
- **Bench / bring on** — lists only the swaps that leave a legal formation, so
  you can't end up with two keepers or no forwards
- **Replace** — the transfer market for that position, showing what you can
  spend on the slot, each player's price difference, and why anyone unpickable
  is blocked ("too expensive", "3 from this club")
- **Auto-pick XI** — throws away manual bench choices and re-picks the best
  legal XI from your 15

Every edit is validated against the same rules the optimizer uses (budget,
three per club, formation), and spend, formation and projected points update
immediately. An EDITED badge appears once you've changed anything.

### 7. Saving and sharing

**Save** stores the team in `saved-teams.json` in the app's Documents folder.
Only player IDs and your XI/armband choices are kept, so reopening a team
re-reads today's prices, form and fixtures rather than showing a stale snapshot.
Teams can be renamed or deleted by swiping in the saved-teams list, and reached
from either the squad screen ("My teams") or the inputs screen.

**Share** renders the squad two ways through the system share sheet: a pitch
image drawn for export (club-coloured badges rather than remote photos, which
wouldn't have loaded in time for `ImageRenderer`), or a plain-text lineup that
pastes cleanly into a mini-league chat.

### 8. Settings

The gear in the header of the inputs and squad screens opens app-wide settings,
kept separate from the per-squad inputs:

- **Appearance** — five accent themes (mint, sky, sunset, magenta, lime) applied
  live across the app, and a switch for player photos versus club badges
- **Player cards** — minimal / standard / full detail on the pitch (full adds
  projected points under every player), plus optional ownership percentages in
  the player lists
- **Defaults** — the budget used when the app picks a squad unprompted, whether
  a rebuild confirms before discarding hand-made edits, and a shortcut to retake
  the survey
- **Data** — when the FPL data was last fetched, and a refresh that re-prices the
  squad on screen without changing the picks
- **About** — the jargon buster, version, and the "unofficial" disclaimer
- **Stored data** — delete all saved teams, or reset the app back to a first
  launch (both behind confirmation alerts)

Settings persist in `UserDefaults` and apply immediately.

## App icon

The icon is drawn in code rather than hand-painted: `Tools/GenerateAppIcon.swift`
renders a 1024pt PNG with Core Graphics — the squad as a formation of dots
(keeper, three at the back, three in midfield, a ringed captain up front) in the
app's mint-to-cyan accent gradient, over the same purple as the app background,
with faint pitch markings. Regenerate it after a palette change:

```bash
swiftc -O -o /tmp/icongen Tools/GenerateAppIcon.swift && (cd Sources/Assets.xcassets/AppIcon.appiconset && /tmp/icongen)
```

## Source layout

```
Sources/
  FPLPickerApp.swift          app entry
  Assets.xcassets             the app icon
  Models/FPLModels.swift      API shapes + position rules
  Models/Preferences.swift    skill mode, budget, club and strategy settings
  Models/SavedTeam.swift      stored teams + the JSON file store
  Models/ExistingTeam.swift   a squad the user already owns, and its validation
  Models/Glossary.swift       plain-English definitions of the jargon
  Models/AppSettings.swift    accent, card detail and app-wide defaults
  Services/FPLService.swift   live API client
  Engine/ProjectionEngine.swift  stats → expected points
  Engine/SquadOptimizer.swift    expected points → legal 15
  Engine/SquadEditor.swift       validated manual transfers, subs and armband
  Engine/TransferPlanner.swift   what to change about a squad you already own
  ViewModels/AppState.swift   phases, persistence, editing, background builds
  Views/                      survey, jargon buster, team import, inputs, pitch,
                              player detail, transfers, saved teams, share card,
                              settings
```

## Notes

- Player photos come from the Premier League CDN and are not updated until the
  season opens, so a summer signing may appear in their previous club's kit.
  Every card shows the club from the live data next to the price.
- "Only these clubs" needs at least five clubs selected, since no more than
  three players may come from one club.
