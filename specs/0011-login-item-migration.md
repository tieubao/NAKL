# SPEC-0011: SMAppService login-item migration

**Status:** draft
**Owner:** @tieubao
**Depends on:** SPEC-0004
**Blocks:** none (but recommended before SPEC-0007 to keep `PreferencesController.m` clean)

> ⚠️ Drafted from follow-up findings during SPEC-0003 / SPEC-0004 implementation. Not approved; needs scope refinement before execution.

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

## Acceptance criteria (starter, needs refinement at approval time)

- [ ] All `LSSharedFileList*` references removed from `NAKL/PreferencesController.m`.
- [ ] "Load at Login" toggles via `[SMAppService mainAppService] register:` / `unregister:`.
- [ ] First-time toggle surfaces the macOS background-item prompt to the user.
- [ ] `archivedDataWithRootObject:` replaced with `archivedDataWithRootObject:requiringSecureCoding:error:`; resulting `NSData` written via `[data writeToURL:options:error:]`.
- [ ] `archiveRootObject:toFile:` removed.
- [ ] `NSOnState` replaced with `NSControlStateValueOn`.
- [ ] `shortcuts.setting` produced by the previous version still loads correctly under the new code (regression test with a fixture file).
- [ ] `xcodebuild ... build 2>&1 | grep "PreferencesController.m.*deprecated"` returns 0 lines.
- [ ] Manual smoke: toggle Load-at-Login on/off; observe macOS prompt; reboot; confirm app starts (or doesn't) per setting.

## Test plan

To be detailed at approval time. Likely includes:

- Unit test (after SPEC-0008 lands): round-trip `ShortcutSetting` archive → unarchive yields identical content.
- Manual smoke: SMAppService toggle + reboot.
- Format-compat smoke: place an old-format `shortcuts.setting` in `~/Library/Application Support/NAKL/`, launch new build, confirm shortcuts appear.

## Implementation notes

To be detailed at approval time. Sketch:

- New target: `NAKLLaunchHelper` (`com.zepvn.NAKL.LaunchHelper`) per SMAppService's bundle requirements. The helper is what `SMAppService.mainAppService` registers.
- Migration: on first launch under the new code, detect a leftover `LSSharedFileList` entry (best effort) and clean it up; otherwise the user sees the app autostart twice (once from the legacy entry, once from SMAppService) until they remove the legacy entry manually.
- `NSKeyedUnarchiver initForReadingFromData:` (already used in `AppData.loadShortcuts` after SPEC-0004) is the symmetric load-side; the save path needs `archivedDataWithRootObject:requiringSecureCoding:error:`.

## Open questions (resolve before approval)

- Migration strategy for users with the old LSSharedFileList registration: best-effort cleanup, or just document that the old entry should be removed manually?
- SMAppService prompts the user for permission when first registered. Do we surface this in NAKL's UI (e.g., explain "macOS will ask you to allow background launch")?
- Does the launch-helper target need its own entitlements file, codesign identity, and notarisation flow? Probably yes; this couples slightly to SPEC-0010.

## Changelog

- 2026-04-27: drafted at status `draft` based on findings from SPEC-0003 / SPEC-0004 implementation. Awaiting approval and scope refinement.
