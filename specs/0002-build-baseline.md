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
- [ ] `xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Release -destination 'generic/platform=macOS' build` exits 0. (Universal: `generic/platform=macOS` not `platform=macOS`; the latter resolves to the host arch only.)
- [ ] `MACOSX_DEPLOYMENT_TARGET = 12.0` for both Debug and Release in `project.pbxproj`.
- [ ] `ARCHS = "$(ARCHS_STANDARD)"` in `project.pbxproj`.
- [ ] `ONLY_ACTIVE_ARCH = NO` for Release, `YES` for Debug.
- [ ] `lipo -archs build/Release/NAKL.app/Contents/MacOS/NAKL` prints `x86_64 arm64`.
- [ ] `xcodebuild -showBuildSettings` emits no "deprecated build setting" or "project format upgrade" warnings.
- [ ] `NAKL/en.lproj/Preferences.xib` deployment version bumped from `1050` to `120000`. (Discovered: ibtool refuses to compile XIBs whose embedded deployment is older than 10.6 even when the project target is 12.0.)
- [ ] Manual smoke: `open build/Release/NAKL.app`; menu bar icon appears; Off / VNI / Telex menu items render.

## Test plan

```bash
DD=$(mktemp -d -t nakl-release)
xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Release \
    -destination 'generic/platform=macOS' -derivedDataPath "$DD" clean build \
    > /tmp/nakl-build.log 2>&1
echo "exit=$?"

# Zero project-level deprecation warnings
! grep -E "(deprecated build setting|project format)" /tmp/nakl-build.log

# Universal binary (order may be x86_64 arm64 or arm64 x86_64)
lipo -archs "$DD/Build/Products/Release/NAKL.app/Contents/MacOS/NAKL" \
    | tr ' ' '\n' | sort | tr '\n' ' '
# Expected: "arm64 x86_64"

# Manual smoke
open "$DD/Build/Products/Release/NAKL.app"
# Confirm menu bar icon and Off/VNI/Telex menu items.
```

## Implementation notes

Files touched:

- `NAKL.xcodeproj/project.pbxproj`: 4 settings (each in 4 places: project + target × Debug + Release).
- `NAKL/en.lproj/Preferences.xib`: 1-line embedded `<deployment version>` bump.

`project.pbxproj` settings to update:

- `MACOSX_DEPLOYMENT_TARGET`: 10.5 → 12.0 (4 occurrences).
- `ARCHS`: was `"$(ARCHS_STANDARD_64_BIT)"` (project) and `"$(ARCHS_STANDARD_32_64_BIT)"` (target); both → `"$(ARCHS_STANDARD)"`.
- `ONLY_ACTIVE_ARCH = NO` made explicit at project Release (was implicit default).
- `CODE_SIGN_IDENTITY = "-"` already present at target level. Real signing arrives in SPEC-0005.

`CLANG_ENABLE_OBJC_ARC = NO` at target level stays; ARC arrives in SPEC-0004.

Carbon framework deprecation warnings from `ShortcutRecorder/` and `HotKey/` are expected. Do not suppress; do not address. Tracked separately when those libs are touched.

Two warnings discovered during baseline that are deliberately NOT fixed in this spec:

- `User-supplied CFBundleIdentifier value 'com.zepvn.NAKL' in the Info.plist must be the same as the PRODUCT_BUNDLE_IDENTIFIER build setting value ''.` SPEC-0005 territory (signing).
- `Run script build phase 'Run Script' will be run during every build because it does not specify any outputs.` Pre-existing build-phase config; out of scope here.

## Open questions

- None expected. If a build issue cannot be resolved by build-setting changes alone, escalate as a blocker on this spec; do not begin patching `.m` files (that is SPEC-0003).

## Changelog

- 2026-04-27: drafted and approved
- 2026-04-27: amended during implementation. Added `Preferences.xib` to the file list (embedded deployment target needed bump for ibtool). Corrected test plan to use `generic/platform=macOS` (the original `platform=macOS` resolves to host arch only on Apple Silicon and produces a non-Universal binary).
