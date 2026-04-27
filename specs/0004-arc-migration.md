# SPEC-0004: Migrate app target to ARC

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0003
**Blocks:** SPEC-0005, SPEC-0007

## Problem

The codebase uses manual reference counting throughout: `[obj release]`, `[super dealloc]`, `retain`/`assign` properties for object types, and the `CWLSynthesizeSingleton` macro that emits MRC-only code. Every future change risks introducing leaks or over-releases. Engine extraction (SPEC-0007) is harder while the surrounding code is MRC because moving allocations between files invalidates retain counts. Vendored libraries (`ShortcutRecorder/`, `HotKey/PT*`) cannot be safely converted without going upstream, so they must remain MRC via per-file build flags.

## Goal

Convert all `.m` files directly under `NAKL/` to ARC, isolate the still-MRC vendored libraries via per-file `-fno-objc-arc` flags, and ensure the project still compiles cleanly with no leaks during a representative session.

## Non-goals

- Converting `ShortcutRecorder/` or `HotKey/`. They stay MRC.
- Behavioural changes.
- Refactoring beyond what ARC requires.

## Acceptance criteria

- [ ] `CLANG_ENABLE_OBJC_ARC = YES` at target level in `project.pbxproj`.
- [ ] Every file in `NAKL/ShortcutRecorder/` and `NAKL/HotKey/` carries `-fno-objc-arc` as a per-file compiler flag.
- [ ] Zero `[* release]`, `[* retain]`, `[* autorelease]`, or `[super dealloc]` calls remain in `NAKL/*.m` (top level).
- [ ] `CWLSynthesizeSingleton.h` is no longer imported by any app-target file. The file may be deleted if it has no remaining importers.
- [ ] `AppData` singleton is implemented via `dispatch_once` in a `+ (instancetype)sharedInstance` (or kept as `sharedAppData` to avoid call-site churn).
- [ ] `assign` properties for object types are switched to `weak` (or `strong` if ownership is needed).
- [ ] CF objects ARC does not own (`eventTap`, `viStatusImage` if held as CF) keep explicit `CFRelease`/`CFRetain`. Bridging uses `(__bridge ...)` casts.
- [ ] `[NSKeyedUnarchiver unarchiveObjectWithFile:]` is replaced with `unarchivedObjectOfClass:fromData:error:` (small scope creep, prevents a near-future warning sweep).
- [ ] App passes the SPEC-0003 manual smoke test, byte-identical behaviour.
- [ ] Instruments → Leaks: zero leaks during a 30-second session of typing + toggling + opening Preferences.

## Test plan

```bash
xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Release \
    OTHER_CFLAGS='$(inherited) -Werror=arc-retain-cycles' clean build

# Smoke: same checklist as SPEC-0003.
open build/Release/NAKL.app

# Leaks
xcrun xctrace record --template Leaks --launch -- build/Release/NAKL.app \
    --time-limit 30s --output /tmp/nakl.trace
# Open /tmp/nakl.trace in Instruments; expect zero leaks.
killall NAKL || true
```

## Implementation notes

- **Preferred path:** open in Xcode, **Edit → Convert → To Objective-C ARC...**, scope the conversion to the app target, uncheck files under `ShortcutRecorder/` and `HotKey/`. Xcode handles ~95% mechanically.
- **Manual cleanup the wizard does NOT do:**
  - Replace `CWLSynthesizeSingleton` with `dispatch_once`. Touch `AppData.h` and `AppData.m`.
  - Inspect every `@property (assign) ...` for object types; most become `weak`. `eventTap` (`CFMachPortRef`) stays `assign` (CF type, ARC does not manage).
  - Remove `dealloc` methods that only `[super dealloc]` and release ivars. ARC handles both.
- **Per-file `-fno-objc-arc` flags:** in Xcode, target → Build Phases → Compile Sources, set the flag for every `.m` under `ShortcutRecorder/` and `HotKey/`. There are ~14 files total.
- `eventTap` is created once and never invalidated; keep that lifetime.
- `+initialize` in `AppDelegate.m` is fine under ARC; nothing inside requires a release.

## Risk

ARC migration has historically produced subtle release-timing bugs. Mitigations:

- Run Instruments → Zombies once after migration to catch over-releases.
- Keep the smoke checklist (from SPEC-0003) tight and concrete.
- This spec is a single PR; do not bundle with other refactors.

## Open questions

- Rename `+sharedAppData` to `+sharedInstance`? Defer; cosmetic, would require touching every call site.
- `CWLSynthesizeSingleton.h` deletion: do it in this spec (file becomes orphan) or defer to a cleanup spec? Recommend delete here; one-line rule.

## Changelog

- 2026-04-27: drafted and approved
