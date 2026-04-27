# SPEC-0012: Bundle cleanup and EnableAssistiveDevices script modernisation

**Status:** draft
**Owner:** @tieubao
**Depends on:** SPEC-0006
**Blocks:** none

> ⚠️ Drafted from follow-up findings during SPEC-0006 implementation. Three small mechanical cleanups bundled because they share a theme: legacy resources still in the bundle.

## Problem

Three pre-existing minor issues remain after SPEC-0006:

1. **Dead bundle resources.** `NAKL/NAKL.icns`, `NAKL/icon.png`, `NAKL/icon24.png`, and `NAKL/icon_blue_24.png` are still copied into the `.app` bundle (~250 KB) but are no longer read by any code (asset catalog and `[NSImage imageNamed:]` make them obsolete). Removing them requires editing 19 line-groups across `project.pbxproj` (PBXBuildFile, PBXFileReference, PBXGroup, PBXResourcesBuildPhase).
2. **Build-artefact pollution.** The Run Script build phase that compiles `scripts/EnableAssistiveDevices.applescript` writes the resulting `.scpt` into the source tree (`scripts/EnableAssistiveDevices.scpt`), leaving the working tree dirty after every build.
3. **Stale dialog text in the AppleScript.** `scripts/EnableAssistiveDevices.applescript` references `System Preferences` (renamed `System Settings` in macOS 13) and links to a 10.9-era FAQ. The "OK" button's `turnUIScriptingOn` flow is therefore a no-op on macOS 13+; only the dialog message renders. The Vietnamese copy also references "MacOS cũ hơn 10.9" which is no longer relevant.

## Goal

Remove dead resources from the bundle, stop the build phase from polluting the source tree, and update the AppleScript to work on macOS 12+ with current System Settings nomenclature.

## Non-goals

- Redesigning the Accessibility-prompt UX. (NAKL could surface this as a native NSAlert instead of an AppleScript dialog; that's a separate larger spec.)
- Localising new dialog copy beyond Vietnamese (the only existing language).
- Replacing AppleScript with native code.

## Acceptance criteria (starter, needs refinement at approval time)

- [ ] `NAKL.icns`, `icon.png`, `icon24.png`, `icon_blue_24.png` removed from `project.pbxproj` (all 4 sections each: PBXBuildFile, PBXFileReference, PBXGroup, PBXResourcesBuildPhase).
- [ ] Files moved out of `NAKL/` (kept in `assets/source/` for re-export reference) or deleted entirely.
- [ ] Built `.app` bundle no longer contains those four files. Verified via `find NAKL.app -name "*.icns" -o -name "icon*.png"` returning empty.
- [ ] `scripts/.gitignore` (or root `.gitignore`) ignores `EnableAssistiveDevices.scpt`. Working tree stays clean after `xcodebuild ... build`.
- [ ] OR: Run Script build phase configured with explicit output path inside the build intermediates (not the source tree).
- [ ] AppleScript dialog text updated: replace "System Preferences" with "System Settings" and remove the 10.9 fallback paragraph.
- [ ] AppleScript `turnUIScriptingOn` updated to use the modern URL scheme (`x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility`) which works on both macOS 12 and macOS 13+.
- [ ] Smoke: launch a fresh build without Accessibility granted; the dialog renders correctly; clicking "OK" opens System Settings → Privacy & Security → Accessibility.

## Test plan

To be detailed at approval time. Manual smoke required for the Accessibility flow.

## Implementation notes

To be detailed at approval time.

For the project.pbxproj surgery, the safest approach is:

1. Identify each of the 4 IDs:
   - `51471006158B1BD000FFB252` (icon.png)
   - `5147100A158B1F4D00FFB252` (icon24.png)
   - `51471010158B2B6200FFB252` (NAKL.icns)
   - `51471012158B2C2000FFB252` (icon_blue_24.png)
2. For each ID, delete the corresponding line in 4 sections: PBXBuildFile, PBXFileReference, PBXGroup `children`, PBXResourcesBuildPhase `files`.
3. Build clean; expect zero impact since `[NSImage imageNamed:]` doesn't reach for these names.

## Open questions (resolve before approval)

- Keep originals in `assets/source/` for future re-export, or delete entirely? Recommend `assets/source/` to preserve the artwork; it's not in the bundle.
- AppleScript dialog: keep AppleScript-based, or replace with a native NSAlert + URL open in `AppDelegate`? Native is cleaner but a bigger change. Recommend keeping AppleScript here and queueing native rewrite as a separate spec if desired.

## Changelog

- 2026-04-27: drafted at status `draft` based on findings from SPEC-0006 implementation and earlier observation that the AppleScript references a renamed system app. Awaiting approval and scope refinement.
