# Releasing ApiX

Pre-publish checklist. **Run this every time before `dart pub publish`** — do not
publish on a green "latest" build alone.

## Why this is not just "CI is green"

- **`pubspec.lock` is not committed** (see `.gitignore`). pub.dev ignores a
  library's lock anyway, so CI resolves dependencies **fresh on every run**. A
  build that was green yesterday can be **red today with no code change**, simply
  because a dependency published a new version in between.
- ApiX declares a **wide dependency range** (`dio: ">=5.4.0 <7.0.0"`). A minor
  release of a dependency can add an enum value or change a handler signature and
  break ApiX **within its own declared range** — which every consumer would hit.
  A build that only tests the latest version does **not** prove the floor still
  works, and vice-versa.

So the release gate is: **the full check must pass on both the floor and the
latest of the dependency range** — which is exactly what the CI matrix does
(`analyze` and `test` jobs run `dio: [floor, latest]`).

## Checklist

1. **Version + changelog**
   - Bump `version:` in `pubspec.yaml`.
   - Add a matching section to `CHANGELOG.md` (Added / Changed / Fixed / Breaking).
2. **Regenerate dartdoc — only if the public API changed**
   - Needed when a `///` doc comment or a public signature changed. Method bodies,
     `//` comments and `CHANGELOG.md` are **not** reflected in `doc/api/`, so a
     behaviour-only fix needs no regen.
   - `dart doc .` (writes to `doc/api/`), then review and commit the diff.
3. **Local verification on BOTH dependency bounds** (see commands below) — format,
   `dart analyze --fatal-infos lib test`, and `flutter test` must all pass on the
   floor **and** the latest.
4. **Push and wait for the CI matrix to be fully green** — all four cells
   (`analyze` × `{floor, latest}`, `test` × `{floor, latest}`) plus `format`.
5. **Dry run**: `dart pub publish --dry-run` — resolve every warning.
6. **Publish**: `dart pub publish`, then tag the release (`git tag vX.Y.Z`).

## Reproducing the CI matrix locally

CI pins **Flutter 3.24.0** for `format`/`test` and uses the **latest stable** for
`analyze`. Mirror both with FVM: use `3.24.5` (≈ CI test) and a recent stable
(e.g. `3.41.x`, ≈ CI analyze). Replace `<flutter>` with the version under test.

```bash
# --- LATEST of the dio range (fresh resolution, like CI with no lock) ---
<flutter> pub get                 # or: pub upgrade dio, to force the newest
dart format --set-exit-if-changed lib test
dart analyze --fatal-infos lib test
flutter test

# --- FLOOR of the dio range (what CI's `dio: floor` cell does) ---
<flutter> pub get
<flutter> pub downgrade dio       # pins dio to 5.4.0, keeps the rest resolvable
dart analyze --fatal-infos lib test
flutter test
```

Run the `analyze` step on the recent stable too — a newer analyzer surfaces lints
the pinned 3.24.x does not (e.g. `unreachable_switch_default`).

## Recurring gotchas

- **External enum evolution.** When a dependency's enum (e.g. `DioExceptionType`)
  gains a value in a newer release, a `switch` over it cannot name the new value
  (absent from the floor) nor omit it (non-exhaustive on the latest). Use a
  reachable `default:` and drop the redundant named cases so it stays exhaustive
  **and** reachable on both bounds.
- **Handler signature drift.** Interceptor handler overrides in tests
  (`ErrorInterceptorHandler.reject`, etc.) must match the signature across the
  whole range; adding an optional parameter is a valid override on both old and
  new versions.
- **Do not commit `pubspec.lock`.** Pinning it would make CI deterministic but
  would **hide** exactly the range drift this flow is meant to catch.
