# AGENTS.md — myapps_data (MyApps-DATA)

Operating guide for agents working on this repository. This file holds **only** rules about how to
work here. Everything describing what the code *is* or *does* lives in `doc/en-us/` — see
[Where to read what](#where-to-read-what).

`myapps_data` is the shared WebDAV-sync and data-management package consumed by three sibling apps
(**MyAnime**, **MyDay**, **MyDevice**) as a git submodule at `packages/myapps_data`. It is the
load-bearing layer under all three: a bug here ships to all of them, and a wire-format change here
can strand existing installs.

## Reading order

When you need to understand code, read in this order and stop as soon as you have what you need:

1. **`doc/en-us/`** — start here, always. `architecture.md` for shape and consumption model;
   `functions/<path>.md` for a specific file's declarations;
   `functions/INDEX.md` to find the right page.
2. **Comments in the source** — the Function Explanation Layer above each declaration.
3. **The implementation** — only when the docs and comments are insufficient, or when you must
   confirm actual behavior before changing it.

Do not jump straight to reading source bodies. Do not trust the docs over the code when they
disagree on something you are about to change — verify, then fix the docs.

## Where to read what

| Question | Read |
|---|---|
| What is this package, how do apps consume it | `doc/en-us/architecture.md` |
| What does this file/function do | `doc/en-us/functions/<mirrored path>.md` |
| Which page covers which source file | `doc/en-us/functions/INDEX.md` |
| The behavior contract: invariants I1–I10, accepted unifications | `doc/en-us/invariants.md` |
| Why a behavior is the way it is, per app | `docs/feature-matrix.md` (the three-way audit) |
| English→Chinese terminology | `doc/en-us/translation-guide.md` |

## Required workflow

1. Treat the user's message as the modification request.
2. Before editing, fetch the relevant remote(s) and check whether the local branch is behind.
   Resolve any divergence before starting.
3. Read per [Reading order](#reading-order).
4. Plan when the work is non-trivial, then implement.
5. Keep changes scoped; do not revert unrelated work in the tree.
6. Update documentation in the same change set — see [Documentation maintenance](#documentation-maintenance).
7. Verify: `flutter pub get && flutter analyze && flutter test`.
8. Report briefly what changed, what was verified, and anything you could not do.
9. Ask before pushing. The user confirms the release version before any release push.

## Documentation maintenance

**Docs are the primary artifact. Update them first, and never let them drift.**

Any change that adds, removes, or changes the behavior or signature of a declaration must update, in
the same commit:

- the per-file page under `doc/en-us/functions/`,
- its `INDEX.md` row (including the declaration counts),
- `architecture.md` when the change affects the package's shape or consumption model.

Once `doc/zh-cn/` exists it must mirror `doc/en-us/` exactly — same files, headings, tables, and
examples — updated in the same commit and translated per `translation-guide.md`. New terminology goes
into `translation-guide.md`: cross-cutting terms into Section 5.1 in **all four** sibling repos,
app-specific terms into that repo's own Section 5.2. This package is headless, so its Section 5.2
stays empty.

Prefer putting explanation in `doc/en-us/`. Keep this file limited to agent instructions; if you find
yourself adding a paragraph here that describes how the code works, it belongs in the docs instead.

Documentation-only commits do not bump versions or create tags.

## Authoring rules

**Function Explanation Layer.** Every function, method, significant callback helper, constructor,
getter, and setter carries a structured comment immediately above it:

- `Purpose: <one short sentence describing what the declaration is responsible for>`
- `Inputs: <important parameters only; omit obvious ones if trivial>`
- `Returns: <what the caller receives, or None>`
- `Side effects: <state changes, file/network/database/UI effects, logging, mutation, or None>`
- `Notes: <important assumptions, edge cases, invariants, or when the declaration should be used;
  prefer None when there is nothing special to add>`

Keep each explanation concise. Add one when adding a declaration, and update it in the same change
when editing an existing one. Use `///` doc comments in Dart.

These comments are the second layer of the [Reading order](#reading-order), so they have to stay
accurate: an agent that trusts a stale comment will make a wrong change. Still verify important
behavior in the implementation before relying on a comment for anything load-bearing.

Other conventions:

- **UTC timestamps** for anything compared across devices. Local-time values break sync conflict
  detection.
- **Pretty-printed JSON** via `JsonEncoder.withIndent('  ')`.
- **Preserve unknown JSON fields** end-to-end (parse → merge → write). Never drop fields this package
  does not model — an older build must not delete a newer build's data.
- **No app-specific knowledge.** No app model imports, no hardcoded data-file lists, no localized
  user-facing strings. App specifics arrive via `DataModule` descriptors and `StorageAdapter`.
- Lints: `flutter_lints` baseline (`analysis_options.yaml`), no custom overrides.
- License: GPL-3.0 (the code originates from the GPL-3.0 apps).

## Behavior contract

This package is consumed by three shipped apps, so treat these as non-negotiable unless the user
explicitly decides otherwise:

- The **WebDAV wire format**, remote layout, and `.lock` semantics (60s TTL, 20s heartbeat) are a
  compatibility contract with builds already in the field.
- Local formats — `webdav_config.json`, `.sync_base/`, `backups/` bundles and blobs — likewise.
- Conflicts are **never** silently auto-resolved.
- Restore disables auto-sync before the first write and re-enables it only if nothing was written.

The full invariant table (I1–I10) is in `doc/en-us/invariants.md`; the per-behavior rationale is in
`docs/feature-matrix.md`. When drift between the apps forces a choice, follow the unification rule in
`invariants.md`: prefer unifying over adding a knob, flag it to the owner, and record the accepted
change and its consequence in that file's table.

## Remotes and releases

- `origin` → `<local_gitea_address>` (private Gitea)
- `github` → `git@github.com:YuanZhe-99/MyApps-DATA.git` (public; app CI fetches the submodule here)
- Branch: `main`.

**Masking rule:** never commit the real Gitea host or port anywhere — docs, comments, CI,
`.gitmodules`. Consumers use the relative URL `../MyApps-DATA.git`. Find the real address with
`git remote -v` when you need it; never write it down.

Release flow: semver, a `CHANGELOG.md` entry, an annotated tag `vX.Y.Z`, pushed to **both** remotes.

**Push here to both remotes before bumping any app's submodule pointer.** A pointer to an unpushed
commit breaks every other clone and every app's CI. Apps must pin to a tagged commit before an app
release.

## Verification

```bash
flutter pub get && flutter analyze && flutter test
```

CI (`.github/workflows/ci.yml`, GitHub only) runs all three on every push and PR to `main` with
Flutter 3.44.2 — deliberately stricter than the apps, because this is the shared layer. The golden
fixtures under `test/golden/` run in **verify** mode by default; to re-record them intentionally,
pass `--dart-define=GOLDEN_RECORD=true` (literally `true` — `bool.fromEnvironment` treats `1` as
false and silently stays in verify mode).

## Never commit

Secrets, WebDAV credentials, test-server configs with real hosts, signing keys, the real Gitea
address, `pubspec.lock` (this is a library package), or golden files containing personal data from
the apps.
