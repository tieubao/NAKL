# SPEC-0020: KeyboardShortcuts SPM swap (retire vendored ShortcutRecorder + PTHotKey)

**Status:** draft
**Owner:** @tieubao
**Depends on:** SPEC-0017, SPEC-0019
**Blocks:** none

## Problem

SPEC-0017 deferred Group D: `ShortcutRecorder/` (10 files) and `HotKey/PT*` (8 files) remain in the build because two production code paths still consume them:

1. `AppData.h` imports `ShortcutRecorder/SRRecorderControl.h` to declare `KeyCombo` properties (`toggleCombo`, `switchMethodCombo`); the typedef itself comes from `SRCommon.h`. The `KeyHandler` C callback in `AppDelegate.m` reads those `KeyCombo.code` and `KeyCombo.flags` fields when comparing keystrokes against the user's hotkey.
2. `AppData.loadHotKeys` deserialises the `NAKLToggleHotKey` / `NAKLSwitchMethodHotKey` defaults via `PTKeyCombo initWithPlistRepresentation:` to populate the `KeyCombo` structs.

Net: 18 vendored Carbon-era source files stay compiled to support a `struct KeyCombo { keyCode, flags }` typedef and a 30-line plist-deserialiser. The real cost is two-fold:
- **Maintenance**: any future macOS or Xcode change can break the unmaintained `ShortcutRecorder` source.
- **i18n**: `ShortcutRecorder.strings` is shipped in the bundle, but consumed by a recorder UI that no longer exists post-SPEC-0017. The strings are dead weight.

`KeyboardShortcuts` (Sindre Sorhus, SPM-distributed, BSD-licensed) replaces both:
- A small Swift wrapper exposes `KeyboardShortcuts.Shortcut` (key code + modifiers) which is what `KeyCombo` was structurally; we typedef our way out of the dependency.
- Persistence is built-in via `KeyboardShortcuts.Name` + the framework's own UserDefaults schema. We migrate the existing `NAKLToggleHotKey` / `NAKLSwitchMethodHotKey` plists into the new schema on first launch and never touch the legacy keys again.

## Goal

Replace the vendored `ShortcutRecorder/` and `HotKey/PT*` source trees with the `KeyboardShortcuts` SPM dependency, migrate the existing hotkey defaults into its schema on first launch, and delete the now-unreachable Swift `HotkeyRecorderNSView` + `HotkeyPlistFormat` (SPEC-0017's interim implementations).

## Non-goals

- Changing the user's currently-bound hotkeys. Both keys round-trip through the migration shim.
- Touching the engine, `KeyboardHandler`, `KeyHandler` C callback. The hotkey *comparison* moves to a `KeyboardShortcuts.onKeyDown(for:)` handler; the keystroke pipeline that flows through to the engine is untouched.
- Adding the IMK target (still SPEC-0009, still draft).
- Changing the migration shim from SPEC-0016 (`com.zepvn.NAKL` → `foundation.d.Monke`). That source-bundle migration stays; this spec's migration is purely *within* the new bundle's defaults (legacy `PTKeyCombo` plist → `KeyboardShortcuts` plist).

## Acceptance criteria

Four groups: A SPM, B migration, C consumption, D cleanup.

### A. SPM dependency

- [ ] `NAKL.xcodeproj/project.pbxproj` declares an `XCRemoteSwiftPackageReference` for `https://github.com/sindresorhus/KeyboardShortcuts` pinned to the latest released minor at execution time.
- [ ] An `XCSwiftPackageProductDependency` ties the `KeyboardShortcuts` product to the `NAKL` target.
- [ ] `Package.resolved` checked in.
- [ ] Verified:
      ```sh
      grep -E "KeyboardShortcuts" NAKL.xcodeproj/project.pbxproj | wc -l
      ```
      returns ≥ 4 (PBXBuildFile + XCRemote + XCSwiftPackageProduct + Frameworks phase).

### B. Hotkey migration shim

- [ ] At first launch under this build, `+[AppData migrateLegacyHotkeysIfNeeded]` (new) reads `NAKLToggleHotKey` and `NAKLSwitchMethodHotKey` from `NSUserDefaults.standard`, decodes them as the legacy `PTKeyCombo` plist format (`{keyCode, modifiers, characters}`), and rewrites them into the `KeyboardShortcuts` schema:
      ```swift
      KeyboardShortcuts.setShortcut(
          .init(.init(rawValue: keyCode)!, modifiers: cocoaModifiers(carbon: modifiers)),
          for: .toggleVietnamese)
      ```
- [ ] After migration, the legacy keys are removed from defaults so they no longer race with the new schema.
- [ ] Idempotent: a `NAKLHotkeyMigrationToKeyboardShortcutsComplete` flag prevents re-running.
- [ ] Verified by unit test: seed legacy plist, run shim, assert `KeyboardShortcuts.getShortcut(for: .toggleVietnamese)` returns the expected combo, assert legacy keys are gone.

### C. Consumption

- [ ] `AppData.h` no longer imports `ShortcutRecorder/SRRecorderControl.h`. The `toggleCombo` / `switchMethodCombo` properties are replaced by computed getters that wrap `KeyboardShortcuts.getShortcut(for:)`, OR removed entirely if only the `KeyHandler` callback uses them and the callback is moved to a Swift `KeyboardShortcuts.onKeyDown(for:)` registration.
- [ ] **Recommended**: drop the in-callback comparison entirely. Use `KeyboardShortcuts.onKeyDown(for: .toggleVietnamese) { /* flip method */ }` and the same for `.switchMethod`. The `KeyHandler` C callback no longer compares against `toggleCombo` / `switchMethodCombo`; those Carbon-event-tap hotkey-detection branches are dead code and removed.
- [ ] `KeyboardShortcuts.Recorder` SwiftUI view replaces SPEC-0017's interim `HotkeyRecorderField` / `HotkeyRecorderNSView`. Settings → Hotkeys tab is a 6-line Swift file.
- [ ] Acceptance criterion verifies no surviving import of `PTHotKey`, `PTKeyCombo`, `SRRecorderControl`, `SRCommon`, `KeyCombo` in any production source:
      ```sh
      grep -rE 'PTHotKey|PTKeyCombo|SRRecorderControl|SRCommon|\bKeyCombo\b' \
          NAKL/ --include='*.h' --include='*.m' --include='*.swift'
      ```
      returns empty.

### D. Cleanup

- [ ] `NAKL/HotKey/` directory deleted (8 PTHotKey* files plus the SPEC-0017 interim Swift `HotkeyRecorderNSView.swift` + `HotkeyPlistFormat.swift`).
- [ ] `NAKL/ShortcutRecorder/` directory deleted (10 SR* files).
- [ ] `NAKL/en.lproj/ShortcutRecorder.strings` deleted; pbxproj `ShortcutRecorder.strings` PBXVariantGroup + PBXBuildFile + Resources entry removed.
- [ ] All corresponding pbxproj entries (PBXFileReference, PBXBuildFile, PBXSourcesBuildPhase files) removed.
- [ ] Cross-cutting: `xcodebuild` exits 0 with zero new warnings sourced from the swap.

### E. Tests

- [ ] Existing 18-test suite still passes (engine corpus + Swift unit tests).
- [ ] New unit test in `tests/EngineTests/HotkeyMigrationTests.swift` exercises the legacy-→-`KeyboardShortcuts` migration in isolation, using a unique defaults suite.
- [ ] HotkeyFormatTests (the SPEC-0017 interim Swift unit tests) get deleted since the file under test is gone. Replaced by the migration test.

## Test plan

```sh
# A: SPM resolution
xcodebuild -project NAKL.xcodeproj -resolvePackageDependencies
ls NAKL.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved

# B+C: build + tests
xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Debug build
xcodebuild test -project NAKL.xcodeproj -scheme NAKL \
    -destination 'platform=macOS' -only-testing:NAKLEngineTests

# D: source tree
test ! -d NAKL/HotKey
test ! -d NAKL/ShortcutRecorder
test ! -f NAKL/en.lproj/ShortcutRecorder.strings
grep -rE 'PTHotKey|PTKeyCombo|SRRecorderControl' NAKL/ --include='*.h' --include='*.m' --include='*.swift'
# → empty

# Manual smoke
# 1. Open Preferences → Hotkeys. The KeyboardShortcuts.Recorder shows the migrated
#    bindings (e.g., ⌃⌥V for toggle).
# 2. Press the toggle hotkey 5×; observe method flip + icon update.
# 3. Re-bind to a new combo; quit; relaunch; new combo persists.
```

## Implementation notes

### Why this depends on SPEC-0019

`KeyHandler` (the C callback) currently performs the hotkey comparison inline. SPEC-0020 moves that comparison out of the callback into Swift via `KeyboardShortcuts.onKeyDown(for:)`. That registration must be set up in the app lifecycle, ideally on `applicationWillFinishLaunching`. With the legacy `AppDelegate.m` still in place (pre-SPEC-0019), wiring this is awkward (Swift would have to call into ObjC to register handlers and then call into Swift handlers). With SPEC-0019 done, the lifecycle is already Swift; the registration is a single line inside `MonkeAppDelegate.applicationWillFinishLaunching`.

It is technically possible to land SPEC-0020 before SPEC-0019 by keeping the Carbon comparison in `KeyHandler` and just swapping the *recorder UI*, but that defeats half the value.

### Migration shim correctness

The `PTKeyCombo` plist format is `{characters: NSString, keyCode: NSNumber, modifiers: NSNumber}` where `modifiers` is the Carbon modifier bitmask (`cmdKey`, `optionKey`, `controlKey`, `shiftKey` from `Carbon.HIToolbox.Events`). The Swift conversion exists in the SPEC-0017 interim `HotkeyPlistFormat.cocoaModifiersFromCarbon`; reuse that function inside the migration shim before the file is deleted.

### Why `onKeyDown` instead of `onKeyUp`

Today's CGEventTap callback flips the method on `kCGEventKeyDown` (line 142 of pre-SPEC-0019 `AppDelegate.m`). `KeyboardShortcuts.onKeyDown` matches that semantic.

### Risk

`KeyboardShortcuts` is widely used (Rectangle, Dato, NetNewsWire, Plash, etc., totalling ~10M+ installs). The library itself is mature. Risk concentrates on the migration shim correctness — specifically, edge cases around modifier bitmasks where the Carbon bit positions differ from Cocoa's `NSEvent.ModifierFlags`. Mitigated by the unit test in §E.

## Open questions

- **Pin to a specific minor version, or `from:`?** Recommendation: `from: "1.X.0"` (minor pin, allows patch updates), aligned with the rest of the user's stack.
- **Should the migration shim run inside `+[AppData migrateLegacyDataIfNeeded]` (alongside the SPEC-0016 cross-bundle migration) or as a separate `+[AppData migrateLegacyHotkeysIfNeeded]`?** Recommendation: separate method. The two migrations have unrelated triggers (cross-bundle vs cross-schema) and bundling them risks running the cross-schema migration before the new defaults are seeded.
- **Do we expose a "Reset hotkeys to defaults" button in Preferences?** Out of scope; user can Cmd-Click the recorder field per `KeyboardShortcuts`'s default behaviour to clear, which is enough.

## Changelog

- 2026-04-27: drafted. Defers execution to a dedicated session post-SPEC-0019.
