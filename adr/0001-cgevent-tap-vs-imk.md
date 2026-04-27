# ADR-0001: Modernise CGEventTap path first; defer InputMethodKit rewrite

**Status:** accepted
**Date:** 2026-04-27
**Deciders:** @tieubao
**Consulted:** Claude Code

## Context

NAKL captures Vietnamese-input keystrokes by installing a global `CGEventTap` from `AppDelegate.eventLoop` (see `NAKL/AppDelegate.m:295`) and rewriting events in-place before they reach the focused application. The mechanism is functional but carries permanent friction:

- Requires the user to grant **Accessibility** (and on macOS 10.15+, **Input Monitoring**) on every install and after most macOS updates.
- Cannot type into apps that have **Secure Input** enabled (password fields, lock screens).
- Per-app context is approximated via excluded-app bundle IDs; there is no per-document state.
- Apple has progressively tightened TCC on event taps over the last several macOS releases. There is no published commitment to keep this surface stable.

The Apple-blessed alternative is **InputMethodKit (IMK)**: ship an `.app` whose principal class subclasses `IMKInputController`, register it as an input source, and let the system route keys to it when the user selects "NAKL" in the input menu. Every actively-maintained third-party Vietnamese input method on macOS today (GoTiengViet, OpenKey, Vietnamese 2.x) works this way.

## Decision drivers

- The repo's current state: 14-year-old MRC code, untested, does not build on current Xcode.
- The user's stated constraint: personal use first, macOS 12+ floor.
- The Vietnamese transformation engine is currently inseparable from the event-tap callback. Any path forward needs that engine extracted; IMK *forces* the extraction, CGEventTap modernisation merely *enables* it.
- Time budget: the user wants a working modern build "now", not in a month.

## Considered options

### A. Modernise the CGEventTap path only

Patch deprecations, migrate to ARC, fix arm64, leave the architecture as-is.

| Pros | Cons |
|---|---|
| 2-3 days to a working app. | Leaves structural fragility (TCC, Secure Input, no per-app state) untouched. |
| Minimal blast radius. | Engine remains entangled with the event-tap callback; testing still painful. |
| Preserves existing UX (status bar, hotkeys, excluded apps) verbatim. | Each macOS release continues to risk breakage on the event-tap surface. |

### B. Rewrite as IMK input method now, abandon CGEventTap

Build a new IMK target from scratch, port the Vietnamese maps and Telex/VNI logic, decommission `AppDelegate.KeyHandler`.

| Pros | Cons |
|---|---|
| Future-proof. No Accessibility prompt. | 2-4 weeks of work for an app that one user uses. |
| Survives Secure Input. | Throws away working UI (Preferences, hotkeys, excluded apps) and rebuilds inside IMK constraints. |
| Per-document state available. | High risk of "rewrite that never ships". |
| Aligns with the macOS-native input ecosystem. | No working app during the migration. |

### C. Sequence A then B, with engine extraction as the bridge

Modernise the CGEventTap codebase (phases 0-4), extract the Vietnamese engine into a pure module (phase 5), test the engine (phase 6), then build IMK on top of the same engine (phase 7).

| Pros | Cons |
|---|---|
| Working app at every checkpoint. | Longest total elapsed time if B is executed. |
| Engine extraction is mandatory work for B and useful for A: no effort wasted regardless of whether B is ever executed. | Two implementations of the input shell live side-by-side once phase 7 ships, until one is retired. |
| Decision to actually do B can be reopened after phase 6, with concrete data on whether the modernised CGEventTap version is "good enough for personal use forever". | |

## Decision

**Choose C.** Modernise the existing CGEventTap codebase first; extract and test the engine; defer the IMK rewrite to a re-evaluated decision point after phase 6.

The IMK rewrite is drafted as SPEC-0009 at `draft` status so the eventual contract is visible, but it is not approved for execution.

## Consequences

### Positive

- A working app on macOS 12+ exists within the first week.
- Engine extraction (SPEC-0007) becomes a forcing function for testability regardless of whether IMK ever ships.
- Decision to invest the 2-4 weeks for IMK can be made with the modernised app already in hand, eliminating "rewrite that never ships" risk.

### Negative

- If IMK is eventually executed, the CGEventTap shell becomes dead code and the modernisation effort spent on `AppDelegate.KeyHandler` (phases 1-2) is partially sunk cost. Estimated waste: ~1.5 days.
- The user must continue to grant Accessibility / Input Monitoring permissions on macOS updates until phase 7 ships.

### Neutral

- Vendored libraries (`ShortcutRecorder`, `PTHotKey`) keep working under both A and B; their retain-or-replace decision is orthogonal and will be made in its own ADR when first relevant.

## Reopen criteria

This ADR should be revisited if any of the following happen:

- Apple announces deprecation or breaking change to `CGEventTap` for keyboard events on a future macOS version.
- The user decides to share NAKL publicly or submit to the App Store. App Store distribution rules out CGEventTap.
- Phase 6 reveals the engine extraction is significantly cheaper than estimated, making the marginal cost of also doing phase 7 small enough to justify pulling it forward.
