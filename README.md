# MyApps-DATA (`myapps_data`)

Shared WebDAV sync & data-management (backup/restore, ZIP import/export) Flutter package
for **MyAnime**, **MyDay**, and **MyDevice**.

Status: scaffold — engines land per the extraction plan (`PLAN.md` in the local
workspace root; phases P0–P4). Conventions and contributor rules: see [AGENTS.md](AGENTS.md).

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
