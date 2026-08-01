# MyApps-DATA Documentation (English)

This is the English documentation tree for the `myapps_data` package — the shared WebDAV-sync and
data-management engine behind **MyAnime**, **MyDay**, and **MyDevice**. The Simplified Chinese mirror
(`doc/zh-cn/`) is maintained alongside it; see [translation-guide.md](translation-guide.md) for the
translation and parity rules.

**These docs are the authoritative description of the code.** The repository's
[AGENTS.md](../../AGENTS.md) is deliberately limited to instructions for agents — workflow, authoring
rules, the behavior contract, and the release process — and points here for everything else. When
code changes, these pages are updated first; when docs and code disagree, verify against the code and
then fix the page.

## Contents

- [architecture.md](architecture.md) — what this package is, its shape, the state of each engine
  area, and how the three sibling apps consume it.
- [invariants.md](invariants.md) — the behavior contract: the hard invariants I1–I10, the
  unification rule, and every accepted unification with its consequence. **Read this before changing
  sync, backup, or ZIP behavior.**
- [feature-matrix.md](feature-matrix.md) — the historical three-way audit of the apps' original
  implementations and the decisions that became fixed behavior or configurable knobs.
- [translation-guide.md](translation-guide.md) — the English-to-Chinese translation guide and
  terminology glossary shared, byte-identical, across all four repos.
- [functions/INDEX.md](functions/INDEX.md) — the function index: every declaration in `lib/`, with
  links to full per-file documentation.

## Current status

Complete and in production. All engine areas — storage, JSON preservation, merge, WebDAV transport
and sync, backup, ZIP transfer, and auto-sync scheduling — are implemented, exported from the public
barrel `lib/myapps_data.dart`, and documented under `functions/`. Focused unit tests plus 36
package-owned golden fixtures cover the shared behavior and the synthetic MyAnime/MyDay/MyDevice
registry shapes in CI.

All three apps consume this package and shipped on it in their `v1.3.0` releases; ~7,700 lines of
duplicated engine code left them, and every existing app test passed unmodified.

Each new source area must gain a `doc/en-us/functions/` page and the matching Chinese page in the
same change set.
