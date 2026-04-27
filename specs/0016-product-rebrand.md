# SPEC-0016: Product rebrand — name, bundle ID, and user-data migration

**Status:** done
**Owner:** @tieubao
**Depends on:** SPEC-0010, SPEC-0011, SPEC-0015
**Blocks:** SPEC-0017

## Problem

The app currently ships as **NAKL** with bundle identifier `com.zepvn.NAKL` (resolved from `com.zepvn.${PRODUCT_NAME:rfc1034identifier}` in `NAKL/NAKL-Info.plist`). The "NAKL" name and `com.zepvn.*` namespace are inherited from the 2012 codebase. Per SPEC-0015, Phase 9 redistributes the app under a new product identity to mark the modernised line and to give the redesigned UI a clean slate.

The rebrand is not a string-replace exercise. Several systems are keyed off the current identity:

- **`NSUserDefaults`** is bundle-ID-scoped: settings live at `~/Library/Preferences/com.zepvn.NAKL.plist`. A new bundle ID = empty defaults (method, hotkeys, load-at-login, excluded apps all reset).
- **Application Support directory** is named after `CFBundleExecutable` (see `NSFileManager+DirectoryLocations.m:139-140`). User shortcuts persist at `~/Library/Application Support/NAKL/shortcuts.setting`; a renamed executable points at a different directory, orphaning the file.
- **`SMAppService.mainAppService`** (per SPEC-0011) is registered against the bundle identifier. A rebrand requires a fresh registration if the user had load-at-login enabled.
- **Notarisation** (per SPEC-0010) ships a DMG named after the product, signs against `Developer ID Application: ... (TEAMID)`, and produces a `CFBundleIdentifier`-stamped artefact.
- **Asset catalog** (per SPEC-0006) currently bundles an `AppIcon.icns` that visually represents the old product. Strictly speaking the rebrand can keep the same icon, but the user has signalled this is a relaunch, so a refresh is desirable.

The current `NSUserDefaults` keys (`NAKLKeyboardMethod`, `NAKLLoadAtLogin`, `NAKLToggleHotKey`, `NAKLSwitchMethodHotKey`, `NAKLExcludedAppBundleIds`) are static string constants in `AppData.h:25-29` and do **not** need to change; the keys live inside the per-bundle plist, and changing the keys would force every user to reconfigure their hotkeys regardless. Migration only needs to copy *values* across plists, not rename keys.

## Goal

Rename the product to `Monke` with bundle identifier `foundation.d.Monke`, and migrate any existing user state from the old identity on first launch of the new build, so users who upgrade do not lose their settings or shortcut dictionary.

> Open question (blocking approval): pick `Monke` and `foundation.d.Monke`. See § Open questions.

## Non-goals

- UI redesign. Stays out; SPEC-0017 owns that, and is the next phase to land.
- Localisation parity. SPEC-0018 owns vi/en parity. The rebrand only touches the few strings tied to identity (Info.plist `CFBundleDisplayName`, the Vietnamese AX-prompt alert in `AppDelegate.m`, the menu-bar icon's tooltip).
- Changing `NSUserDefaults` key names. Keys stay; only the containing plist file moves.
- Changing the engine, the CGEventTap pipeline, or the Preferences XIB. Those persist intact through SPEC-0017.
- Migrating users on macOS < 12. Deployment target stays at 12.0 for this spec; SPEC-0017 bumps to 14.0.
- Source-tree-wide rename. The project directory, the Xcode project file (`NAKL.xcodeproj`), and the `NAKL/` source folder may keep their current names if the rename pressure is purely cosmetic; what matters is the *built artefact*. See Implementation notes.

## Acceptance criteria

Three groups: A identity, B migration, C distribution. Each criterion independently verifiable.

### A. Bundle identity

- [ ] `NAKL/NAKL-Info.plist` `CFBundleIdentifier` resolves to `foundation.d.Monke` after build. Verified:
      ```sh
      /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" \
          build/Release/Monke.app/Contents/Info.plist
      # → foundation.d.Monke
      ```
- [ ] Built bundle name is `Monke.app`. Verified:
      ```sh
      ls build/Release/ | grep -E "^Monke\.app$"
      ```
- [ ] `CFBundleName` and `CFBundleDisplayName` both resolve to `Monke`.
- [ ] `CFBundleExecutable` is `Monke` (no spaces; if the display name has spaces, use a tight ASCII variant for the executable, e.g., display `Tieng Viet` → executable `TiengViet`).
- [ ] Xcode scheme is renamed (or aliased) to `Monke` so `xcodebuild -scheme Monke` builds.
- [ ] Asset catalog `AppIcon` set is unchanged for this spec, but is reachable via the new product name in Xcode's Targets pane.

### B. User-data migration shim

The shim runs **once**, on first launch of a build whose bundle ID does not match the legacy `com.zepvn.NAKL`, and is idempotent.

- [ ] On first launch, if `~/Library/Preferences/com.zepvn.NAKL.plist` exists AND the new bundle's `NSUserDefaults` is empty (no `NAKLKeyboardMethod` key), copy across:
      `NAKLKeyboardMethod`, `NAKLLoadAtLogin`, `NAKLToggleHotKey`, `NAKLSwitchMethodHotKey`, `NAKLExcludedAppBundleIds`.
- [ ] On first launch, if `~/Library/Application Support/NAKL/shortcuts.setting` exists AND the new directory `~/Library/Application Support/Monke/shortcuts.setting` does not, copy the file across.
- [ ] After the shim runs, set a `NAKLMigrationFromZepvnComplete = YES` flag in the new defaults so subsequent launches skip the shim.
- [ ] If the legacy `SMAppService.mainAppService.status` was `.enabled` (queryable while the legacy bundle ID is still installed), display a one-shot `NSAlert` instructing the user to re-enable load-at-login under the new identity in Preferences. **No** programmatic re-registration: the legacy and new bundle IDs are *different* services to `SMAppService`, and re-registering automatically would surface a system prompt the user did not initiate. Surface the requirement via UI; let them click the toggle.
- [ ] Verified: with a real legacy `~/Library/Preferences/com.zepvn.NAKL.plist` and `~/Library/Application Support/NAKL/shortcuts.setting` in place, launching the new build produces the equivalent files for the new bundle ID and writes the migration flag. Re-launching the new build does **not** re-copy.

### C. Distribution surface

- [ ] `scripts/notarise.sh` (per SPEC-0010) builds and notarises the rebranded app without code edits, because identity is read from `CFBundleIdentifier` in the built Info.plist (already env-var-driven). Verified:
      ```sh
      scripts/notarise.sh --check
      ```
      passes with the new bundle present.
- [ ] DMG output is `build/notarise/dist/<version>/Monke.dmg`.
- [ ] `assets/` (asset catalog source images) are reviewed; if the user supplies a refreshed icon, it lands here. If not, the existing icon ships unchanged for this spec — the rebrand is allowed to launch with the current artwork; a follow-up cosmetic spec can refresh.
- [ ] `README.md` updates the product name in the title and first paragraph; the `huyphan/NAKL` GitHub link in the README's history paragraph stays as-is (historical lineage).
- [ ] The GPLv3 file headers across all source files keep the literal phrase "NAKL project" intact for this spec; renaming them is busywork that adds nothing the user reads. A separate cleanup spec (or a one-line SPEC-0019) can sweep them later.

### Cross-cutting

- [ ] `xcodebuild -project NAKL.xcodeproj -scheme Monke -configuration Release build` exits 0 with zero new warnings sourced from the rebrand.
- [ ] **Manual smoke (clean install)**: delete the legacy bundle and all its preferences/Application-Support data, install the new build, confirm app launches, hotkeys can be configured, shortcuts can be added, and load-at-login toggle works.
- [ ] **Manual smoke (upgrade install)**: with legacy preferences and shortcuts in place, install the new build, confirm method, hotkeys, excluded apps, and shortcuts all carry over without user action.

## Test plan

Build:

```sh
xcodebuild -project NAKL.xcodeproj -scheme Monke -configuration Release build
```

Identity verification (Group A):

```sh
APP=build/Release/Monke.app
/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier"   "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleName"         "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleDisplayName"  "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Print :CFBundleExecutable"   "$APP/Contents/Info.plist"
```

Migration smoke (Group B): run *both* sequences below from a clean state. The first proves migration works; the second proves idempotence.

```sh
# Sequence 1: legacy state present
defaults write com.zepvn.NAKL NAKLKeyboardMethod -int 1
mkdir -p ~/Library/Application\ Support/NAKL
echo "stub" > ~/Library/Application\ Support/NAKL/shortcuts.setting

defaults read foundation.d.Monke 2>&1     # → "Domain ... does not exist"
open "$APP"
sleep 2
killall Monke
defaults read foundation.d.Monke NAKLKeyboardMethod        # → 1
ls ~/Library/Application\ Support/Monke/shortcuts.setting   # exists
defaults read foundation.d.Monke NAKLMigrationFromZepvnComplete             # → 1

# Sequence 2: re-launch, must be a no-op
defaults write com.zepvn.NAKL NAKLKeyboardMethod -int 99   # tamper old plist
open "$APP"
sleep 2
killall Monke
defaults read foundation.d.Monke NAKLKeyboardMethod           # → still 1, NOT 99
```

Distribution scaffold (Group C):

```sh
scripts/notarise.sh --check
ls assets/      # confirm icon source is present
```

## Implementation notes

### Where to set the new identity

The bundle identifier and product name come from Xcode build settings, not from `Info.plist` literals. `NAKL.xcodeproj/project.pbxproj` has `PRODUCT_BUNDLE_IDENTIFIER` and `PRODUCT_NAME` build settings (or relies on `${PRODUCT_NAME}` substitution in the Info.plist's `CFBundleIdentifier = com.zepvn.${PRODUCT_NAME:rfc1034identifier}`). Implementation paths:

1. **Preferred**: edit `PRODUCT_NAME` (controls executable, bundle name, and CFBundleIdentifier substitution) and override `PRODUCT_BUNDLE_IDENTIFIER` directly to `foundation.d.Monke` (decouples bundle ID from name; safer for future). Update Info.plist's `CFBundleIdentifier` to `${PRODUCT_BUNDLE_IDENTIFIER}` instead of the legacy substitution string.
2. Add `CFBundleDisplayName = Monke` to `NAKL-Info.plist` (currently absent; falls back to `CFBundleName`).

### Migration shim location

Add a Swift-callable `migrateLegacyDataIfNeeded` (or ObjC class method `+[AppData migrateLegacyDataIfNeeded]`) called from `applicationWillFinishLaunching:` *before* `[AppData loadUserPrefs]`. Implementation sketch (ObjC, fits the current code; SPEC-0017 will Swiftify the surrounding code):

```objc
+ (void)migrateLegacyDataIfNeeded {
    NSUserDefaults *new = [NSUserDefaults standardUserDefaults];
    if ([new boolForKey:@"NAKLMigrationFromZepvnComplete"]) return;

    NSUserDefaults *old = [[NSUserDefaults alloc]
        initWithSuiteName:@"com.zepvn.NAKL"];

    // Only migrate if old has data AND new is empty.
    if ([old objectForKey:NAKL_KEYBOARD_METHOD] != nil &&
        [new objectForKey:NAKL_KEYBOARD_METHOD] == nil) {
        for (NSString *key in @[NAKL_KEYBOARD_METHOD, NAKL_LOAD_AT_LOGIN,
                                NAKL_TOGGLE_HOTKEY, NAKL_SWITCH_METHOD_HOTKEY,
                                NAKL_EXCLUDED_APPS]) {
            id v = [old objectForKey:key];
            if (v) [new setObject:v forKey:key];
        }
    }

    // Move shortcuts.setting from old Application Support dir.
    NSFileManager *fm = NSFileManager.defaultManager;
    NSString *home = NSHomeDirectory();
    NSString *legacyPath = [home stringByAppendingPathComponent:
        @"Library/Application Support/NAKL/shortcuts.setting"];
    NSString *newDir = [fm applicationSupportDirectory]; // resolves to new exec name
    NSString *newPath = [newDir stringByAppendingPathComponent:@"shortcuts.setting"];
    if ([fm fileExistsAtPath:legacyPath] && ![fm fileExistsAtPath:newPath]) {
        [fm copyItemAtPath:legacyPath toPath:newPath error:NULL];
    }

    [new setBool:YES forKey:@"NAKLMigrationFromZepvnComplete"];
}
```

The `+ (NSUserDefaults *)alloc initWithSuiteName:` form reads any plist in `~/Library/Preferences/` regardless of running app's bundle ID; this is the standard cross-bundle defaults read.

### What does NOT migrate

- **`SMAppService` registration.** The system treats `com.zepvn.NAKL` and `foundation.d.Monke` as different applications. Cannot transfer registration; the user has to re-tick "Load at Login" in the new build's Preferences once. Surface this via the `NAKLAlert` described in §B acceptance criterion 4.
- **Code-signing identity.** Tied to the user's Developer Team ID, which does not change. The notarisation script reads the certificate from the keychain by pattern (`Developer ID Application:`) and is unaffected.
- **GitHub release tags.** New releases under the new name; old `v0.x` tags stay as historical NAKL releases. README links to the new release line.

### Source-tree rename

**Defer.** Renaming `NAKL.xcodeproj` → `Monke.xcodeproj`, the `NAKL/` source folder → `Monke/`, and updating every `#import "NAKL/..."` (there are none; imports are flat) is busywork. The repo can keep its `NAKL` directory name; the *built artefact* is what users see. If the user wants the source tree renamed too, that is a separate spec landed after SPEC-0017 (when SwiftUI restructuring is the natural moment to reshuffle directories).

### Notarisation script update

`scripts/notarise.sh` per SPEC-0010 already takes `NAKL_VERSION` from `CFBundleShortVersionString` and the identity from a keychain pattern. The DMG name is hard-coded `NAKL.dmg` in the spec text but the actual script (per SPEC-0010 implementation) packages by `$APP` basename. Verify at implementation time; if hard-coded, parameterise it. The DMG `volname` (`-volname NAKL`) similarly needs to read the product name from Info.plist or env.

### What to call the new product

Recommendations (any of these would work as a starting point; user picks):

| Display name | Bundle ID | Rationale |
|---|---|---|
| `Tiếng Việt Input` | `vn.tieubao.TiengVietInput` | Self-describing; English-friendly when accents are unsupported. Matches Apple's `Pinyin` / `Hangul` naming convention for input-method-style products. |
| `NAKL` (kept, with new bundle ID) | `vn.tieubao.NAKL` | Cheapest rebrand: keep the recognised name, only swap the namespace from the inherited `com.zepvn` to the user's own. |
| `Monke` | `foundation.d.Monke` | Short, evocative ("wood/wooden printing block" — a nod to traditional Vietnamese typesetting). |
| `Gõ Tiếng Việt` | `vn.tieubao.GoTiengViet` | Conflicts namespace with the existing GõTiếngViệt by Trần Kỳ Nam; **do not use** unless intentional. |

The `vn.tieubao.*` namespace is the user's personal namespace (`tieubao` matches the GitHub username and home directory). `vn.` is the country-code TLD which Apple is fine with; `com.tieubao.*` would be equivalent and more conventional for non-Vietnamese-targeted products.

## Open questions

**Blocking approval (single, load-bearing):**

- **What is `Monke` and `foundation.d.Monke`?** The user's call. Recommendations are listed above; any of them or another choice unblocks this spec for `approved` status. Once chosen, the spec body is search-and-replaced before implementation begins.

**Resolved:**

- **Migrate `SMAppService` registration?** No, per cross-bundle SMAppService semantics. Surface to user via one-shot alert.
- **Migrate the `NSUserDefaults` keys (e.g., `NAKLKeyboardMethod` → `<NewName>KeyboardMethod`)?** No. Keys are static string constants; renaming them forces every user to reconfigure regardless of where the data lives. The keys are an internal protocol; the bundle ID is the user-facing identity.
- **Refresh the app icon in this spec?** Optional. The spec accepts launching with the current icon; a refresh is a follow-up cosmetic spec.
- **Rename the source tree, Xcode project, GPLv3 headers?** Defer. Cosmetic, churn-heavy, not user-facing.

## Changelog

- 2026-04-27: drafted. Awaiting user choice of display name + bundle ID to flip to approved.
- 2026-04-27: approved. Display name = **Monke**, bundle identifier = **foundation.d.Monke**, executable name = **Monke**. Sweep replaces the inherited `com.zepvn.*` namespace with the Dwarves Foundation `foundation.d.*` namespace, which is proper reverse-DNS of the team's owned domain `d.foundation` (TLD `foundation`, second-level `d`, product `Monke`). Conforms to Apple's stated bundle-identifier convention.
  - **Note on the in-flight rename.** Earlier drafts of this spec named the product `Mộc` / `vn.tieubao.Moc` (an agent suggestion), then briefly `dfoundation.Monke` (flat, not reverse-DNS). The user landed on `Monke` / `foundation.d.Monke` before the spec stabilised. The migration shim's source bundle ID stays `com.zepvn.NAKL` (the only legacy install in the wild); no double-migration is required.
- 2026-04-27: done. Group A (identity) verified on the built bundle: `foundation.d.Monke`, name and display name `Monke`, executable `Monke`. Group C distribution scaffold satisfied: notarisation script (per SPEC-0010) is env-var-driven so no edits required; README rebranded in this commit. Group B migration code shipped in `8d35b24` and is exercised on first launch but **not yet smoke-tested by a real legacy install** — the shim's correctness is the user's first manual-smoke gate. Implementation across `8d35b24` (Mộc baseline + migration shim + Info.plist), `97b1bec` (rename to Monke + bundle ID swap), `86cf82a` (final reverse-DNS form `foundation.d.Monke`).
