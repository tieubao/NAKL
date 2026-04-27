# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

NAKL is a macOS menu-bar app that lets users type Vietnamese with **VNI** or **Telex** input methods. It is an Objective-C / Cocoa app, originally by Huy Phan (2012), based on the keymap and key-handling algorithm of [xvnkb](http://xvnkb.sourceforge.net/).

## Build / Run

There is no Makefile, CI, or test target. Build everything through Xcode:

```bash
# Build from the command line
xcodebuild -project NAKL.xcodeproj -configuration Debug
xcodebuild -project NAKL.xcodeproj -configuration Release

# Or open in Xcode
open NAKL.xcodeproj
```

Output binary: `build/<Configuration>/NAKL.app`.

Notes:
- Single Xcode project, no workspace, no CocoaPods/SPM. All third-party code (`ShortcutRecorder/`, `HotKey/PT*`) is vendored in source form.
- `MACOSX_DEPLOYMENT_TARGET = 10.5`, `SDKROOT = macosx`. The deployment target is intentionally old; do not bump it casually.
- ARC is **disabled at the target level** (`CLANG_ENABLE_OBJC_ARC = NO`). Code uses manual `retain`/`release`/`autorelease`. New code must follow MRC conventions or it will leak / crash.
- At runtime the app needs **Accessibility permission** (System Settings → Privacy & Security → Accessibility) because it installs a global `CGEventTap`. On launch it runs `scripts/EnableAssistiveDevices.applescript` to open the right pane if permission is missing.

There are no automated tests. "Testing" means running the built app, toggling the menu-bar item, and typing into a real text field.

## Architecture

The data flow is a single global keyboard hook that mutates events in-place before they reach the focused app.

```
main.m
  └─ NSApplicationMain
       └─ AppDelegate
            ├─ +initialize          → registers defaults, prompts for AX permission
            ├─ awakeFromNib         → creates the NSStatusItem (menu bar icon)
            ├─ applicationWillFinishLaunching
            │    ├─ AppData load{UserPrefs,HotKeys,Shortcuts,ExcludedApps}
            │    ├─ kbHandler = [KeyboardHandler new]
            │    └─ -eventLoop  (background thread) ──► CGEventTapCreate(KeyHandler)
            └─ KeyHandler  (C callback, hot path)
                 ├─ skip if event flagged with NAKL_MAGIC_NUMBER (our own re-injected events)
                 ├─ skip if frontmost app's bundle ID is in AppData.excludedApps
                 ├─ on toggle/switch hotkey → flip kbHandler.kbMethod, redraw status item
                 └─ on KeyDown
                      └─ [kbHandler addKey:c]
                           └─ on hit: re-post a sequence of BACKSPACE + replacement
                                       chars via CGEventTapPostEvent (flagged with
                                       NAKL_MAGIC_NUMBER so we don't recurse)
```

Key points to keep in mind when changing anything:

- **`KeyHandler` is a C function, not a method.** It runs on the event-tap thread for every keystroke system-wide. Allocating Objective-C objects, locking, or doing I/O here will degrade typing for the whole machine. Push state into the `KeyboardHandler` singleton-ish instance (`kbHandler`) and read from `AppData` (also a singleton).
- **Re-injection guard.** Synthesised events are tagged with `NAKL_MAGIC_NUMBER (1<<29)` in their `CGEventFlags` so the next callback ignores them. Any new code that posts events must set this flag, otherwise you get an infinite loop.
- **macOS version compatibility.** `frontmostAppApiCompatible` is set in `+initialize` based on `NSAppKitVersionNumber10_7`. Below 10.7, the code uses the deprecated `[NSWorkspace activeApplication]` dict; above, it uses `frontmostApplication`. Recent commits in `git log` are specifically about this OS-version check; preserve that fallback.
- **Excluded apps** are matched by **bundle identifier**, with the app's display name stored as the value (used for the UI list). Bundle ID may be `nil` for some apps; recent commits added a filename fallback when `CFBundleName` is empty (see `ExcludedAppsTableViewController.add:`).

### Vietnamese input engine

The transformation logic lives in `KeyboardHandler.{h,m}` and the static maps:

- `keymap.h` — X11-style symbol constants (`XK_*`) and macOS keycodes (`KC_*`) used to recognise navigation/control keys that should clear the buffer.
- `telex-standard.h` — Telex composition rules.
- `utf.h`, `utf8.h` — Vietnamese precomposed character tables, vowel groups, and tone mappings.
- `KeyboardHandler` keeps a small ring buffer (`_kbBuffer[256]`, with `BACKSPACE_BUFFER = 20` slots reserved for replay) and tracks the current word/vowel positions. `addKey:` returns the number of replay characters or `-1` if the keystroke is passed through unchanged.
- `separators[]` in `AppDelegate.m` defines per-method punctuation that flushes the buffer. VNI and Telex have different separator sets (Telex omits `{}[]` because they are valid Telex shortcuts).

### Settings & persistence

- **`AppData`** is a singleton (via `CWLSynthesizeSingleton`) that owns four pieces of state, all backed by `NSUserDefaults` except shortcuts:
  - `userPrefs` — keyboard method, load-at-login flag, hotkey dictionaries, excluded apps.
  - `toggleCombo`, `switchMethodCombo` — `KeyCombo` structs (from `ShortcutRecorder`) reconstructed via `PTKeyCombo` from the plist saved by the recorder UI.
  - `shortcuts` / `shortcutDictionary` — user-defined text expansions, archived to `~/Library/Application Support/NAKL/shortcuts.setting` via `NSKeyedArchiver` (file path comes from `NSFileManager+DirectoryLocations`).
  - `excludedApps` — `{bundleId: displayName}` dictionary persisted under the `NAKL_EXCLUDED_APPS` key.
- Keys are namespaced as `NAKL*` constants in `AppData.h`. Don't introduce new untyped string keys; add a `#define` there.

### UI

- `MainMenu.xib` (English only) defines the status-bar menu (Off / VNI / Telex / Preferences / Quit).
- `Preferences.xib` is wired to `PreferencesController` and contains the two `SRRecorderControl` hotkey fields plus the `shortcutsTableView` (driven by `ShortcutTableViewController` and an `NSArrayController`).
- `ExcludedAppsTableViewController` powers the "exclude these apps" pane via an `NSOpenPanel` rooted at `/Applications`.
- Localization: `en.lproj/` is the source of truth for strings/XIBs; `vi.lproj/` only overrides `NAKL-Info.plist`. There is no `MainMenu.xib` in `vi.lproj/`.

### Vendored libraries

- `ShortcutRecorder/` — modified copy of the [ShortcutRecorder](http://wafflesoftware.net/shortcut/) library (recorder cell + control + key-code transformer). Used for the hotkey-capture fields in Preferences.
- `HotKey/` — `PTHotKey*` classes from the `PTHotKey` library, used to register the global toggle/switch hotkeys via Carbon.
- `CWLSynthesizeSingleton.h` — Matt Gallagher's singleton macro.
- `NSFileManager+DirectoryLocations.{h,m}` — utility category for `~/Library/Application Support/<AppName>` paths.

When touching files in these directories, treat them as upstream third-party code; prefer minimal, surgical changes.

## Conventions

- Files carry the GPLv3 header. New files in this repo should keep it.
- Match existing style: tabs/spaces and brace style follow the existing files; no clang-format config.
- This is **MRC, not ARC**. Always pair `alloc`/`copy`/`new` with `release` (or `autorelease`), and use `retain`/`assign`/`copy` correctly in `@property` declarations. The codebase still uses non-ARC patterns like `[super dealloc]`.
- The hot path runs on a non-main thread; UI updates from `KeyHandler` must be funnelled through `AppDelegate` methods that the runtime will dispatch correctly (the existing code calls `updateStatusItem`/`updateCheckedItem` directly; if you add anything that mutates AppKit state, hop to the main queue).
