# SPEC-0019: MenuBarExtra rewrite (retire main.m + AppDelegate + MainMenu.xib)

**Status:** draft
**Owner:** @tieubao
**Depends on:** SPEC-0017
**Blocks:** none

## Problem

SPEC-0017 deferred Group B (`MenuBarExtra`) and shipped a SwiftUI Preferences window hosted inside the legacy ObjC AppDelegate + MainMenu.xib. The menu-bar status item, the Off/VNI/Telex menu, the `+[AppDelegate initialize]` AX-permission flow, the CGEventTap event loop, and the hotkey comparison inside `KeyHandler` all still run from `main.m → NSApplicationMain → MainMenu.xib → AppDelegate`.

The deferral was correct at the time; the marginal user-visible benefit of swapping the existing `NSStatusItem` for SwiftUI's `MenuBarExtra` was small and the entry-point switch was risky in batched mode. Now that the SwiftUI Preferences UI is stable, the menu-bar shell is the last AppKit / XIB surface in the project. Retiring it unblocks:

- Full removal of `MainMenu.xib` and `en.lproj/MainMenu.xib` (the menu items, including the AX-prompt-related labels, would localise via the Swift catalog instead of XIB-localised IB strings).
- Deletion of `main.m` and `AppDelegate.{h,m}` once their responsibilities (AX-permission check, event-tap creation, status-item rendering, menu-method binding) move into Swift.
- A single source of truth for the app lifecycle (`@main App`) and a single source for hotkey UX.

## Goal

Replace the `NSApplicationMain → MainMenu.xib → AppDelegate` boot path with a `@main App` struct hosting a SwiftUI `MenuBarExtra` scene plus the existing `Settings` scene, retaining behavioural parity with today's menu (Off / VNI / Telex / Preferences… / Quit), the CGEventTap pipeline, and the AX-permission flow.

## Non-goals

- Touching the engine, `KeyboardHandler`, `AppData`, or `ShortcutSetting`. They survive verbatim, called from Swift via the bridging header.
- Swapping the hotkey lib. SPEC-0020 owns that; this spec keeps the existing PTKeyCombo plist format and the in-callback comparison logic.
- Changing the in-event-tap re-injection protocol (`NAKL_MAGIC_NUMBER` re-entry guard). Stays.
- Localising the menu items beyond what SPEC-0018's catalog already covers; the menu uses `Text(localized:)` lookups against the same catalog.
- Adding new features (popover-style menu, recent shortcuts, status-bar quick-toggle). Behavioural parity only.

## Acceptance criteria

Three groups: A scaffold, B behaviour, C cleanup.

### A. Scaffold

- [ ] `NAKL/MonkeApp.swift` declares the `@main` App with a `MenuBarExtra` scene whose label is the current method's status icon.
- [ ] `Info.plist` no longer declares `NSMainNibFile = MainMenu`. `NSPrincipalClass = NSApplication` stays.
- [ ] `LSUIElement = YES` retained (menu-bar-only; no Dock).
- [ ] An `@NSApplicationDelegateAdaptor` wires a Swift `MonkeAppDelegate` for the legacy hooks (AX-permission check, event-tap lifecycle, KeyboardHandler retention).

### B. Behaviour

- [ ] Status icon updates on method change (Off / VNI / Telex). Verified: cycle the menu items; observe icon flips between `Status`, `StatusVNI`, `StatusVI`.
- [ ] Menu items reproduce today's static menu plus `⌘,` shortcut for Preferences and `⌘Q` for Quit.
- [ ] Selecting **Preferences…** opens the Settings scene via `EnvironmentValues.openSettings()` (no `NSHostingController` shim).
- [ ] AX-permission alert from SPEC-0014 + SPEC-0018 still appears on first launch when permission is missing; localised text from `Localizable.xcstrings`.
- [ ] CGEventTap thread starts on `applicationWillFinishLaunching`, identical to today's `-eventLoop` behaviour. The C `KeyHandler` callback signature unchanged; its `refcon` is now an `@MainActor` Swift class instance bridged via `Unmanaged`.
- [ ] Toggle and switch-method hotkeys still flip the method, identical semantics. (Hotkey lib swap is SPEC-0020; this spec keeps the in-callback comparison.)
- [ ] SPEC-0008 corpus: `xcodebuild test -only-testing:NAKLEngineTests` exits with 18 / 18 pass (engine + the Swift unit tests added in this session).
- [ ] Manual smoke from SPEC-0017's test plan still passes (Preferences round-trip, shortcut add, excluded apps, hotkey recorder).

### C. Cleanup

- [ ] `NAKL/main.m`, `NAKL/AppDelegate.h`, `NAKL/AppDelegate.m` deleted.
- [ ] `NAKL/en.lproj/MainMenu.xib` deleted; pbxproj `MainMenu.xib` PBXVariantGroup + PBXBuildFile removed.
- [ ] `NAKL/PreferencesWindowController.swift` (the SPEC-0017 NSHostingController shim) deleted; replaced by direct `Settings { SettingsRoot() }` scene.
- [ ] `NAKL/Monke-Bridging-Header.h` retained (engine + KeyboardHandler + AppData still ObjC-bridged).
- [ ] No surviving import of `Moc-Swift.h` / `Monke-Swift.h` in ObjC sources (none should remain after AppDelegate.m is gone).

## Test plan

```sh
# Source assertions
test ! -f NAKL/main.m
test ! -f NAKL/AppDelegate.m
test ! -f NAKL/AppDelegate.h
test ! -f NAKL/en.lproj/MainMenu.xib
grep -n "NSMainNibFile" NAKL/NAKL-Info.plist   # → empty

# Build
xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Release build

# Engine + Swift unit corpus
xcodebuild test -project NAKL.xcodeproj -scheme NAKL \
    -destination 'platform=macOS' -only-testing:NAKLEngineTests
# → 18 tests pass

# Manual smoke
open build/Release/Monke.app
# 1. Click menu bar icon → Off / VNI / Telex / Preferences… (⌘,) / Quit (⌘Q).
# 2. Cycle methods; icon updates.
# 3. ⌘, opens Settings; tabs work; close; reopen via menu.
# 4. Type "tieengs vieet" in TextEdit → "tiếng việt" (engine intact).
# 5. AX-permission alert reappears after revoking the permission.
```

## Implementation notes

### Lifecycle bridge

```swift
@main
struct MonkeApp: App {
    @NSApplicationDelegateAdaptor(MonkeAppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra { MenuBarMenuView() }
        label: { Image(StatusModel.shared.iconName) }

        Settings { SettingsRoot() }
    }
}

@MainActor
final class MonkeAppDelegate: NSObject, NSApplicationDelegate {
    private var keyboardHandler: KeyboardHandler?

    func applicationWillFinishLaunching(_ notification: Notification) {
        AppData.migrateLegacyDataIfNeeded()
        AppData.loadUserPrefs()
        AppData.loadHotKeys()
        AppData.loadShortcuts()
        AppData.loadExcludedApps()

        if !AXIsProcessTrusted() { presentAccessibilityAlert() }

        keyboardHandler = KeyboardHandler()
        keyboardHandler?.kbMethod = Int32(/* read from defaults */)
        // Spawn the CGEventTap thread; same C function ports verbatim.
        Thread.detachNewThread { [weak self] in self?.runEventTap() }
    }
}
```

### CGEventTap thread

The C function `KeyHandler` signature stays:
```c
CGEventRef KeyHandler(CGEventTapProxy proxy, CGEventType type,
                      CGEventRef event, void *refcon);
```
`refcon` is now a Swift class instance, passed via `Unmanaged.passUnretained(self).toOpaque()` and read back inside the C function as a `(__bridge MonkeAppDelegate *)refcon` from a tiny ObjC shim (or via `Unmanaged.fromOpaque(...).takeUnretainedValue()` if we move the C function to Swift's `@_silgen_name`). Recommendation: keep the C function in `KeyboardHandler.m` and pass a stable opaque pointer to a `KeyboardHandlerHost` ObjC class that exposes `kbMethod` as a property; minimal change.

### Status icon

`StatusModel @Observable` (already designed in SPEC-0017's "Status icon update path" section, never landed). `MenuBarExtra` reads `Image(StatusModel.shared.iconName)` directly; the C callback hops to main and updates the published `iconName`.

### Risk

Swift `@main` + `@NSApplicationDelegateAdaptor` + `MenuBarExtra` is a well-trodden pattern post-macOS 14. Risk concentrates on the bridge between the C callback and the Swift @MainActor model — specifically that the existing comparison `(flag & controlKeys) == toggleCombo.flags` references the `KeyCombo` struct from `ShortcutRecorder/SRCommon.h`. Stays, since SPEC-0020 has not yet retired ShortcutRecorder.

## Open questions

- **Should `Quit` go through `NSApp.terminate(_:)` or via SwiftUI's `dismiss` on the scene?** Open until implementation; recommendation: `NSApp.terminate(_:)` to match today's behaviour.
- **Does `MenuBarExtra(style: .menu)` (default) support a Picker for the three methods cleanly, or do we need `style: .window` with a custom popover?** Default `.menu` style with three `Toggle` rows or a `Picker(selection:)` is the SwiftUI-native form; verify at scaffold time. Fall back to `.window` only if `.menu` proves insufficient for the icon-update + checkmark UX.
- **Do we keep the SwiftUI Preferences window's title customisation (`window.title = "Monke Preferences"`) once the Settings scene takes over?** SwiftUI's `Settings` scene auto-titles based on `CFBundleDisplayName`. The Localizable.xcstrings `Monke Preferences` entry can stay or be removed; defer to implementation.

## Changelog

- 2026-04-27: drafted. Defers execution to a dedicated session.
