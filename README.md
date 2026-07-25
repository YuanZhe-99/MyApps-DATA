# MyApps-DATA (`myapps_data`)

Shared WebDAV sync & data-management (backup/restore, ZIP import/export) Flutter package
for **MyAnime**, **MyDay**, and **MyDevice**.

Status: **stable and in production at `v1.0.0`.** All three apps consume this package and shipped on
it in their `v1.3.0` releases.

The package provides shared sync-progress and wake-lock helpers, JSON preservation, generic record
merging, atomic file replacement with optional serialized write queues, the WebDAV transport client
and generic sync engine (ordered app modules, upload-lock lifecycle, base snapshots, conflict
finalization, image sync, and force operations), the local backup engine (v2 blob store,
reference-counted GC, retention, guarded daily auto-backup, and validate-before-write v1/v2 restore
with the auto-sync-disable safety rule), the ZIP transfer engine (registry-driven export allowlist,
traversal-safe two-phase import, per-app strictness knobs), and the auto-sync scheduler
(lifecycle/debounce/periodic core with app hooks preserving each app's trigger topology and side
effects). Package-owned request and format goldens cover synthetic MyAnime, MyDay, and MyDevice
registries in CI.

- Documentation: [`doc/en-us/`](doc/en-us/) — start at its README.
- Behavior contract (invariants, accepted unifications): [`doc/en-us/invariants.md`](doc/en-us/invariants.md).
- Per-behavior audit of the three apps' original implementations: [`docs/feature-matrix.md`](docs/feature-matrix.md).
- Contributor and agent rules: [AGENTS.md](AGENTS.md).

## Consuming (apps)

Embedded as a git submodule + pub path dependency:

```bash
# once per app repo
git submodule add ../MyApps-DATA.git packages/myapps_data
```

```yaml
# app pubspec.yaml
dependencies:
  myapps_data:
    path: packages/myapps_data
```

Fresh app clone: `git clone --recurse-submodules <app-url>` (or `git submodule update --init`).

Bump an app to a newer shared version:

```bash
cd packages/myapps_data
git fetch origin --tags && git checkout vX.Y.Z
cd ../.. && flutter analyze && flutter test
git add packages/myapps_data && git commit -m "Bump myapps_data to vX.Y.Z"
```

## Contributing back

The submodule checks out detached; switch to a branch first (`git switch main`).
Push to **both** remotes (`origin`, `github`) before committing any app's pointer bump.

## Verify

```bash
flutter pub get && flutter analyze && flutter test
```

The P2.10 fixtures verify by default with `flutter test
test/golden/shared_engines_golden_test.dart`. Re-record an intentional change
with `flutter test --dart-define=GOLDEN_RECORD=true
test/golden/shared_engines_golden_test.dart`.
