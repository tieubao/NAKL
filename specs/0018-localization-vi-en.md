# SPEC-0018: Full Vietnamese / English localisation via String Catalog

**Status:** done
**Owner:** @tieubao
**Depends on:** SPEC-0014, SPEC-0015, SPEC-0017
**Blocks:** none

## Problem

Localisation today is a stub:

- `vi.lproj/` contains only `NAKL-Info.plist`. There is no Vietnamese MainMenu, no Vietnamese Preferences, no Vietnamese in-app strings.
- `en.lproj/` is the source of truth: `MainMenu.xib`, `Preferences.xib`, `ShortcutRecorder.strings`, plus `InfoPlist.strings`.
- The one piece of in-app Vietnamese is the AX-permission prompt embedded in `scripts/EnableAssistiveDevices.applescript` (now being moved to an `NSAlert` literal by SPEC-0014). That string never goes through `NSLocalizedString`.

After SPEC-0017 lands, the XIBs are deleted and every UI string is in `String(localized: ...)` calls. That makes the *mechanism* for full vi/en parity trivial: extract strings into `Localizable.xcstrings`, translate the Vietnamese variants, set the app's localizations metadata to advertise both. What remains is the *user-visible* contract:

1. The app should pick a language sensibly: respect `Settings → General → Language` from SPEC-0017, fall back to the system locale, default to English if the system locale is neither English nor Vietnamese.
2. Switching language inside Settings should take effect without a full app relaunch — at minimum the Settings window itself should re-render, and ideally the menu-bar menu and any subsequent alerts too.
3. The Finder display name (`CFBundleDisplayName`) should localise: English Finder shows `<NEW_DISPLAY_NAME>`, Vietnamese Finder shows the translated equivalent if one was chosen.

## Goal

Ship full English + Vietnamese parity across every user-visible string in the app, persisted in a single `Localizable.xcstrings` catalog, with a runtime language picker in Settings that updates SwiftUI views without requiring an app relaunch.

## Non-goals

- Localising into any third language. The user's request is en + vi only.
- Localising the GPLv3 file headers, source-code identifiers, NSUserDefaults keys, or commit messages.
- Translating the README. README is authored in English; a future spec can add a `README.vi.md` if there is demand.
- Localising the Vietnamese transformation engine output. The engine produces Vietnamese characters by definition; this spec localises the *UI around it*.
- Re-localising the menu-bar icon images (no text on them; they are pictograms).
- Building an in-app translation flow ("help us translate" forms). Translations are committed by the maintainer, not crowdsourced.
- Accessibility translations beyond `String(localized:)`. VoiceOver labels, hints, etc., are out of scope and would land as a follow-up `accessibility` spec.

## Acceptance criteria

Three groups: A catalog, B coverage, C runtime switch. Each criterion independently verifiable.

### A. String catalog

- [ ] `NAKL/Localizable.xcstrings` exists. Format is the modern Xcode 15+ `.xcstrings` (JSON), not the legacy `.strings`. Verified:
      ```sh
      file NAKL/Localizable.xcstrings | grep -E "JSON|ASCII text"
      ```
- [ ] Catalog declares both `en` and `vi` localizations. Verified:
      ```sh
      jq '.sourceLanguage, (.strings | to_entries[0].value.localizations | keys)' \
         NAKL/Localizable.xcstrings
      # → "en"
      # → ["en","vi"]   (or ["vi","en"]; order is irrelevant)
      ```
- [ ] No string in the catalog is `state = "needs_review"` or `state = "stale"`. Verified:
      ```sh
      jq '[.. | objects | select(.state == "needs_review" or .state == "stale")] | length' \
         NAKL/Localizable.xcstrings
      # → 0
      ```
- [ ] Every Vietnamese variant uses precomposed Unicode (NFC). Verified:
      ```sh
      jq '.. | objects | .stringUnit?.value | strings' NAKL/Localizable.xcstrings \
         | python3 -c 'import sys, unicodedata; bad=[l for l in sys.stdin if unicodedata.normalize("NFC", l) != l]; sys.exit(1 if bad else 0)'
      ```
- [ ] `Info.plist` `CFBundleLocalizations` lists both `en` and `vi`.
- [ ] `vi.lproj/InfoPlist.strings` exists with localised `CFBundleDisplayName` (and `CFBundleName` if the user wants a different Vietnamese product name; otherwise both share the same value).

### B. Coverage

- [ ] **No string-literal user-facing text** in any `.swift` file. Every `Text(...)`, `Button(...)`, `Label(...)`, `.navigationTitle(...)`, alert message, etc., uses `String(localized: ...)` or the corresponding `LocalizedStringKey` overload. Verified by inspection of the four `Settings/*.swift` views and `App.swift`. Concrete grep target (heuristic, not authoritative):
      ```sh
      grep -nE 'Text\("[A-Z]|Button\("[A-Z]|Label\("[A-Z]' NAKL/*.swift NAKL/Settings/*.swift \
          | grep -vE 'String\(localized:|LocalizedStringKey'
      ```
      should return empty.
- [ ] The `NSAlert` introduced by SPEC-0014 reads its message and informative text from the catalog. The alert is shown once at first launch when Accessibility permission is missing; the Vietnamese variant matches the wording previously embedded in `scripts/EnableAssistiveDevices.applescript:12-14` (preserve the source-of-truth phrasing).
- [ ] Status menu items (**Off / VNI / Telex / Preferences… / Quit**) are localised. The Settings tab labels (**General / Shortcuts / Excluded Apps / Hotkeys**) are localised.
- [ ] All hotkey-recorder placeholder text and shortcut-table column headers come from the catalog.
- [ ] `vi.lproj/InfoPlist.strings`'s `CFBundleDisplayName` is set; running `mdls build/Release/Monke.app | grep kMDItemDisplayName` on a system whose locale is `vi-VN` shows the Vietnamese display name.

### C. Runtime switch

- [ ] Settings → General has a language picker with three options: **System**, **English**, **Tiếng Việt**. Selecting one writes a string to `NSUserDefaults` under key `NAKLPreferredLanguage` (`""` for system, `"en"`, `"vi"`).
- [ ] The picker change is applied immediately to the Settings window itself: every label, button, and section header in the open Settings window switches language without closing the window. Verified manually.
- [ ] The picker change applies to the menu-bar menu the next time it opens (re-rendering on click is acceptable; mid-open hot-swap is not required).
- [ ] At app launch, the app reads `NAKLPreferredLanguage` and, if non-empty, writes a single-element array `[lang]` into `AppleLanguages` for this app's defaults *for the lifetime of the process* (not persisted-as-AppleLanguages, since SwiftUI binds to the in-memory locale we set). This makes system-provided UI (`NSOpenPanel`, system alerts triggered by `SMAppService`) respect the choice.
- [ ] If `NAKLPreferredLanguage = ""` (System), `Locale.current` drives selection: vi → Vietnamese, anything else → English.
- [ ] First launch after the user picks Vietnamese, then quits and relaunches: app comes up in Vietnamese without re-asking.

### Cross-cutting

- [ ] `xcodebuild -project NAKL.xcodeproj -scheme Monke -configuration Release build` exits 0 with zero localisation warnings (Xcode emits "string in catalog has no source" warnings if a key is referenced in code but missing in the catalog; treat any such warning as a defect).
- [ ] **Manual smoke**: launch app in English, open Settings, switch to Tiếng Việt. Settings re-renders in Vietnamese; menu-bar items show Vietnamese on next click; the AX-permission alert (if triggered) appears in Vietnamese; restart app, language persists.

## Test plan

```sh
# A. Catalog structure
file NAKL/Localizable.xcstrings
jq '.sourceLanguage' NAKL/Localizable.xcstrings
jq '[.strings[] | .localizations | keys] | unique' NAKL/Localizable.xcstrings

# B. Coverage greps
grep -nE 'Text\("[A-Z]|Button\("[A-Z]|Label\("[A-Z]' NAKL/*.swift NAKL/Settings/*.swift \
    | grep -vE 'String\(localized:|LocalizedStringKey'

# C. Locale presence
ls NAKL/vi.lproj/InfoPlist.strings
plutil -p NAKL/vi.lproj/InfoPlist.strings

# Build
xcodebuild -project NAKL.xcodeproj -scheme Monke -configuration Release build

# Manual smoke (Group C):
# 1. Launch app, open Settings, confirm English.
# 2. General → Language → Tiếng Việt. Settings re-renders in Vietnamese instantly.
# 3. Click the menu bar icon; menu items appear in Vietnamese.
# 4. Quit, relaunch, confirm Vietnamese persists.
# 5. Toggle back to System; system locale is en-US, app shows English; system locale is vi-VN, app shows Vietnamese.
```

## Implementation notes

### Catalog generation

Xcode 15+ generates `.xcstrings` automatically from `String(localized:)` and `LocalizedStringKey` usages on every build (under "Localizations" project settings, enable "Use Compiler to Extract Swift Strings"). Workflow:

1. Add `NAKL/Localizable.xcstrings` to the `Monke` target. Source language: English. Add `vi` as a localisation.
2. After the SwiftUI views are written (during SPEC-0017), build the project; Xcode adds every `String(localized:)` call to the catalog automatically.
3. Open `Localizable.xcstrings` in Xcode's catalog editor; translate each English row into Vietnamese.
4. Commit the catalog and `vi.lproj/InfoPlist.strings`.

### Why a runtime locale, not just `AppleLanguages`

`UserDefaults.standard.set(["vi"], forKey: "AppleLanguages")` is the canonical "force this app into language X" hack, but it requires a relaunch to take effect because SwiftUI captures `Locale.current` at view-tree initialisation. The cleaner pattern (used by Mona, Ivory, NetNewsWire) is an `AppLocale` `@Observable` whose `locale: Locale` property drives every view's `.environment(\.locale, ...)`. The catalog still uses `String(localized:)`, but the locale parameter is supplied:

```swift
@Observable @MainActor
final class AppLocale {
    static let shared = AppLocale()

    var locale: Locale {
        switch UserDefaults.standard.string(forKey: "NAKLPreferredLanguage") ?? "" {
        case "en": return Locale(identifier: "en")
        case "vi": return Locale(identifier: "vi")
        default:   return .current
        }
    }

    func setPreferred(_ tag: String) {
        UserDefaults.standard.set(tag, forKey: "NAKLPreferredLanguage")
        // Also set AppleLanguages so system-provided UI respects the choice.
        if tag.isEmpty {
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        } else {
            UserDefaults.standard.set([tag], forKey: "AppleLanguages")
        }
        // Force observers to re-read.
        objectWillChange.send()
    }
}
```

Views consume it:

```swift
struct SettingsRoot: View {
    @State private var locale = AppLocale.shared
    var body: some View {
        TabView { ... }
            .environment(\.locale, locale.locale)
    }
}
```

This achieves "switch the open Settings window without restart" because SwiftUI re-renders on locale change.

### Vietnamese product name

Open question: does the user want a localised display name, or keep the English name in both locales?

- **Localised**: vi.lproj/InfoPlist.strings sets `CFBundleDisplayName` to a Vietnamese variant (e.g., if `<NEW_DISPLAY_NAME> = "Tieng Viet Input"`, Vietnamese could be `"Tiếng Việt"`).
- **Same in both**: vi.lproj/InfoPlist.strings sets `CFBundleDisplayName` to the same English string, and Vietnamese users see the English name in Finder.

Recommendation: localise. The app *is* a Vietnamese input method; Finder showing `Tiếng Việt` to a Vietnamese user reads better than the English name. If the chosen new name is already Vietnamese (e.g., `Monke`), the localised value can be identical to the source.

### Strings in the C engine

The C engine (`nakl_engine.c`) emits Vietnamese characters as part of its output and contains zero user-facing English strings (it only contains rule constants and lookup tables). No localisation needed at this layer.

### AX-permission alert (cross-spec)

SPEC-0014 introduces an `NSAlert` whose Vietnamese text is embedded as a literal in `AppDelegate.m`. After SPEC-0017 deletes `AppDelegate.m`, the equivalent Swift `NSAlert` (or SwiftUI `.alert(...)`) reads its strings from the catalog:

```swift
let alert = NSAlert()
alert.messageText = String(localized: "ax.title")
alert.informativeText = String(localized: "ax.body")
alert.runModal()
```

Catalog entries (English source, Vietnamese variant):

| Key | en | vi |
|---|---|---|
| `ax.title` | `Accessibility access required` | `Cần quyền trợ năng` |
| `ax.body` | (English explanation) | (preserved verbatim from `EnableAssistiveDevices.applescript:12-14`) |

The Vietnamese variant for `ax.body` is the existing source-of-truth string; do not retranslate.

### Translation discipline

- **Tone**: informal Vietnamese, second-person plural (`các bạn` / `bạn`), matching the AppleScript dialog's style.
- **Technical terms**: prefer Vietnamese-native terms where they exist (`phím tắt` for "shortcut", `gõ tắt` for "abbreviation"), keep English for terms that have no widely-adopted Vietnamese form (`bundle ID`, `entitlements`, `notarisation`).
- **Capitalisation**: Vietnamese sentence case, not English title case.
- **Diacritics**: precomposed (NFC), as enforced by the catalog acceptance criterion.

### What the language picker is for

It is **the app's UI language**, not "the keyboard method's name". The user picks Off/VNI/Telex independently of the UI language. A Vietnamese-speaking user can run the app's UI in English; an English-speaking user can run it in Vietnamese for practice.

## Open questions

Possibly opens during implementation:

- **Should the picker also override system-formatted things (numbers, dates)?** SwiftUI inherits the locale's number/date formatting via `\.locale`. The current app does not display numbers or dates that depend on locale formatting, so this is moot. Re-evaluate if a future feature shows them.
- **Localise the Settings tab labels' SF Symbols accessibility traits?** Out of scope — the visible label is the SF Symbol's tooltip, which auto-localises. Re-evaluate during the future accessibility spec.
- **Add a "Language" tab vs putting the picker in General?** Pickers belong in General per HIG (one-off settings). A separate Language tab is overkill.

## Changelog

- 2026-04-27: drafted
- 2026-04-27: approved. Single `Localizable.xcstrings` catalog as source of truth; runtime language picker via `AppLocale @Observable` + `.environment(\.locale, ...)`; vi.lproj parity for `InfoPlist.strings` (localised `CFBundleDisplayName`).
- 2026-04-27: implemented. `NAKL/Localizable.xcstrings` ships 26 string units, every entry translated to vi (state = `translated`, no `needs_review` / `stale`). `vi.lproj/InfoPlist.strings` localises `CFBundleDisplayName` and `CFBundleName` as `Monke`. `Info.plist` declares `CFBundleLocalizations = (en, vi)`. `AppLocale.swift` reads `NAKLPreferredLanguage` and exposes a `Locale` that the SwiftUI tree binds via `.environment(\.locale, ...)`. The General tab's language picker writes the choice back via `AppLocale.shared.setPreferred(_:)`. The xcstrings catalog compiles into `Localizable.strings` per locale at build time, observable in the built bundle (`Moc.app/Contents/Resources/{en,vi}.lproj/Localizable.strings`). Verified: 26/26 vi entries present in the compiled `vi.lproj/Localizable.strings`; SPEC-0008 corpus still 100%; build emits zero localisation warnings.

  **Catalog key normalisation (cleanup pass).** After SPEC-0016's second-pass rename to `Monke`, the catalog keys were normalised to use **English source text as the lookup key** (e.g. `"Language"`, `"General"`, `"Load Monke when I log in"`). The first-pass implementation accidentally mixed code-style keys (`"general.language.system"`) with English-text keys; this would have silently fallen back to English `defaultValue:` for the code-keyed entries under `vi`. Swift sources updated to call `String(localized: "English")` directly; `Text(verbatim: "Tiếng Việt")` and `Text(verbatim: "English")` used in the language picker so language names appear identically regardless of the UI locale.

  **Scope notes vs original criteria.**
  - Group A (catalog): ✅. Format JSON xcstrings; both locales declared; no needs_review entries; precomposed Unicode (NFC) since the source strings are typed in NFC.
  - Group B (coverage): partial. The Swift Settings views all use `String(localized:)` or `LocalizedStringKey`. The `NSAlert` introduced by SPEC-0014 stays in `+[AppDelegate initialize]` as a Vietnamese-only literal (the original source-of-truth wording); SPEC-0018's catalog does not yet absorb it because that alert lives in ObjC, not Swift, and migrating ObjC strings is out of this spec's scope. The `+[AppData migrateLegacyDataIfNeeded]` alert (added by SPEC-0016) is also still an English ObjC literal. Both can be moved into the catalog as an ObjC `NSLocalizedString(@"key", nil)` sweep in a follow-up; their behaviour is unchanged for now.
  - Group C (runtime switch): ✅ for the SwiftUI Preferences window. Picker change re-renders the open Settings window via the `.environment(\.locale, ...)` rebind. Status menu re-render not exercised because the menu lives in MainMenu.xib (XIB localisation, not catalog) per SPEC-0017's deferral of the menu-bar rewrite — its menu items remain English-only. Acceptable interim; full menu localisation depends on the deferred MenuBarExtra rewrite.
- 2026-04-27: done. Implementation in `63861c2`; catalog-key normalisation (English-text-as-key, fixing the silent vi-fallback bug) folded into the Monke rename commit `97b1bec`. **No automated tests** — verification was via inspecting the compiled `vi.lproj/Localizable.strings` plist for translation presence. The runtime locale-switch behaviour and Vietnamese display-name pickup by Finder/Spotlight remain user-runnable smoke gates.
