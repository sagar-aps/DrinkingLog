# DrinkingLog

DrinkingLog is a **cross-platform mobile app** for Android and iOS. It tracks alcohol consumption and optional next-morning outcomes such as hangover severity, symptom tags, and notes.

The primary product constraint is that logging a drink must remain immediate and distraction-free. V1 is local-first and requires no account.

## Ralph harness configuration

Use:

```text
--type generic
```

Do **not** use `nextjs-postgres`. DrinkingLog is not a web app, CLI, Next.js project, or client/server product.

The dependency-ordered implementation plan is tracked in [the V1 epic](https://github.com/sagar-aps/DrinkingLog/issues/1). Run one numbered V1 issue at a time and advance after its acceptance criteria and repository checks pass.

## Intended stack

- Expo + React Native
- TypeScript with strict type checking
- One shared Android/iOS codebase
- Expo Router for navigation, unless the foundation issue documents an equivalent lightweight choice
- SQLite through Expo-compatible local persistence
- Archivo bundled as the application font
- npm and a committed lockfile
- Jest plus React Native Testing Library for unit and component tests
- Maestro for device-level Android E2E flows
- Native platform facilities for notifications, date/time pickers, sharing, safe areas, back navigation, and long-press haptics

Use current stable compatible versions when the project is bootstrapped; pin them in the lockfile rather than recording floating versions here.

## Architecture boundary

V1 is intentionally local-only:

- no Postgres or other remote database;
- no API server;
- no authentication or mandatory account;
- no cloud sync;
- no product analytics;
- no web application requirement.

Drink inputs are stored locally. Pure alcohol grams and locale-specific standard drinks are derived from those inputs. The only outbound flows are explicit CSV sharing and local OS notification handling.

## Development preview

The meaningful preview target is an **Android emulator or physical Android device** using Expo/Metro. iOS must remain buildable from the same codebase, but Android is the first private dogfood target.

Expected commands after bootstrap:

```bash
npm install
npm run start
npm run android
npm run ios
```

A browser preview is not an acceptance target. Do not wire Playwright or treat Expo Web rendering as proof that the mobile UI works.

## Automated checks

The foundation issue should create `scripts/check.sh`. It must be non-interactive, fail fast, and run from a clean checkout:

```bash
#!/usr/bin/env bash
set -euo pipefail

npm ci
npm run format:check
npm run lint
npm run typecheck
npm run test:ci
```

`test:ci` must run once and exit; it must not enter watch mode. The check script must not require an emulator, physical device, Expo account, network service, or running preview server.

If a lightweight Expo bundle/config validation is added later, expose it as a separate npm script and add it to `scripts/check.sh` only when it remains deterministic in CI.

## E2E checks

Device E2E is separate from `scripts/check.sh` because it requires an installed app and Android emulator/device.

Expected command once the E2E issue is implemented:

```bash
npm run e2e:android
```

Maestro flows should cover the critical path described by the V1 issues: quick logging, undo, detailed/backfilled entry, editing/deletion, next-morning check-in, targets, graph/calendar navigation, export, and notification actions.

## Delivery target

The first delivery is an installable Android development build for a 14-day private dogfood test. App-store submission, a production backend, web deployment, accounts, and V2 habit types are outside this build.
