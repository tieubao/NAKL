# SPEC-0002: Build baseline (Xcode 16, macOS 12, Universal)

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0001
**Blocks:** SPEC-0003

## Problem

`NAKL.xcodeproj` was last meaningfully touched in 2014. It declares `MACOSX_DEPLOYMENT_TARGET = 10.5`, has no explicit `ARCHS`, no Apple Silicon awareness, and no entitlements. Modern Xcode (15.x, 16.x) refuses several of these settings, and the build either fails or silently downgrades. There is no working baseline against which to measure the rest of the roadmap.

## Goal

Get the project building cleanly on the latest Xcode, targeting macOS 12.0 as the minimum, producing a Universal binary, with no warnings about the project format.

## Non-goals

- Source-level deprecation fixes. SPEC-0003.
- ARC migration. SPEC-0004.
- Entitlements / Hardened Runtime. SPEC-0005.
- Icon refresh. SPEC-0006.
- Removing or rewriting any source file. Build settings only.

## Acceptance criteria

- [ ] `xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Debug -destination 'platform=macOS' build` exits 0.
- [ ] `xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Release -destination 'platform=macOS' build` exits 0.
- [ ] `MACOSX_DEPLOYMENT_TARGET = 12.0` for both Debug and Release in `project.pbxproj`.
- [ ] `ARCHS = "$(ARCHS_STANDARD)"` in `project.pbxproj`.
- [ ] `ONLY_ACTIVE_ARCH = NO` for Release, `YES` for Debug.
- [ ] `lipo -archs build/Release/NAKL.app/Contents/MacOS/NAKL` prints `arm64 x86_64`.
- [ ] `xcodebuild -showBuildSettings` emits no "deprecated build setting" or "project format upgrade" warnings.
- [ ] Manual smoke: `open build/Release/NAKL.app`; menu bar icon appears; Off / VNI / Telex menu items render.

## Test plan

```bash
rm -rf build
xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Release \
    -destination 'platform=macOS' clean build 2>&1 | tee /tmp/nakl-build.log

# Zero project-level deprecation warnings
! grep -E "(deprecated build setting|project format)" /tmp/nakl-build.log

# Universal binary
lipo -archs build/Release/NAKL.app/Contents/MacOS/NAKL | grep -q "arm64 x86_64"

# Manual smoke
open build/Release/NAKL.app
# Confirm menu bar icon and Off/VNI/Telex menu items.
```

## Implementation notes

- Open `NAKL.xcodeproj` in Xcode and accept any "modernise project format" prompt.
- Settings to update in `project.pbxproj` (4 occurrences each: project + target, Debug + Release):
  - `MACOSX_DEPLOYMENT_TARGET`: 10.5 → 12.0
  - `ARCHS`: explicitly `"$(ARCHS_STANDARD)"`
  - `ONLY_ACTIVE_ARCH`: NO for Release
  - `CODE_SIGN_IDENTITY`: `"-"` (Sign to Run Locally). Real signing arrives in SPEC-0005.
- `CLANG_ENABLE_OBJC_ARC = NO` at target level stays; ARC arrives in SPEC-0004.
- Carbon framework deprecation warnings from `ShortcutRecorder/` and `HotKey/` are expected. Do not suppress; do not address. Tracked separately when those libs are touched.

## Open questions

- None expected. If a build issue cannot be resolved by build-setting changes alone, escalate as a blocker on this spec; do not begin patching `.m` files (that is SPEC-0003).

## Changelog

- 2026-04-27: drafted and approved
