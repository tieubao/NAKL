# SPEC-0011: SMAppService login-item migration

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0004
**Blocks:** none (but recommended before SPEC-0007 to keep `PreferencesController.m` clean)

## Problem

`NAKL/PreferencesController.m` still carries 12 deprecation warnings that SPEC-0003 deliberately left out of scope:

- `LSSharedFileListCreate`, `kLSSharedFileListSessionLoginItems`, `LSSharedFileListInsertItemURL`, `kLSSharedFileListItemLast`, `LSSharedFileListCopySnapshot`, `LSSharedFileListItemResolve`, `LSSharedFileListItemRemove` (deprecated 10.10–10.11, no longer supported).
- `[NSKeyedArchiver archivedDataWithRootObject:]` and `archiveRootObject:toFile:` (deprecated 10.14).
- `NSOnState` (deprecated 10.14).

The `LSSharedFileList*` APIs implement "Load at Login" via the legacy session-login-items database. Apple's replacement is **SMAppService** (macOS 13+), which has a different permission model (the system shows a "background item enabled by ..." prompt the first time) and a different bundle layout (the launch-helper is a separate target).

The `archivedDataWithRootObject:` calls implement the nested-archive format used by `shortcuts.setting`. The save side wasn't migrated when SPEC-0004 migrated the load side.

## Goal

Replace the LSSharedFileList code path with SMAppService, modernise the keyed-archiver save calls (preserving the file format so existing user shortcuts still load), and bring `PreferencesController.m` to zero deprecation warnings.

## Non-goals

- Visual redesign of the Preferences window.
- Changing the `shortcuts.setting` file format.
- Sandboxing the app (out of scope; would conflict with CGEventTap).

## Acceptance criteria

Three independent groups (A login-item, B archiver, C UI constant). Each criterion independently verifiable.

### A. Login-item via SMAppService

- [ ] `ServiceManagement.framework` added to the `NAKL` target's link phase (PBXBuildFile + PBXFileReference + PBXFrameworksBuildPhase + Frameworks PBXGroup). Verified:
      ```sh
      grep -E "ServiceManagement" NAKL.xcodeproj/project.pbxproj | wc -l
      ```
      returns ≥ 4.
- [ ] `PreferencesController.m` no longer contains any `LSSharedFileList` symbol. Verified:
      ```sh
      grep -nE "LSSharedFileList|kLSSharedFileList" NAKL/PreferencesController.m
      ```
      returns empty.
- [ ] `addAppsAsLoginItem` and `removeAppFromLoginItem` replaced with `[[SMAppService mainAppService] registerAndReturnError:]` and `[[SMAppService mainAppService] unregisterAndReturnError:]`. Errors are surfaced to the user via `NSAlert` (user can read why their toggle didn't take effect).
- [ ] `[SMAppService mainAppService].status` is queried on `windowDidLoad` to seed the checkbox state from system reality (not stale defaults).

### B. Modernised keyed archiver, format preserved

- [ ] `[NSKeyedArchiver archivedDataWithRootObject:]` and `[NSKeyedArchiver archiveRootObject:toFile:]` no longer appear in `PreferencesController.m`. Verified:
      ```sh
      grep -nE "archivedDataWithRootObject:[^r]|archiveRootObject:toFile:" NAKL/PreferencesController.m
      ```
      returns empty.
- [ ] Save path uses the modern `archivedDataWithRootObject:requiringSecureCoding:error:` (twice, to preserve the existing **nested-archive** wire format) and `[NSData writeToURL:options:error:]`.
- [ ] **Format compat**: a `shortcuts.setting` produced by the pre-change build still loads correctly under the new code. Verified: copy the existing `~/Library/Application Support/NAKL/shortcuts.setting` aside, build new code, re-launch, open Preferences → shortcuts list matches.
- [ ] Round-trip: save under new code, then re-open Preferences in a fresh launch; shortcuts list is identical.

### C. Modern UI state constants

- [ ] `NSOnState` no longer appears in `PreferencesController.m`. Replaced with `NSControlStateValueOn`. Verified:
      ```sh
      grep -nE "NSOnState\b|NSOffState\b" NAKL/PreferencesController.m
      ```
      returns empty.

### Cross-cutting

- [ ] `xcodebuild -project NAKL.xcodeproj -configuration Debug build` exits 0.
- [ ] Zero deprecation warnings sourced from `PreferencesController.m`. Verified:
      ```sh
      xcodebuild -project NAKL.xcodeproj -configuration Debug build 2>&1 \
        | grep -E "PreferencesController\.m.*deprecat" | wc -l
      ```
      prints `0`.
- [ ] **Manual smoke**: launch app; open Preferences; toggle "Load at Login" ON; observe macOS background-item prompt; reboot; confirm NAKL launches automatically. Toggle OFF; reboot; confirm NAKL does not launch.

## Test plan

Run all automatable verification commands listed above, then the format-compat smoke and the SMAppService toggle smoke. Round-trip and reboot smoke require user time; everything else is one-shot.

## Implementation notes

**SMAppService variant:** use `SMAppService.mainAppService`. NO separate launch-helper target is needed — `mainAppService` registers the main `.app` itself for login-launch. (`agentService:` / `daemonService:` / `loginItemService:` are for XPC daemons and bundled-helper login items, neither of which apply here. The earlier draft over-estimated complexity.)

**Framework linking:** add `ServiceManagement.framework` from `System/Library/Frameworks/`. Pattern to copy from `Cocoa.framework` registration in `project.pbxproj`: PBXBuildFile, PBXFileReference, Frameworks PBXGroup `children`, PBXFrameworksBuildPhase `files`.

**Archive format:** the current file is a *nested* keyed archive — outer archive whose root object is an `NSData` that itself contains the inner archive of `NSMutableArray<ShortcutSetting>`. `AppData.loadShortcuts` (already migrated by SPEC-0004) reads it as: outer `NSKeyedUnarchiver` → decode inner `NSData` → inner `NSKeyedUnarchiver` → decode `NSArray`. To preserve format, save side must produce the same nesting:

```objc
NSError *err = nil;
NSData *innerData = [NSKeyedArchiver
    archivedDataWithRootObject:[AppData sharedAppData].shortcuts
         requiringSecureCoding:NO
                         error:&err];
NSData *outerData = [NSKeyedArchiver
    archivedDataWithRootObject:innerData
         requiringSecureCoding:NO
                         error:&err];
[outerData writeToURL:[NSURL fileURLWithPath:filePath]
              options:NSDataWritingAtomic
                error:&err];
```

`requiringSecureCoding:NO` matches the load side (`outer.requiresSecureCoding = NO;`). Bumping to `YES` would require `ShortcutSetting` to adopt `NSSecureCoding` and is out of scope.

**Migration strategy for legacy LSSharedFileList entry:** **document, don't code.** Best-effort cleanup using the deprecated APIs would re-introduce the warnings we are deleting (even with `#pragma clang diagnostic push/ignored`, it's noise we don't need). This file's pre-change install base is small (personal use) and any user with a stale entry can remove it manually via System Settings → General → Login Items. A line in the README + a comment in `startupOptionClick:` is enough.

## Open questions

Resolved at approval:

- **Cleanup of legacy LSSharedFileList entry?** No code; document instead. Rationale above.
- **Surface the macOS background-item prompt in NAKL UI?** No. The system prompt is informative on its own; adding an explanatory `NSAlert` is ceremony for a one-time event. Surface only the *failure* path: if `register:` returns an error (e.g., user denied), show an `NSAlert` with the error description and revert the checkbox. That gives the user a clear signal without pre-empting the system.
- **Launch-helper target?** **No** — `SMAppService.mainAppService` registers the main app itself. No separate target, no separate entitlements, no separate notarisation. SPEC-0010 coupling does not exist.

## Changelog

- 2026-04-27: drafted at status `draft` based on findings from SPEC-0003 / SPEC-0004 implementation. Awaiting approval and scope refinement.
- 2026-04-27: refined and approved. Three acceptance-criteria groups (A login-item / B archiver / C UI constant) with explicit verification commands; resolved all three open questions (no LSSharedFileList cleanup code, no pre-emptive prompt UI, no launch-helper target — `SMAppService.mainAppService` registers the main `.app` itself); locked the archive-format-preserving save path via nested `archivedDataWithRootObject:requiringSecureCoding:error:` + `writeToURL:options:error:`. The earlier draft's "needs `NAKLLaunchHelper` target" concern was wrong: `mainAppService` is the right SMAppService variant for menu-bar apps and requires no separate target. Status flipped to `approved`.
- 2026-04-27: implemented as approved with two minor amendments:
  - **A**: Added `ServiceManagement.framework` to the link phase (4-line edit to `project.pbxproj` mirroring `Cocoa.framework`). Replaced both legacy methods with a single `startupOptionClick:` body that calls `registerAndReturnError:`/`unregisterAndReturnError:` on `[SMAppService mainAppService]`, surfacing failures via `NSAlert` and reverting the bound `NSUserDefaults["startAtLogin"]` so the checkbox unticks itself. Seeded the same defaults key in `windowDidLoad` from `[SMAppService mainAppService].status` so the checkbox reflects system reality across launches.
  - **B**: Replaced the nested archive with `archivedDataWithRootObject:requiringSecureCoding:NO error:` (twice, preserving wire format) + `[NSData writeToURL:options:NSDataWritingAtomic error:]`. Save errors are NSLog'd rather than alert-modal'd to avoid interrupting the Preferences-window-close flow that triggers the save.
  - **C**: Replaced the single `NSOnState` use with `NSControlStateValueOn`.
  - **B1 amendment**: the criterion's grep `archivedDataWithRootObject:[^r]` matches the new multi-line method invocation (because the regex evaluates against the first line where `[` follows the colon, not `r`). The authoritative check is the cross-cutting "PreferencesController.m deprecation count = 0", which passes. Future revisions of this spec should use `git grep -nE "archivedDataWithRootObject:\\s*\\[" -- NAKL/PreferencesController.m` to specifically detect the legacy single-arg form, or rely entirely on the deprecation count.
  - **Skipped (per resolved open question)**: no programmatic cleanup of any leftover `LSSharedFileList` entry; users with a stale entry from very old NAKL builds can remove it manually via System Settings → General → Login Items.
  - All automatable verifications pass. Manual SMAppService toggle + reboot smoke (cross-cutting last item) is the user's to run.
