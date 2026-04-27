# SPEC-0012: Bundle cleanup and EnableAssistiveDevices script modernisation

**Status:** approved
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

## Acceptance criteria

Three independent groups (A bundle, B build pollution, C AppleScript). Each criterion independently verifiable.

### A. Dead bundle resources removed

- [ ] `NAKL.icns`, `icon.png`, `icon24.png`, `icon_blue_24.png` removed from `NAKL.xcodeproj/project.pbxproj`. All 4 sections per file (PBXBuildFile, PBXFileReference, PBXGroup `children`, PBXResourcesBuildPhase `files`). Verified by:
      ```sh
      grep -nE "icon\.png|icon24\.png|NAKL\.icns|icon_blue_24\.png" NAKL.xcodeproj/project.pbxproj
      ```
      returns empty.
- [ ] Source files moved to `assets/source/` (preserve artwork; do not delete). Verified:
      ```sh
      ls assets/source/ | sort
      # → NAKL.icns, icon.png, icon24.png, icon_blue_24.png
      test ! -e NAKL/NAKL.icns -a ! -e NAKL/icon.png -a ! -e NAKL/icon24.png -a ! -e NAKL/icon_blue_24.png
      ```
- [ ] `xcodebuild -project NAKL.xcodeproj -configuration Debug build` exits 0.
- [ ] Built `.app` bundle no longer contains those four files. Verified:
      ```sh
      find build/Debug/NAKL.app \( -name "*.icns" -o -name "icon.png" -o -name "icon24.png" -o -name "icon_blue_24.png" \)
      ```
      returns empty.
- [ ] `assetutil --info build/Debug/NAKL.app/Contents/Resources/Assets.car` still lists `AppIcon`, `StatusBarVI`, `StatusBarEN` (regression check on SPEC-0006 work).

### B. Build artefact no longer pollutes source tree

Decision: ignore the generated `.scpt` rather than redirecting the build output. Rationale: the existing build-phase ordering (Sources → Frameworks → Resources → ShellScript → CopyFiles) regenerates the `.scpt` before `CopyFiles` consumes it, so the file's source-tree presence is purely a build artefact. Redirecting to `${DERIVED_FILE_DIR}` would also require rewriting the `EnableAssistiveDevices.scpt` `PBXFileReference` path; ignoring is one line.

- [ ] `.gitignore` (root) ignores `scripts/EnableAssistiveDevices.scpt`. Verified:
      ```sh
      git check-ignore scripts/EnableAssistiveDevices.scpt
      # → scripts/EnableAssistiveDevices.scpt
      ```
- [ ] After a clean build, the working tree is clean from this file's perspective:
      ```sh
      rm -f scripts/EnableAssistiveDevices.scpt
      xcodebuild -project NAKL.xcodeproj -configuration Debug build
      git status --porcelain | grep -E "EnableAssistiveDevices\.scpt"
      ```
      returns empty (the rebuilt `.scpt` is ignored).
- [ ] `find build/Debug/NAKL.app -name "EnableAssistiveDevices.scpt"` is non-empty (the `.scpt` still ships in the bundle).

### C. AppleScript modernised for macOS 12+ / System Settings

- [ ] `scripts/EnableAssistiveDevices.applescript` no longer contains the literal string `"System Preferences"`. Verified:
      ```sh
      iconv -f UTF-16LE -t UTF-8 scripts/EnableAssistiveDevices.applescript | grep -F "System Preferences"
      ```
      returns empty.
- [ ] AppleScript no longer contains the macOS 10.9 fallback paragraph (`MacOS cũ hơn 10.9` / `huyphan.github.io/NAKL/index.html#faq`). Verified by `iconv ... | grep -F "10.9"` returning empty.
- [ ] `turnUIScriptingOn` opens the Accessibility pane via the modern URL scheme `x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility` (works on macOS 12 and 13+). Verified by `iconv ... | grep -F "x-apple.systempreferences"` returning the URL.
- [ ] Dialog text references "System Settings > Privacy & Security > Accessibility" (current macOS 13+ path; macOS 12 users see "System Preferences" but the system handles the URL redirect).
- [ ] File remains UTF-16 LE encoded (so `osacompile` keeps working). Verified:
      ```sh
      file scripts/EnableAssistiveDevices.applescript | grep -F "UTF-16, little-endian"
      ```
- [ ] **Manual smoke**: revoke Accessibility for NAKL in System Settings → Privacy & Security → Accessibility. Quit and relaunch `build/Debug/NAKL.app`. The dialog appears; the OK action lands in System Settings → Privacy & Security → Accessibility (macOS 13+) or the equivalent System Preferences pane (macOS 12).

## Test plan

Run all automatable verification commands listed under each acceptance criterion above. Then the single manual smoke (criterion C, last item):

1. Build: `xcodebuild -project NAKL.xcodeproj -configuration Debug build`
2. `killall NAKL || true; open build/Debug/NAKL.app`
3. In System Settings → Privacy & Security → Accessibility, toggle NAKL off.
4. Quit and relaunch NAKL. Verify the localised Vietnamese dialog appears.
5. Click OK. Verify the system opens directly to Privacy & Security → Accessibility (macOS 13+) or System Preferences → Security & Privacy → Privacy → Accessibility (macOS 12).

## Implementation notes

For the `project.pbxproj` surgery, the safest approach is:

1. Identify each of the 4 IDs (canonical assignments per the file as of `2510f4e`):
   - `51471006158B1BD000FFB252` (icon.png)
   - `5147100A158B1F4D00FFB252` (icon24.png)
   - `51471010158B2B6200FFB252` (NAKL.icns)
   - `51471012158B2C2000FFB252` (icon_blue_24.png)
2. For each ID, first `grep <ID> NAKL.xcodeproj/project.pbxproj` to confirm exactly the expected occurrences (PBXBuildFile, PBXFileReference, PBXGroup `children`, PBXResourcesBuildPhase `files`). Delete those lines and nothing else.
3. `xcodebuild -project NAKL.xcodeproj -configuration Debug clean build` and check for "missing file" errors. None expected; `[NSImage imageNamed:]` reaches into the asset catalog, not these loose files.
4. Move (do not delete) the four files into `assets/source/`. Create the directory if absent. Add `assets/source/README.md` noting that these are reference originals not in the build.

For the `.scpt` ignore: append `scripts/EnableAssistiveDevices.scpt` to the root `.gitignore`. If the file does not yet exist, create it with that line plus the standard macOS noise (`.DS_Store`, `build/`, `xcuserdata/`).

For the AppleScript modernisation: convert UTF-16 LE → UTF-8 with `iconv` for editing, edit, then convert back to UTF-16 LE with BOM. Replace the `tell application "System Preferences"` block with `do shell script "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"`. Strip the macOS 10.9 fallback paragraph entirely (irrelevant since 2014).

## Open questions

Resolved at approval:

- **Keep originals or delete?** Keep in `assets/source/`. Preserves artwork for future re-export at negligible repo cost.
- **AppleScript or native rewrite?** Keep AppleScript here; this spec stays a cleanup. A native NSAlert + `[NSWorkspace openURL:]` rewrite is queued as a follow-up spec if the existing flow proves fragile in user reports.

## Changelog

- 2026-04-27: drafted at status `draft` based on findings from SPEC-0006 implementation and earlier observation that the AppleScript references a renamed system app. Awaiting approval and scope refinement.
- 2026-04-27: refined acceptance criteria into three independently verifiable groups (A bundle, B build pollution, C AppleScript) with explicit verification commands per criterion; resolved both open questions (keep originals; keep AppleScript); locked the build-pollution approach to `.gitignore` rather than `${DERIVED_FILE_DIR}` redirection (one-line change vs. project-file edit + path rewrite); status flipped to `approved`.
- 2026-04-27: implemented as approved with one minor criterion clarification:
  - **A bundle**: removed all 16 lines (4 IDs × 4 sections) from `project.pbxproj`; moved `NAKL.icns`, `icon.png`, `icon24.png`, `icon_blue_24.png` from `NAKL/` to new `assets/source/` directory with a `README.md` explaining their purpose. Clean rebuild succeeds.
  - **A4 amendment**: the criterion as written (`find ... \( -name "*.icns" -o ... \)`) matches the SPEC-0006-generated `AppIcon.icns` inside the built `.app`, which is the *correct* modern asset-catalog output (not a leftover). The intent was to exclude the legacy files only. Spirit of the criterion is met: only `AppIcon.icns` (the SPEC-0006 product) ships in the bundle; `NAKL.icns`, `icon.png`, `icon24.png`, `icon_blue_24.png` do not. Future revisions should re-write the criterion as `find ... -name NAKL.icns -o -name "icon.png" -o -name "icon24.png" -o -name "icon_blue_24.png"` rather than the broader wildcard.
  - **B build pollution**: appended `scripts/EnableAssistiveDevices.scpt` to root `.gitignore`. Verified: file is regenerated by the Run Script phase before `CopyFiles` consumes it; `git status` stays clean; bundle still contains the `.scpt`.
  - **C AppleScript**: replaced `tell application "System Preferences"` block with `do shell script "open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'"`; updated dialog text to "System Settings > Privacy & Security > Accessibility"; removed the macOS 10.9 fallback paragraph entirely. File remains UTF-16 LE with BOM (verified via `file`).
  - All automatable verifications pass. Manual Accessibility-revoke smoke (criterion C, last item) is the user's to run on next launch.
