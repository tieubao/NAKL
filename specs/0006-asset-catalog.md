# SPEC-0006: Modern app icon and asset catalog

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0005
**Blocks:** SPEC-0010

## Problem

The app icon (`NAKL/NAKL.icns`, plus `icon.png`, `icon24.png`, `icon_blue_24.png`) was generated at sizes appropriate for macOS 10.5-10.7. Modern macOS requires AppIcon sizes from 16x16 up to 1024x1024 in both @1x and @2x for full Retina support, declared via an `.appiconset` in an asset catalog rather than `.icns`. The status-bar icons are PNGs loaded at runtime via `pathForResource:ofType:`; they are not template images, so they do not adapt to dark mode.

A second cleanup is overdue: `NAKL/Images-2.xcassets/` is a legacy duplicate created by an old Xcode upgrade and is not referenced by the build.

## Goal

Replace `NAKL.icns` with a complete `AppIcon.appiconset`, convert the status-bar icons to template images that respect dark mode, and remove the legacy duplicate asset catalog. Visual identity stays the same.

## Non-goals

- Redesigning the icon. Same artwork.
- Adding alternate icon themes.

## Acceptance criteria

- [ ] `NAKL/Images.xcassets/AppIcon.appiconset/` contains all 10 standard sizes:
  16@1x, 16@2x, 32@1x, 32@2x, 128@1x, 128@2x, 256@1x, 256@2x, 512@1x, 512@2x.
- [ ] `NAKL/Images.xcassets/StatusBarVI.imageset/` and `StatusBarEN.imageset/` exist with @1x + @2x PNGs at 18x18 and 36x36.
- [ ] Status-bar imagesets are marked **template images** (`"template-rendering-intent": "template"` in `Contents.json`).
- [ ] `AppDelegate.m awakeFromNib` loads via `[NSImage imageNamed:@"StatusBarVI"]` / `[NSImage imageNamed:@"StatusBarEN"]` instead of `pathForResource:ofType:`.
- [ ] `NAKL/NAKL.icns` removed from the project.
- [ ] `NAKL/Images-2.xcassets/` removed.
- [ ] Loose PNGs `icon.png`, `icon24.png`, `icon_blue_24.png` removed from the bundle (kept in `assets/source/` if needed for future re-export).
- [ ] Visual smoke: icon looks correct in Finder, Dock, and Cmd-Tab; status-bar icon adapts to light/dark menu bar.

## Test plan

```bash
xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Release clean build

# Verify all icon sizes ended up in Assets.car
xcrun --sdk macosx assetutil --info build/Release/NAKL.app/Contents/Resources/Assets.car \
    | grep -c '"Idiom":"universal"'   # expect >= 12 (10 app icon + 2 status icon)

# Visual smoke
open build/Release/NAKL.app
# 1. Cmd-Tab: full-resolution icon visible.
# 2. Dock: icon crisp on Retina.
# 3. Toggle Dark Mode in System Settings -> Appearance.
#    Status-bar icon must remain legible (template tinting).
# 4. Toggle back to Light Mode.
killall NAKL || true
```

## Implementation notes

- Source artwork: `NAKL/icon.png` (1024x1024 visually). Re-export to required sizes via `sips -z H W input.png --out output.png`.
- Status-bar templates: convert `icon24.png` and `icon_blue_24.png` to monochrome alpha-only PNGs. The system tints them automatically. This means **colour can no longer carry the EN/VI distinction**; use a shape difference instead (e.g. EN = filled, VI = outlined, or two distinct glyph variants). If the call is unclear, ship two distinct shapes rather than colour-coded ones; document the choice in the PR.
- `AppDelegate.m:121-125` currently loads images via `pathForResource:ofType:` with a manual `setSize:`. Replace with `[NSImage imageNamed:]`, which handles @1x/@2x and sizing automatically.
- Confirm `Images-2.xcassets/` is unreferenced before deletion: `grep -r 'Images-2' NAKL.xcodeproj/`. If empty, safe to remove.

## Open questions

- Use shape-variant template images for EN/VI (preferred for dark-mode purity) or break the template convention to keep the original colour scheme? Recommend shape variants. PR documents the decision.

## Changelog

- 2026-04-27: drafted and approved
