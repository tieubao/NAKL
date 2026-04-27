# Source artwork

Reference originals. **Not in the build.**

These four files were the legacy bundle resources before SPEC-0006 introduced the asset catalog (`NAKL/Images.xcassets`) and SPEC-0012 removed them from `project.pbxproj`. They are kept here so future re-export or design iterations can start from the original artwork rather than reverse-engineering it from `Assets.car`.

| File | Original use |
|---|---|
| `NAKL.icns` | App icon (pre-asset-catalog `.icns` form) |
| `icon.png` | App icon at 1024x1024 |
| `icon24.png` | Status-bar icon, "VI" state |
| `icon_blue_24.png` | Status-bar icon, "EN" state |

Status-bar imagesets shipped today live at `NAKL/Images.xcassets/StatusBarVI.imageset` and `StatusBarEN.imageset`, derived from `icon24.png` and `icon_blue_24.png` via `sips` at 18@1x and 36@2x.

If you regenerate `Assets.car` content from these files, update both this README and the relevant spec changelog.
