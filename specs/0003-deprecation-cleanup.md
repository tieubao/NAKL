# SPEC-0003: Deprecation cleanup in app sources

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0002
**Blocks:** SPEC-0004

## Problem

Building against the macOS 12 SDK (per SPEC-0002) surfaces deprecation warnings for APIs that were superseded between macOS 10.7 and 10.10. Two paths in `AppDelegate.m` exist purely as fallbacks for macOS 10.5 to 10.6 and are now dead: the entire `frontmostAppApiCompatible` branch, and the `AXAPIEnabled()` else-branch. `ExcludedAppsTableViewController` uses three separate deprecated `NSOpenPanel` APIs.

## Goal

Remove every macOS-version fallback that targets a version below the new floor (12.0), and replace each deprecated API call in app-target sources with its modern equivalent.

## Non-goals

- ARC migration. SPEC-0004.
- Touching `ShortcutRecorder/` or `HotKey/`. They warn but still function; decision deferred.
- Behavioural changes. The user-visible behaviour must be byte-identical before and after this spec.

## Acceptance criteria

- [ ] `AppDelegate.m` no longer references `frontmostAppApiCompatible`, `NSAppKitVersionNumber10_7`, or `AXAPIEnabled`.
- [ ] `AppDelegate.m` calls only `[NSWorkspace sharedWorkspace].frontmostApplication` for active-app lookup (not `activeApplication`).
- [ ] `AppDelegate.m` calls only `AXIsProcessTrustedWithOptions(...)` for accessibility check.
- [ ] `ExcludedAppsTableViewController.m` uses `NSModalResponseOK` (not `NSOKButton`).
- [ ] `ExcludedAppsTableViewController.m` uses `setDirectoryURL:` and `URLs` (not `setDirectory:` and `filenames`).
- [ ] `ExcludedAppsTableViewController.m` reads bundle metadata via `[NSBundle bundleWithURL:]` (not path concatenation + `dictionaryWithContentsOfFile:`).
- [ ] `xcodebuild ... build 2>&1 | grep -E "NAKL/(AppDelegate|ExcludedAppsTableViewController)\.m.*deprecated"` returns 0 lines.
- [ ] Manual smoke checklist (below) passes.

## Test plan

```bash
xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Release build 2>&1 | tee /tmp/nakl-build.log

# Zero deprecations in our two files
! grep -E "NAKL/(AppDelegate|ExcludedAppsTableViewController)\.m.*deprecated" /tmp/nakl-build.log
```

Manual smoke checklist:

1. Launch NAKL. Menu bar shows EN icon.
2. Switch to Telex. Type `tieengs vieet` in TextEdit; output is `tiếng việt`.
3. Open Preferences → Excluded Apps → Add. Pick Safari.app. Safari appears in the list.
4. Type `tieengs` in Safari address bar; output is raw `tieengs`.
5. Remove Safari from the excluded list. Repeat step 4; output is `tiếng`.
6. Recorded toggle hotkey still flips method; recorded switch hotkey still cycles VNI ↔ Telex.

## Implementation notes

| File | Lines (current) | Edit |
|---|---|---|
| `AppDelegate.m` | 40 | Delete `static bool frontmostAppApiCompatible = false;`. |
| `AppDelegate.m` | 51-53 | Delete the entire `if (floor(NSAppKitVersionNumber) >= NSAppKitVersionNumber10_7) { ... }` block. |
| `AppDelegate.m` | 55-62 | Collapse to a single line: `BOOL accessibilityEnabled = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)@{(id)kAXTrustedCheckOptionPrompt: @NO});`. |
| `AppDelegate.m` | 137-145 | Replace the `if (frontmostAppApiCompatible) { ... } else { ... }` block with `NSString *activeAppBundleId = [NSWorkspace sharedWorkspace].frontmostApplication.bundleIdentifier;`. |
| `ExcludedAppsTableViewController.m` | 49 | `[dialog setDirectoryURL:[NSURL fileURLWithPath:@"/Applications"]];` |
| `ExcludedAppsTableViewController.m` | 51 | `if ([dialog runModal] == NSModalResponseOK) {` |
| `ExcludedAppsTableViewController.m` | 53-64 | Iterate `[dialog URLs]`. For each `NSURL *appURL`: `NSBundle *b = [NSBundle bundleWithURL:appURL]; NSString *bid = b.bundleIdentifier; NSString *name = b.infoDictionary[(NSString*)kCFBundleNameKey] ?: appURL.URLByDeletingPathExtension.lastPathComponent;` |

- The `(__bridge CFDictionaryRef)` cast is correct under both MRC (no-op) and ARC (zero-cost). It survives SPEC-0004.
- Keep `scripts/EnableAssistiveDevices.applescript` untouched.

## Open questions

- The AppleScript references "MacOS 10.9" in its dialog text. Cosmetic and out of scope here.

## Changelog

- 2026-04-27: drafted and approved
