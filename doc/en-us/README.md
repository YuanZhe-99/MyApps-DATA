# MyApps-DATA Documentation (English)

This is the English documentation tree for the `myapps_data` package — the shared WebDAV-sync and
data-management engine behind **MyAnime**, **MyDay**, and **MyDevice**. The Simplified Chinese mirror
(`doc/zh-cn/`) is a follow-up phase and does not exist yet; see
[translation-guide.md](translation-guide.md) for how it will be produced.

**These docs are the authoritative description of the code.** The repository's
[AGENTS.md](../../AGENTS.md) is deliberately limited to instructions for agents — workflow, authoring
rules, the behavior contract, and the release process — and points here for everything else. When
code changes, these pages are updated first; when docs and code disagree, verify against the code and
then fix the page.

## Contents

- [architecture.md](architecture.md) — what this package is, its shape, the state of each engine
  area, and how the three sibling apps consume it.
- [translation-guide.md](translation-guide.md) — the English-to-Chinese translation guide and
  terminology glossary shared, byte-identical, across all four repos.
- [functions/INDEX.md](functions/INDEX.md) — the function index: every declaration in `lib/`, with
  links to full per-file documentation.

Two references live outside this tree:

- `docs/feature-matrix.md` (repo root) — the three-way behavioral audit of the apps' original
  implementations. This is where to look for *why* a shared behavior is the way it is, and which
  differences were made configurable versus unified.
- `PLAN.md` at the **workspace root** (a sibling of the app checkouts, not inside any repo) — the
  extraction plan, the hard invariants I1–I10, and the accepted-unification list.

## Current status

Complete and in production. All engine areas — storage, JSON preservation, merge, WebDAV transport
and sync, backup, ZIP transfer, and auto-sync scheduling — are implemented, exported from the public
barrel `lib/myapps_data.dart`, and documented under `functions/`. Focused unit tests plus 36
package-owned golden fixtures cover the shared behavior and the synthetic MyAnime/MyDay/MyDevice
registry shapes in CI.

All three apps consume this package and shipped on it in their `v1.3.0` releases; ~7,700 lines of
duplicated engine code left them, and every existing app test passed unmodified.

Each new source area must gain a `doc/en-us/functions/` page in the same change set — and a Chinese
translation too, once `doc/zh-cn/` exists.
