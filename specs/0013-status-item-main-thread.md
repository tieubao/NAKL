# SPEC-0013: Status-item main-thread dispatch

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0002
**Blocks:** none

## Problem

`KeyHandler` (`NAKL/AppDelegate.m`) is a `CGEventTap` callback registered via `performSelectorInBackground:@selector(eventLoop)`. It runs on the event-tap's secondary thread for every keystroke system-wide. On the toggle-method and switch-method hotkey paths it currently calls `[appDelegate updateCheckedItem]` (which mutates `NSMenuItem.state`) and `[appDelegate updateStatusItem]` (which mutates `NSStatusItem.button.image`) **synchronously on that background thread**.

Modern AppKit (deployment target macOS 12.0 per SPEC-0002) logs this at runtime:

```
Setting NSStatusItem property on background thread. This is unsupported and may
crash your application. NSStatusItem properties should only be read/written on
the main thread.
```

Apple has stated this *will* crash in a future release. The footgun was even called out in `CLAUDE.md` ("if you add anything that mutates AppKit state, hop to the main queue") but the call sites pre-date that note.

## Goal

All AppKit mutations triggered from inside `KeyHandler` happen on the main queue, with no perceptible typing latency regression.

## Non-goals

- Reworking the event-tap architecture or the hot-path data flow.
- Moving `[NSWorkspace sharedWorkspace].frontmostApplication.bundleIdentifier` (`AppDelegate.m:113`) off the event-tap thread. `NSRunningApplication` is documented thread-safe; the call stays. The kernel's `task_for_pid` denial log (`Unable to obtain a task name port right for pid N`) is unrelated kernel noise and is explicitly out of scope.
- Investigating the one-shot `_NSDetectedLayoutRecursion` warning. That requires a stack capture via Xcode symbolic breakpoint and is deferred until reproducible.
- Migrating from `dispatch_async` to a more elaborate scheduler (NSOperationQueue, async/await). Plain GCD is correct and minimal.

## Acceptance criteria

Each independently verifiable.

- [ ] **Source.** Every AppKit-mutating call inside `KeyHandler` (`NAKL/AppDelegate.m`) is wrapped in `dispatch_async(dispatch_get_main_queue(), ^{ ... })`. Verified by:
      ```sh
      grep -nE "updateCheckedItem|updateStatusItem" NAKL/AppDelegate.m
      ```
      Every occurrence inside the `KeyHandler` function (lines 106-261 today) appears inside a `dispatch_async(dispatch_get_main_queue()` block.

- [ ] **Build.** `xcodebuild -project NAKL.xcodeproj -configuration Debug build` exits 0. No new compiler warnings sourced from `NAKL/AppDelegate.m`:
      ```sh
      xcodebuild -project NAKL.xcodeproj -configuration Debug build 2>&1 \
        | grep -E "AppDelegate\.m.*warning:"
      ```
      returns empty.

- [ ] **Manual smoke (no log).** Launch `build/Debug/NAKL.app`. Open Console.app, filter by process `NAKL`. Trigger the toggle hotkey 5x and the switch-method hotkey 5x. Console must show **zero** new lines containing `Setting NSStatusItem property on background thread`.

- [ ] **Manual smoke (status item still works).** Same session: the menu-bar icon visibly changes between `StatusBarVI` and `StatusBarEN` on each toggle, and the menu's checked state matches the active method when the menu is opened.

- [ ] **Regression (typing).** With method set to VNI: type one paragraph of test text (e.g. `nguoi vie65t` etc) into TextEdit. Vietnamese composition still produces correct output; no perceptible lag versus pre-change behaviour.

## Test plan

Build:

```sh
xcodebuild -project NAKL.xcodeproj -configuration Debug build
```

Source check:

```sh
grep -nE "updateCheckedItem|updateStatusItem" NAKL/AppDelegate.m
grep -nE "AppDelegate\.m.*warning:" <(xcodebuild -project NAKL.xcodeproj -configuration Debug build 2>&1)
```

Manual smoke checklist:

1. Quit any running NAKL: `killall NAKL || true`
2. `open build/Debug/NAKL.app`
3. Grant Accessibility permission if prompted (one-time, persistent).
4. Open Console.app; in the search field type `NAKL` and `Setting NSStatusItem`.
5. Press toggle hotkey 5x. Verify menu-bar icon flips each time.
6. Press switch-method hotkey 5x with method ON. Verify it cycles VNI ↔ Telex.
7. Confirm Console shows no new `Setting NSStatusItem property on background thread` lines from this run.
8. In TextEdit type `nguoi viet64nam` and verify `người việt nam` (or your standard test phrase) renders correctly with no perceptible delay.

## Implementation notes

- Use `dispatch_async`, **not** `dispatch_sync`. The event-tap thread runs the kernel's input pipeline. Blocking it on a main-thread hop would stall keystrokes for the entire user session.
- Capture the `AppDelegate *` from `refcon` into a local before the block; capturing `refcon` (a `void *`) would defer the bridge cast inside the block and make the intent fuzzy.
- The `NSUserDefaults` write at line 168 stays where it is (NSUserDefaults is documented thread-safe).
- Block capture under ARC retains `appDelegate`; this is correct (the AppDelegate singleton outlives any in-flight dispatch).
- Two call-site clusters to wrap: the toggle-method block (around lines 147-161) and the switch-method block (around lines 163-179).

## Open questions

None. The diff is small and the rationale is unambiguous.

## Changelog

- 2026-04-27: drafted and approved
- 2026-04-27: implemented as specified, no amendments. Both call-site clusters in `KeyHandler` (toggle path around `AppDelegate.m:155-159`, switch-method path around `AppDelegate.m:172-176`) wrapped in `dispatch_async(dispatch_get_main_queue(), ^{...})` with the `AppDelegate *` captured into a local before the block. Verified: source grep confirms both occurrences are inside dispatch blocks; `xcodebuild ... build` exits 0 with zero warnings sourced from `AppDelegate.m`. Manual Console smoke for the "no NSStatusItem warning" criterion is the user's to run on next launch.
