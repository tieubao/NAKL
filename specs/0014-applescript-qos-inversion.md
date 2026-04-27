# SPEC-0014: Replace launch-time AppleScript with native Cocoa AX prompt

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0012
**Blocks:** none

## Problem

`+[AppDelegate initialize]` (`NAKL/AppDelegate.m:43-70`) runs on the main thread (Obj-C runtime contract). When Accessibility permission is missing, it synchronously executes `scripts/EnableAssistiveDevices.applescript` via `[NSAppleScript executeAndReturnError:]` at line 63. The OSA call blocks the main thread (User-Interactive QoS) on an AppleEvent roundtrip into the `System Events` helper, which runs at Default QoS. Xcode's QoS Inversion Detection logs:

```
[Internal] Thread running at User-interactive quality-of-service class
waiting on a lower QoS thread running at Default quality-of-service class.
Investigate ways to avoid priority inversions
```

The macOS scheduler boosts the lower thread to unblock the upper one, but the call site is the bug. The boost only masks it.

The script itself is doing two trivially-Cocoa-replaceable things:

1. Re-check accessibility trust via `System Events` "UI elements enabled". This is redundant: line 50 already does `AXIsProcessTrustedWithOptions(...)`, which is the canonical, sandbox-friendly check. The AppleScript path re-checks the same condition over a slower IPC.
2. On `false`, display a Vietnamese dialog and `do shell script "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"` to open the Accessibility pane.

Both are expressible directly in Cocoa with no OSA, no `System Events` dependency, and no main-thread block. SPEC-0012 already cleaned up the bundle copy of the script; this spec retires the script entirely.

## Goal

Remove the AppleScript-based AX prompt, replacing it with a synchronous-on-main `NSAlert` + `NSWorkspace openURL:` flow that triggers no QoS inversion warning at launch.

## Non-goals

- Replacing `AXIsProcessTrustedWithOptions` itself. It is correct, modern, and stays.
- Auto-granting permission, or relaunching NAKL after the user grants it. Manual quit + relaunch remains the user's responsibility (the existing dialog wording already says so).
- Adding a polling loop that re-checks AX trust periodically. Out of scope.
- Localising the alert further. The existing Vietnamese string is the source of truth and is preserved verbatim.
- Migrating from `+initialize` to `applicationWillFinishLaunching:`. The trust check timing is fine where it is; the spec only changes the *mechanism*, not the *moment*.
- Touching `scripts/EnableAssistiveDevices.scpt` references in `NAKL.xcodeproj` beyond what's needed to drop the resource copy. That bundle cleanup is owned by SPEC-0012's follow-up if needed.

## Acceptance criteria

Each independently verifiable.

- [ ] **Source.** `+[AppDelegate initialize]` no longer references `NSAppleScript`, `pathForResource:@"EnableAssistiveDevices"`, or `executeAndReturnError:`. Verified by:
      ```sh
      grep -nE "NSAppleScript|EnableAssistiveDevices|executeAndReturnError" NAKL/AppDelegate.m
      ```
      returns empty.

- [ ] **Source.** When `AXIsProcessTrustedWithOptions` returns `NO`, the new code path:
      1. Constructs an `NSAlert` with the existing Vietnamese message text (preserved verbatim from `scripts/EnableAssistiveDevices.applescript` lines 12-14).
      2. Runs `[alert runModal]` on the main thread.
      3. Calls `[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"]]`.
      No call into `System Events`, no `do shell script`, no OSA.

- [ ] **Build.** `xcodebuild -project NAKL.xcodeproj -configuration Debug build` exits 0. No new compiler warnings sourced from `NAKL/AppDelegate.m`:
      ```sh
      xcodebuild -project NAKL.xcodeproj -configuration Debug build 2>&1 \
        | grep -E "AppDelegate\.m.*warning:"
      ```
      returns empty.

- [ ] **Manual smoke (permission missing).** With NAKL removed from System Settings → Privacy & Security → Accessibility, launch `build/Debug/NAKL.app`. The new `NSAlert` appears on the main screen, in Vietnamese, identical wording to the prior AppleScript dialog. Dismissing it opens System Settings on the Privacy & Security → Accessibility pane. **Xcode debug console shows zero new lines** containing `priority inversion` or `User-interactive quality-of-service`.

- [ ] **Manual smoke (permission already granted).** With NAKL already in the Accessibility list, launch the app. No alert is shown, no Settings pane opens, no QoS warning appears. Toggle/switch hotkeys work as before.

- [ ] **Bundle.** `scripts/EnableAssistiveDevices.scpt` is no longer copied into `build/Debug/NAKL.app/Contents/Resources/`. Verified by:
      ```sh
      ls build/Debug/NAKL.app/Contents/Resources/EnableAssistiveDevices.scpt 2>&1
      ```
      reports "No such file or directory". The source files in `scripts/` may stay on disk for git history; the Xcode "Copy Files" build phase entry referencing `EnableAssistiveDevices.scpt` is removed.

## Test plan

Build:

```sh
xcodebuild -project NAKL.xcodeproj -configuration Debug build
```

Source check:

```sh
grep -nE "NSAppleScript|EnableAssistiveDevices|executeAndReturnError" NAKL/AppDelegate.m
ls build/Debug/NAKL.app/Contents/Resources/EnableAssistiveDevices.scpt 2>&1
```

Manual smoke (permission-missing path):

1. System Settings → Privacy & Security → Accessibility → remove NAKL (or toggle off).
2. `killall NAKL || true`
3. In Xcode: open the project, ⌘R to run with Diagnostics → QoS Inversion Detection enabled.
4. Confirm the Vietnamese alert appears with the existing copy.
5. Click OK. Confirm System Settings opens on the Accessibility pane.
6. In Xcode's debug console, confirm no `priority inversion` line appears for `AppDelegate.m`.
7. Quit NAKL.

Manual smoke (permission-granted path):

1. Re-tick NAKL in the Accessibility list.
2. Re-run NAKL from Xcode (⌘R).
3. Confirm no alert, no Settings pane, no inversion warning.
4. Press toggle and switch hotkeys 5x each. Type into TextEdit to confirm Vietnamese composition still works.

## Implementation notes

- The Vietnamese string in `scripts/EnableAssistiveDevices.applescript` lines 12-14 is the source of truth for the alert message. Copy it verbatim into a UTF-8 `NSString` literal in `AppDelegate.m`, with `\n\n` between the two paragraphs.
- `NSAlert` defaults are fine: `messageText` = "NAKL", `informativeText` = the Vietnamese paragraph, single OK button. No need for an icon override; `NSAlertStyleInformational` is correct.
- `+initialize` is allowed to block on `runModal`. Modal alert-on-main is **not** a QoS inversion: the alert runs in the main run loop, so there is no cross-QoS thread wait.
- Order matters: present the alert *before* opening the Settings URL, so the user reads the Vietnamese instructions before being yanked into Settings.
- `NSWorkspace openURL:` returns synchronously after dispatching the URL to LaunchServices. Do not wait on its return value beyond the `BOOL` result.
- The `scripts/` directory itself can stay (it's outside the bundle). The Xcode "Copy Files" build phase entry for `EnableAssistiveDevices.scpt` (visible in the project's `PBXCopyFilesBuildPhase` for the `NAKL` target) is what gets removed.
- This spec assumes ARC (per SPEC-0004); no manual `release` calls.

## Open questions

- **Should the alert offer a "Quit & re-launch automatically" button?** Possible, but cross-cuts SPEC-0011 (SMAppService) and would need its own spec. Out of scope here.
- **Bundle ID `com.apple.preference.security` vs `com.apple.settings.PrivacySecurity`?** The legacy URL still works on macOS 12-15 per Apple's compatibility shim. Keep the existing form unless a future macOS removes it; that is a separate spec.

## Changelog

- 2026-04-27: drafted
- 2026-04-27: approved by @tieubao
- 2026-04-27: implemented as specified, no amendments. `+[AppDelegate initialize]` (`NAKL/AppDelegate.m:43-66`) replaces the AppleScript path with an `NSAlert` + `[NSWorkspace openURL:]` flow. Project file no longer references `EnableAssistiveDevices.scpt` for bundle copy (PBXBuildFile, CopyFiles `files` entry, PBXFileReference, and root-group child entry all removed). The `osacompile` `ShellScript` phase and the empty `CopyFiles` phase are intentionally left in place per spec scope. Verified: AC1, AC2, AC3, AC6 pass via grep + `xcodebuild` + bundle inspection. AC4, AC5 are user-driven Xcode smoke tests.
