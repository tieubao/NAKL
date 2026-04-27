# SPEC-0009: InputMethodKit input method (deferred draft)

**Status:** draft
**Owner:** @tieubao
**Depends on:** SPEC-0007, SPEC-0008
**Blocks:** none

> ⚠️ This spec is intentionally `draft`, not `approved`. Per [ADR-0001](../adr/0001-cgevent-tap-vs-imk.md) and [SPEC-0001](0001-modernisation-roadmap.md), the decision to execute is reopened after SPEC-0008 ships, with the modernised CGEventTap version already in hand.

## Problem

The CGEventTap input model has known long-term liabilities:

- Every install requires Accessibility and Input Monitoring grants.
- Password fields with Secure Input cannot be typed into.
- There is no per-document state.
- Apple has tightened TCC on event taps repeatedly across recent macOS releases.

The Apple-blessed alternative is **InputMethodKit (IMK)**, where the OS routes keys directly to an `IMKInputController` subclass when the user selects "NAKL" from the input menu.

## Goal

Build a new IMK target inside `NAKL.xcodeproj` that registers as a Vietnamese input source on macOS 12+, reuses the SPEC-0007 engine verbatim, and replaces the CGEventTap menu-bar app for typing tasks.

## Non-goals

- Behavioural changes to the engine. Same Telex / VNI semantics.
- App Store submission. Out of scope unless explicitly opened.
- Custom UI for candidate windows. Vietnamese input methods do not use them; reject any drift in that direction.

## Acceptance criteria (proposed; may change before approval)

- [ ] New target `NAKL-IM` produces an `.app` bundle whose `Info.plist` contains:
  - `LSBackgroundOnly = YES`
  - `InputMethodConnectionName = vn.huyphan.NAKL_Connection`
  - `InputMethodServerControllerClass = NAKLInputController`
  - `tsInputMethodIconFileKey` referencing the asset catalog
  - `tsInputMethodCharacterRepertoireKey = ["vi"]`
- [ ] `NAKLInputController : IMKInputController` is the principal class.
- [ ] `inputText:client:` forwards every key to `nakl_engine_add_key`; replays via `[client insertText:replacementRange:]`.
- [ ] Bundle installable via `cp -R NAKL-IM.app ~/Library/Input\ Methods/`.
- [ ] After install + System Settings → Keyboard → Input Sources → Add → Vietnamese → NAKL, the IM appears in the input menu.
- [ ] Selecting NAKL and typing `tieengs vieet` in TextEdit produces `tiếng việt`.
- [ ] Same in a Secure Input password field (the differentiator vs CGEventTap).
- [ ] No Accessibility / Input Monitoring permission required.
- [ ] Engine test suite (SPEC-0008) passes against the IM target's linkage with zero diff.

## Test plan

To be detailed at approval time. Expected shape:

- Reuse the SPEC-0008 corpus and tests (engine layer).
- Manual integration smoke list for IM-specific behaviour: input source registration, switch via Cmd-Space input picker, deactivate / reactivate, deinstall cleanup, secure-input compatibility.

## Implementation notes

To be detailed at approval time. Expected shape:

- Reuse `NAKL/Engine/` unchanged. Promote it to a small static library or framework target if both `NAKL` and `NAKL-IM` link it.
- Preferences may stay in the `NAKL` menu-bar app; the IM target reads the same `NSUserDefaults` (a shared suite name to be decided).
- Excluded-apps logic does NOT translate to IMK; the user simply does not select NAKL when typing in those apps. Drop the feature in the IM target unless a clear need surfaces.
- Hotkey toggle (`AppData.toggleCombo`) maps onto the input-source-switch mechanism in IMK; review whether a custom hotkey is still needed.

## Open questions (resolve before approval)

- Does the menu-bar `NAKL.app` survive after the IM ships? Options: retire it, keep it as a Preferences host, ship both. Each implies different installer semantics.
- One Xcode project with two targets, or two projects? Recommend one project with a shared Engine target.
- IMK does not surface raw key codes the same way CGEventTap does. Audit `AppDelegate.KeyHandler`'s separator / control logic to see what survives the boundary.
- Code signing for IMs is stricter; does this require a real Developer ID? Likely yes for any deployment beyond personal use, which couples this spec to SPEC-0010.

## Changelog

- 2026-04-27: drafted at status `draft`. Execution gated on SPEC-0008 completion and a fresh re-evaluation of ADR-0001.
