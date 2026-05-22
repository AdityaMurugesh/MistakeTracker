# MistakeTracker — 5-Day Execution Plan

3 people. 5 days. Flutter. Nobody has built a mobile app before.

## Roles (vertical feature ownership)

Each person owns one user-visible feature end-to-end. This avoids the "Person B can't build screens until Person A finishes models" bottleneck.

| Role | Owns | See file ownership |
|---|---|---|
| **Capture** | Entry form, home screen, DB layer | `FILE_OWNERSHIP.md` |
| **Insights** | Suggestion engine, insights screen | `FILE_OWNERSHIP.md` |
| **Reach & Data** | Notifications, export, settings, app shell | `FILE_OWNERSHIP.md` |

## Daily plan

Dates assume Day 1 = the day work starts. Shift them to your team's calendar.

### Day 1 — Together (3-4 hrs sync, rest async)

**Goal:** everyone can run the app on their emulator and the shared contracts are agreed.

- [ ] One teammate installs Flutter SDK on their machine: https://docs.flutter.dev/get-started/install
- [ ] That teammate runs `flutter create --platforms=android,ios --project-name=mistake_tracker .` inside `MistakeTracker/`, then `flutter pub get`, then `flutter run`. Commit the generated `android/`, `ios/`, and `lib/main.dart` (modify `main.dart` per README first).
- [ ] Other two install Flutter, pull, `flutter pub get`, `flutter run`. Confirm the empty app loads.
- [ ] All 3 read `DESIGN.md` together. Sign off on the four SHARED CONTRACT files (`entry.dart`, `insight.dart`, `suggestion_engine.dart`, `signal_source.dart`).
- [ ] Reach & Data finishes app shell + initial providers in `lib/state/providers.dart`.

### Day 2 — Independent feature builds

Each person works on their own branch (`feat/capture`, `feat/insights`, `feat/reach-and-data`).

- **Capture**: implement `database.dart` (open DB + create table), `entry_dao.dart` (insert + getAll + watchAll), wire `home_screen.dart` to the watch stream. End of day: can tap "+", land on a placeholder form, save a hardcoded entry, see it in the list.
- **Insights**: build the insights screen UI against a *stub* `RuleEngine` that returns 3 hardcoded `Insight`s. End of day: insights screen looks right with fake data.
- **Reach & Data**: skeleton `Notifier.init()` + scheduling one test notification on app launch. Settings screen with the "Export" button calling a stubbed `ExportService.shareLatestExport()`.

### Day 3 — Fill in the brains

- **Capture**: real entry form with all fields. Save/edit/delete. Validation. End of day: full CRUD works.
- **Insights**: replace `RuleEngine` stub with real implementation. All three rule families. Write unit tests in `test/rule_engine_test.dart`.
- **Reach & Data**: wire `TimeSignal` to read real DAO data and emit triggers. Wire `ExportService` to read real entries and produce real JSON. Hook export to `share_plus`.

### Day 4 — Integration & polish

- All 3: merge branches into `main`. Fix the integration bugs.
- Empty states, error banners, permission flows (notifications on Android 13+).
- Manual test checklist run end-to-end on one device.
- Triage: anything not working gets cut or stubbed for the demo.

### Day 5 — Demo prep

- README screenshots.
- Short writeup explaining the v1-simple/v2-ready architecture (this is the part the assignment grader cares about).
- Record a demo video.
- Final manual pass on the test checklist.
- Tag `v0.1.0`.

## Communication protocol

- **Daily 15-min standup** (5 min each): what I did, what I'm stuck on, what I'll do today.
- **Branch protocol:** branch per role → PR into `main` → one teammate reviews → merge.
- **Shared contracts** (`entry.dart`, `insight.dart`, `suggestion_engine.dart`, `signal_source.dart`) frozen after Day 1. Changes require all 3 to sign off in the PR.
- **Stuck > 1 hour** → ask the team channel. Don't grind alone.

## Manual test checklist (run on Day 4 and Day 5)

- [ ] Cold-start the app. Home loads in <1s. Empty state shows.
- [ ] Tap "+", fill `what` only, save. Entry appears on home.
- [ ] Tap entry, edit `solution`, save. Reopen — change persists.
- [ ] Insights tab. With <3 entries: empty state. After 3 same-cause entries: a "recurring cause" insight appears.
- [ ] Settings → Export. File is generated and share sheet opens.
- [ ] Deny notification permission. App still works. Banner shows in Settings.
- [ ] Grant notification permission. Create 3 entries with same `what` and time. Within a minute, no crash; a scheduled notification appears in the system tray at the right time (or use a test-only "fire now" button).
- [ ] Kill app, reopen — all data persists.
