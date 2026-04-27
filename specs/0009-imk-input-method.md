# SPEC-0009: InputMethodKit input method (deferred draft, refined)

**Status:** draft (execution-ready; awaits user go-ahead per ADR-0001)
**Owner:** @tieubao
**Depends on:** SPEC-0007, SPEC-0008, SPEC-0010 (signing)
**Blocks:** none

> ⚠️ Status remains `draft` because the **execute/no-execute decision is yours per ADR-0001**. This refinement locks all open questions and proposes a phased execution plan so the spec is implementation-ready when you approve. ADR-0001's reopen evaluation is appended at the bottom of this spec.

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

## Acceptance criteria

Grouped by phase (see § Phasing). Each criterion independently verifiable.

### A. Bundle scaffold (Phase 9.1)

- [ ] New target `NAKL-IM` produces a `.app` bundle whose `Info.plist` contains:
  - `LSBackgroundOnly = YES`
  - `LSUIElement = YES`
  - `InputMethodConnectionName = vn.huyphan.NAKL_Connection`
  - `InputMethodServerControllerClass = NAKLInputController`
  - `InputMethodServerDelegateClass = NAKLInputController` (same class doubles as connection delegate)
  - `tsInputMethodIconFileKey = StatusBarVI.tiff` (or asset-catalog reference if Xcode honours `Assets.car` lookups for input methods on macOS 12+; verify at scaffold time)
  - `tsInputMethodCharacterRepertoireKey = ("vi")`
  - `CFBundleIdentifier = com.zepvn.NAKL.InputMethod`
  - `MACOSX_DEPLOYMENT_TARGET = 12.0`
- [ ] Bundle installs via `cp -R NAKL-IM.app ~/Library/Input\ Methods/` and appears in System Settings → Keyboard → Input Sources → Add → Vietnamese (after a session restart or `killall -HUP TextInputMenuAgent`).
- [ ] No Accessibility / Input Monitoring prompt during install or first activation.

### B. Engine integration (Phase 9.2)

- [ ] `NAKLInputController : IMKInputController` is the principal class.
- [ ] `inputText:client:` translates each input keystroke to a `nakl_engine_add_key` call.
- [ ] On engine replay (`n > 0`): replay via `[client insertText:withReplacementRange:]`. The leading-`\b` characters in the engine's replay buffer become a `replacementRange.length = kbPLength` against the inserted text (the modern equivalent of the CGEventTap backspace dance).
- [ ] On pass-through (`n == 0`): return `NO` so the system inserts the original keystroke verbatim.
- [ ] Selecting NAKL and typing `tieengs vieet` in TextEdit produces `tiếng việt`.
- [ ] Same in a Secure-Input password field (the differentiator vs CGEventTap).
- [ ] SPEC-0008 corpus runs against `NAKL-IM` engine linkage with zero diff (i.e. the IM target compiles `nakl_engine.c` from the same source path; the test target already links it; verify the test target's snapshot matches an equivalent corpus run via the IM target).

### C. Preferences sharing (Phase 9.3)

- [ ] `NAKL.app` (menu-bar Preferences host) and `NAKL-IM.app` share `NSUserDefaults` via the shared suite name `vn.huyphan.NAKL.shared` (or App Group equivalent if both targets are sandboxed in the future).
- [ ] Method, hotkey, shortcuts, and excluded-apps state read by both targets without duplication.
- [ ] Per-user shortcut additions in NAKL Preferences take effect in the next IMK keystroke without a re-launch.

### D. UX migration (Phase 9.4)

- [ ] Documentation: `docs/imk-migration.md` explains the install flow, how to switch input sources, and how to uninstall.
- [ ] `scripts/install-im.sh` copies the IM bundle into `~/Library/Input Methods/` and signals the input-method server to refresh.
- [ ] `scripts/uninstall-im.sh` removes it cleanly.
- [ ] Decision recorded for the menu-bar `NAKL.app` post-IM era (see resolved open questions below).

## Test plan

```bash
# A. Scaffold
xcodebuild -project NAKL.xcodeproj -scheme NAKL-IM -configuration Release build
ls build/Release/NAKL-IM.app/Contents/Info.plist
plutil -lint build/Release/NAKL-IM.app/Contents/Info.plist
scripts/install-im.sh build/Release/NAKL-IM.app
killall -HUP TextInputMenuAgent
# Then: System Settings → Keyboard → Input Sources → Add → Vietnamese → "NAKL"

# B. Engine integration (manual smoke required; the system has to route keys)
#   1. Pick NAKL from the input-source picker.
#   2. In TextEdit type: tieengs vieet  → tiếng việt
#   3. In a Safari password field type the same → tiếng việt (proves Secure Input)
#   4. Switch to ABC, type "tieengs" → tieengs (proves IM is bypassed)

# C. Preferences sharing
#   Open NAKL.app, Preferences. Add a shortcut: dwf → Dwarves Foundation.
#   Switch to TextEdit; with NAKL IM active, type "dwf<space><space>" →
#   Dwarves Foundation.

# D. Engine corpus regression (automated)
xcodebuild test -project NAKL.xcodeproj -scheme NAKL \
    -destination 'platform=macOS' -only-testing:NAKLEngineTests
# 100% pass (the IM target shares the engine source; no behavioural drift).
```

## Implementation notes

### Layout

- One Xcode project, three targets: `NAKL` (menu-bar Preferences host, retained), `NAKL-IM` (new IMK bundle), `NAKLEngineTests` (existing). Engine sources (`NAKL/Engine/nakl_engine.{c,h}`) compiled directly into both `NAKL` and `NAKL-IM`. No shared static library yet; if binary size becomes a concern, promote to `Engine.framework` in a follow-up.

### Engine reuse

`NAKL-IM` adds `nakl_engine.c` to its own Sources build phase (no edit to the engine itself). Header search path includes `$(SRCROOT)/NAKL/Engine`. The wrapper bridge for the shortcut callback lives in the IM target as a small Obj-C++ helper, mirroring `KeyboardHandler.m`'s pattern but reading the shared `NSUserDefaults` instead of the host's `AppData` singleton.

### Replay translation

CGEventTap replay was: post N backspace events, then post M Unicode events. IMK equivalent: build an `NSString *replacement` from the engine's `[\b * kbPLength][replacement * kbBLength]` buffer (the `\b` chars are *implied* by `replacementRange.length = kbPLength`; only the non-`\b` portion goes into the inserted string). The IM target's `inputText:client:` therefore:

```objc
- (BOOL)inputText:(NSString *)string client:(id)sender {
    if (string.length != 1) return NO;        // ignore IME composition
    UniChar key = [string characterAtIndex:0];
    UniChar buf[2 * NAKL_WORD_SIZE];
    int n = nakl_engine_add_key(_engine, key, buf, sizeof(buf)/sizeof(*buf));
    if (n <= 0) return NO;                    // pass-through

    // Split [\b * p][chars * b] from the replay buffer.
    int p = 0; while (p < n && buf[p] == '\b') p++;
    int b = n - p;
    NSString *replacement = [NSString stringWithCharacters:buf+p length:b];
    NSRange r = NSMakeRange(NSNotFound, p); // delete `p` chars before insertion point
    [sender insertText:replacement replacementRange:r];
    return YES;
}
```

### Hotkey + excluded-apps + status bar

- **Excluded apps**: drop in `NAKL-IM`. The user picks the input source per app via macOS; an explicit allowlist is redundant and IMK has no hook to gate by bundle identifier.
- **Toggle / switch hotkeys**: drop in `NAKL-IM`. macOS already provides Caps Lock and the input-source switch chord; reproducing custom Carbon-hotkey handling inside IMK is fragile.
- **Status item**: keep in the menu-bar `NAKL.app` for its Preferences-launcher role; the live On/VNI/Telex toggle becomes a redundant indicator once IMK is selected — show it but don't make it authoritative.

### Code signing

`~/Library/Input Methods/` accepts ad-hoc-signed bundles for personal install, but distribution (via DMG, GitHub release, etc.) requires Developer ID per Apple's IM bundle requirements. SPEC-0010 (now `approved` and scaffolded) provides the signing pipeline. Couple this spec to SPEC-0010 only when shipping; personal-use development can use ad-hoc signing.

## Open questions

Resolved at refinement:

- **Does menu-bar `NAKL.app` survive after the IM ships?**
  **Yes — as the Preferences host and shortcut editor.** The IM bundle has no UI surface for hotkey configuration, shortcut editing, or excluded-apps management. `NAKL.app` continues to own those screens; `NAKL-IM` reads the same `NSUserDefaults` suite. The CGEventTap pipeline inside `NAKL.app` becomes dormant when the user switches to IM mode (toggle the menu to "Off" and the existing event-tap returns events unmodified). A follow-up spec can decide whether to retire the CGEventTap path entirely once IM has been on personal-use long enough to confirm parity.

- **One Xcode project with two targets, or two projects?**
  **One project, three targets** (NAKL, NAKL-IM, NAKLEngineTests). Shared engine sources compiled into both runtime targets. No shared static library / framework until size or build-time pressure motivates it.

- **Audit of `AppDelegate.KeyHandler` boundary survival.**
  Surviving: per-keystroke engine call, the `[\b][replacement]` buffer protocol, the SPEC-0007 shortcut-callback bridge.
  Not surviving: `CGEventTapPostEvent` re-injection (replaced by `[sender insertText:replacementRange:]`), the `NAKL_MAGIC_NUMBER` re-entry guard (no longer needed; IMK doesn't re-route inserted text back to us), separator detection (still needed but moves into `inputText:client:`), control-key gate via `controlKeys` flag mask (the system delivers a key string, not raw flags; we lose the ability to detect "user pressed Cmd+something" exactly the same way — survey at Phase 9.2 to see if `[sender attributedSubstringFromRange:]` or `[sender markedRange]` give us enough to reconstruct).

- **Code signing.** Personal-use ad-hoc signing works. Distribution requires Developer ID and notarisation per SPEC-0010. Couple at distribution time, not at scaffold time.

## Phasing

Recommended execution order. Each phase is small enough to ship as one feat commit; failures don't strand the codebase.

| Phase | Scope | Effort estimate |
|---|---|---|
| **9.1 Scaffold** | New `NAKL-IM` target. Stub `NAKLInputController` that just logs every keystroke. Install via script. Confirm appearance in input picker. | 1 session |
| **9.2 Engine integration** | Wire `inputText:client:` → engine. Replay via `insertText:withReplacementRange:`. Manual smoke + SPEC-0008 corpus parity. | 1-2 sessions |
| **9.3 Preferences sharing** | Shared `NSUserDefaults` suite. Method / shortcuts / hotkeys readable from both targets. | 1 session |
| **9.4 UX migration** | install/uninstall scripts; documentation; decision on menu-bar app retirement. | 1 session |

Total: 4-5 sessions of focused work, gated on user approval to start.

## ADR-0001 reopen evaluation (as of 2026-04-27)

ADR-0001 says this spec should be revisited when any of three reopen criteria fire:

| Criterion | Status |
|---|---|
| Apple announces deprecation or breaking change to `CGEventTap` for keyboard events on a future macOS version. | **Not triggered.** No Apple announcement; CGEventTap continues to work on macOS 14/15/16 dev seeds as of session date. |
| User decides to share NAKL publicly or submit to the App Store. | **Partially triggered.** SPEC-0010 (notarisation pipeline) just scaffolded, which preps for distribution; whether you actually intend to share is your call. |
| Phase 6 (engine extraction) reveals it is significantly cheaper than estimated, making the marginal cost of also doing phase 7 small enough to justify pulling it forward. | **Triggered.** SPEC-0007 shipped in one session (~1 day equivalent), well below the ADR-implied multi-day estimate. The marginal IMK cost shrinks from "2-4 weeks" (ADR option B) to roughly 4-5 sessions (this spec's phasing) since the engine and tests are already in hand. |

Two of three reopen criteria are at least partially active; the decision is yours, but the door is open. If you decide to execute, this spec's Phase 9.1 is the entry point.

## Related specs / follow-ups

- **SPEC-0010** (notarisation) — required for distribution of the IM bundle. Already approved and scaffolded.
- A **future SPEC-0014** (or similar) should retire the CGEventTap event loop in `NAKL.app` once `NAKL-IM` has shipped and the user has confirmed parity for at least a quarter. Until then, the menu-bar app's KeyHandler stays in tree as a fallback.

## Changelog

- 2026-04-27: drafted at status `draft`. Execution gated on SPEC-0008 completion and a fresh re-evaluation of ADR-0001.
- 2026-04-27: refined post-SPEC-0008. All four open questions resolved (menu-bar app survives as Preferences host; one project / three targets; CGEventTap-boundary survival audit; ad-hoc sign for personal use, Developer ID for distribution). Acceptance criteria split into four phase groups (A scaffold / B engine integration / C preferences sharing / D UX migration). Phasing table proposes 4-5 sessions of focused work. ADR-0001 reopen evaluation appended: 2 of 3 criteria are at least partially active, but the execute decision remains the user's. Status stays `draft` because that decision has not been made.
