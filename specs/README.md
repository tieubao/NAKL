# Specs

Spec-driven development for NAKL. **No code without an approved spec.**

Architectural decisions live in `/adr/`, not here. ADRs are write-once; supersede instead of editing.

## Workflow

1. Reserve a number in the [Index](#index) below and create `specs/NNNN-<short-slug>.md` from the [Template](#template). Status starts at `draft`.
2. Self-review or ask a reviewer; iterate until acceptance criteria are testable and unambiguous.
3. Flip status to `approved` and commit. Implementation can begin.
4. Implement on a branch named `feat/spec-NNNN-<short-slug>`. Status flips to `in-progress`.
5. PR title `feat(spec-NNNN): <one line>`. PR body references the spec and ticks each acceptance criterion.
6. After merge, status flips to `done` and the changelog gets the merge SHA.

## Status legend

| Status | Meaning |
|---|---|
| `draft` | Being written. Not safe to implement against. |
| `approved` | Locked. Implementation can begin. |
| `in-progress` | Branch open, work underway. |
| `blocked` | Waiting on an external factor. Note what in the spec body. |
| `done` | All acceptance criteria verified. Linked to the merge SHA. |
| `superseded` | Replaced by a newer spec. Top of the body says by which. |
| `planned` | Slot reserved in the index, file not yet written. Must be drafted before its predecessor finishes. |

## Numbering

- `0001` to `0099`: roadmap and umbrella specs.
- `0100` and up: future feature specs.

## Index

| # | Title | Status | Owner |
|---|---|---|---|
| [0001](0001-modernisation-roadmap.md) | Modernisation roadmap | approved | @tieubao |
| [0002](0002-build-baseline.md) | Build baseline (Xcode 16, macOS 12) | approved | @tieubao |
| [0003](0003-deprecation-cleanup.md) | Deprecation cleanup | approved | @tieubao |
| [0004](0004-arc-migration.md) | ARC migration | approved | @tieubao |
| [0005](0005-arm64-hardened-runtime.md) | arm64 + Hardened Runtime | approved | @tieubao |
| [0006](0006-asset-catalog.md) | Asset catalog refresh | approved | @tieubao |
| [0007](0007-engine-extraction.md) | Vietnamese engine extraction | approved | @tieubao |
| [0008](0008-engine-test-suite.md) | Engine test suite | approved | @tieubao |
| [0009](0009-imk-input-method.md) | IMK input method | draft (refined; awaits user go) | @tieubao |
| [0010](0010-notarisation.md) | Notarisation pipeline | approved | @tieubao |
| [0011](0011-login-item-migration.md) | SMAppService login-item migration | approved | @tieubao |
| [0012](0012-asset-bundle-cleanup.md) | Bundle cleanup + EnableAssistiveDevices script | approved | @tieubao |
| [0013](0013-status-item-main-thread.md) | Status-item main-thread dispatch | approved | @tieubao |
| [0014](0014-applescript-qos-inversion.md) | AppleScript launch QoS inversion fix | approved | @tieubao |
| [0015](0015-redistribution-ui-v2-roadmap.md) | Phase 9 roadmap: redistribution + UI v2 | done | @tieubao |
| [0016](0016-product-rebrand.md) | Product rebrand (Monke, foundation.d.Monke) | done | @tieubao |
| [0017](0017-swiftui-shell.md) | SwiftUI Preferences shell + macOS 14 deployment | done | @tieubao |
| [0018](0018-localization-vi-en.md) | Full vi/en localisation via String Catalog | done | @tieubao |
| [0019](0019-menubarextra-rewrite.md) | MenuBarExtra rewrite (retire main.m + AppDelegate + MainMenu.xib) | draft | @tieubao |
| [0020](0020-keyboardshortcuts-spm-swap.md) | KeyboardShortcuts SPM swap (retire vendored ShortcutRecorder + PTHotKey) | draft | @tieubao |

## Template

Copy this verbatim into a new `NNNN-<slug>.md` file:

```markdown
# SPEC-NNNN: <title>

**Status:** draft
**Owner:** @tieubao
**Depends on:** SPEC-XXXX, SPEC-YYYY (or `none`)
**Blocks:** SPEC-ZZZZ (or `none`)

## Problem
What is broken or missing today, in one paragraph.

## Goal
One sentence. Singular. If there are two goals, write two specs.

## Non-goals
What this spec deliberately does NOT do. Prevents scope creep.

## Acceptance criteria
Each criterion independently verifiable, with a concrete command or observation.
- [ ] `xcodebuild ... ` exits 0 with zero warnings.
- [ ] `lipo -archs build/Release/NAKL.app/Contents/MacOS/NAKL` prints `arm64 x86_64`.
- [ ] App launches on macOS 12.0 in a VM.

## Test plan
The exact commands a reviewer (or future-you) runs to verify the criteria.
- For engine specs: link the fixture file and the XCTest case names.
- For UI specs: a numbered manual-smoke checklist.

## Implementation notes
Constraints, gotchas, files to touch. Not a tutorial.

## Open questions
Anything unresolved that could invalidate the spec mid-implementation.

## Changelog
- YYYY-MM-DD: drafted
- YYYY-MM-DD: approved by @tieubao
- YYYY-MM-DD: completed in commit <sha>
```
