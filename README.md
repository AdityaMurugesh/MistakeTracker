# MistakeTracker

A Flutter app for logging everyday failures (missed deadlines, impulse spends, skipped workouts, arguments, etc.) and surfacing recurring causes, total cost, failure chains, and personalized prevention suggestions.

ACOP290 Project 2. Built by a 3-person team in ~5 days.

## Quick start (first person to set up locally)

The repo currently has the `lib/`, `test/`, and `docs/` skeleton but no Android/iOS platform folders or `pubspec.lock`. The first teammate to set up locally must:

```bash
# 1. Install Flutter SDK (one-time): https://docs.flutter.dev/get-started/install
flutter --version            # confirm

# 2. Generate the platform folders (android/, ios/) WITHOUT overwriting lib/
cd MistakeTracker
flutter create --platforms=android,ios --project-name=mistake_tracker .

# 3. Install dependencies
flutter pub get

# 4. Run on an emulator or device
flutter run
```

> **Important:** `flutter create` may try to overwrite `lib/main.dart` if you create one before running it. We deliberately ship without `lib/main.dart` so `flutter create` can generate the default. After it runs, replace the generated `main.dart` body with:
> ```dart
> import 'package:flutter/material.dart';
> import 'package:flutter_riverpod/flutter_riverpod.dart';
> import 'app.dart';
>
> void main() => runApp(const ProviderScope(child: MistakeTrackerApp()));
> ```

After `flutter create` succeeds, commit the generated `android/`, `ios/`, and `lib/main.dart`.

## Documentation

- [`docs/DESIGN.md`](docs/DESIGN.md) — architecture, data model, flows, error handling, testing
- [`docs/EXECUTION_PLAN.md`](docs/EXECUTION_PLAN.md) — 5-day plan with daily milestones
- [`docs/FILE_OWNERSHIP.md`](docs/FILE_OWNERSHIP.md) — which file is owned by which role; claim yours here

## Roles

Three feature-vertical roles. Pick one:

1. **Capture** — entry form, home screen, DB layer
2. **Insights** — rule engine, insights screen
3. **Reach & Data** — notifications, export, settings, app shell

See `docs/FILE_OWNERSHIP.md` for the file-by-file mapping.

## Branch protocol

- Each role works on its own branch: `feat/capture`, `feat/insights`, `feat/reach-and-data`.
- PRs into `main`, reviewed by one other teammate before merge.
- The contract files (`lib/domain/models/`, `lib/domain/suggestion_engine.dart`, `lib/notifications/signal_source.dart`) are **shared**. Changes need a 3-person sign-off.
