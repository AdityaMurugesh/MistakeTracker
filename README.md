# MistakeTracker

A Flutter app that lets you log everyday failures — missed deadlines, impulse spends, skipped workouts, arguments — and surfaces the recurring causes, total cost, failure chains, and personalised prevention suggestions hidden in your own log.

> ACOP290 Project 2 · built by a 3-person team in 5 days · runs offline on Android (iOS-ready)

## Why this design

We had 5 days, 3 people, and none of us had shipped a mobile app before. Two things shaped every decision: **ship something demoable**, and **don't paint ourselves into a corner** if v2 wants smarter intelligence or cloud sync.

The result is a deliberately small v1 with extension seams documented for every feature we deferred. None of the v2 ideas require rewriting the v1 — they slot into an interface that already exists.

### v1 — what we built

| Layer | v1 implementation | Why |
|---|---|---|
| **Storage** | Local SQLite (`sqflite`) + manual JSON export | Zero backend risk; export gives a backup story without auth or accounts |
| **Intelligence** | Rule-based `RuleEngine` (3 rule families, pure Dart) | Explainable behaviour in the demo; no model dependency; testable in <1 second |
| **Notifications** | Local, time-based via `flutter_local_notifications` | Avoids push infrastructure and the cross-platform pain of background services |
| **State management** | Riverpod (DI + reactive providers) | Clean swap points for the v2 interfaces; same shape everywhere |
| **Entry model** | One `entries` table; one shared `Entry` Dart class | Single source of truth across all three roles |

### v2 — where it goes next, without rewriting

Each deferred feature has a documented seam in the v1 code:

| v2 feature | Extension point in v1 |
|---|---|
| Cloud sync (Firebase / Supabase) | Swap the `EntryDao` impl behind `entryDaoProvider` |
| LLM-powered suggestions | Add an `LLMEngine` that implements `SuggestionEngine`; `Insights` consumes the interface, not the impl |
| Calendar-aware notifications | Add a `CalendarSignal` that implements `SignalSource`; `Notifier` subscribes to any number of them |
| Location- / fitness-aware notifications | Same pattern — new `SignalSource` impls |
| Positive ("win") log | `Entry.kind` field is already in the schema; v2 only adds UI |
| Home-screen widgets | Native Android `AppWidgetProvider`; reads the same SQLite file |

The interfaces (`EntryDao`, `SuggestionEngine`, `SignalSource`, `Entry`, `Insight`) are tagged in the source as **SHARED CONTRACTS** — changing them requires sign-off from all three role owners, exactly because they're the seams v2 hinges on.

## Architecture

```
lib/
├── app.dart                     # MaterialApp + bottom-nav
├── main.dart                    # ProviderScope wrapper
├── data/
│   ├── database.dart            # sqflite open + schema + migration hook
│   ├── entry_dao.dart           # CRUD + watchAll() stream
│   └── export_service.dart      # JSON writer + share intent
├── domain/
│   ├── models/
│   │   ├── entry.dart           # core data class           [SHARED CONTRACT]
│   │   └── insight.dart         # suggestion-engine output  [SHARED CONTRACT]
│   ├── suggestion_engine.dart   # abstract interface        [SHARED CONTRACT]
│   └── rule_engine.dart         # v1 impl (3 rule families)
├── notifications/
│   ├── signal_source.dart       # abstract interface        [SHARED CONTRACT]
│   ├── time_signal.dart         # v1 impl
│   └── notifier.dart            # local-notifications glue
├── ui/
│   ├── home_screen.dart         # recent-entries list + "+" FAB
│   ├── entry_form.dart          # capture / edit form
│   ├── insights_screen.dart     # rule-engine output as cards
│   └── settings_screen.dart     # export + notification settings
└── state/
    └── providers.dart           # Riverpod providers (DI + reactive state)
```

Dependencies flow one way: `ui` → `state` → (`domain`, `data`, `notifications`). There are no back-edges.

## How insights work

The v1 `RuleEngine` runs three rule families over your entries, in pure Dart:

1. **Recurring cause** — group by `cause`; surface causes appearing ≥ 3 times in 30 days. Suggestion = your own past `solution` for the same cause, if you've ever logged one.
2. **Time-of-day pattern** — group by `(what, weekday)` and `(what, hour)`; flag combinations with ≥ 3 hits.
3. **Cost insight** — sum `cost_minutes` and `cost_money` across the lookback window.

All thresholds live as constants in `rule_engine.dart` so they're tweakable in one place. Swapping in an LLM in v2 means writing one `analyze(List<Entry>) -> List<Insight>` method on a new class — the `Insights` UI never sees the engine type, only the interface.

## Status (v1 scope)

| Feature | Status |
|---|---|
| Log a failure (full form with 9 fields + validation) | ✓ |
| Edit / delete entries | ✓ |
| Reactive recent-entries list with empty / loading / error states | ✓ |
| Rule-based insights (3 families) | ✓ |
| Settings + JSON export (`share_plus`) | ✓ |
| Local notifications (time-of-day patterns, Android 13+ runtime permission) | ✓ |
| Cloud sync | Deferred to v2 (swap-in point documented) |
| LLM suggestions | Deferred to v2 (swap-in point documented) |
| Win log | Deferred to v2 (`Entry.kind` field already in schema) |

## Testing

- **Unit / widget tests** under `test/`. Current count: 42 passing.
- **DAO integration tests** run against an in-memory SQLite via `sqflite_common_ffi`.
- **No end-to-end tests in v1** — a short manual checklist covers the demo path.

## Tech stack

`Flutter 3.44` · `Dart 3` · `sqflite` · `flutter_riverpod` · `flutter_local_notifications` · `share_plus` · `mocktail` (tests) · `sqflite_common_ffi` (tests)

## Team & roles

Three vertical-feature roles, each owning a slice end-to-end:

| Role | Owns | Branch |
|---|---|---|
| **Capture** | Entry form, home screen, DB layer | `feat/capture` |
| **Insights** | Suggestion engine, insights screen | `feat/insights` |
| **Reach & Data** | Notifications, export, settings, app shell | `feat/notifications` |

See [`docs/FILE_OWNERSHIP.md`](docs/FILE_OWNERSHIP.md) for the file-by-file mapping.

## Running it locally

```bash
git clone https://github.com/AdityaMurugesh/MistakeTracker.git
cd MistakeTracker
flutter pub get
flutter run                # picks up any connected device or running emulator
```

Tested target: Android API 33+ on an `x86_64` emulator (`Medium_Phone_API_36.1`).

## Further reading

- [`docs/DESIGN.md`](docs/DESIGN.md) — full design doc (decisions, data model, error handling)
- [`docs/EXECUTION_PLAN.md`](docs/EXECUTION_PLAN.md) — the 5-day plan with daily milestones
- [`docs/FILE_OWNERSHIP.md`](docs/FILE_OWNERSHIP.md) — who owns what
