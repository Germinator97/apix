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

1. **The six places a version touches.** Not four, not five — the two that get
   forgotten are at the bottom, and each was forgotten at least once.

   | # | Place | Why it is missed |
   |---|-------|------------------|
   | 1 | `pubspec.yaml` — `version:` | — |
   | 2 | `CHANGELOG.md` — a `## X.Y.Z` heading, and `## Unreleased` folded into it | Never rewrite a section already on pub.dev |
   | 3 | `README.md` — the `apix: ^X.Y.Z` install snippet | It shows the **latest** version, so it moves on patches too |
   | 4 | `doc/api/` — `dart doc .` | The number is stamped into **every** page, so a bump alone rewrites all of them |
   | 5 | `apix_example_app/` — `flutter pub get`, commit the lock | A `path:` dependency does not update the lock on its own, and only the `enforce-lockfile` CI job compares them |
   | 6 | `apix/example/` — **both** `example.dart` *and* its `README.md` | The neighbouring README describes the file; it had drifted three majors |

   Places 1–3 are guarded by `test/readme_claims_test.dart` and
   `test/changelog_defaults_test.dart`, by equality in both directions. 4–6 are
   not, and are the reason this table exists.

   For 4, the rule of thumb: a `///` doc comment or a public signature changed
   means a regen is needed; method bodies, `//` comments and `CHANGELOG.md` are
   not reflected in `doc/api/`. A version bump always is.
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
