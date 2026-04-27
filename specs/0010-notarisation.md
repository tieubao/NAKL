# SPEC-0010: Notarised distribution pipeline (deferred draft)

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0005, SPEC-0006
**Blocks:** none

> Implementation scaffolds the pipeline. Final pass-criteria verification (Gatekeeper accepts, stapler validates, fresh-Mac open is clean) requires the user to run the script with their Developer ID credentials; the spec changelog records this hand-off.

## Problem

A personal-use ad-hoc-signed binary (per SPEC-0005) cannot be distributed: Gatekeeper blocks it on first launch with a "cannot verify the developer" prompt that requires right-click → Open or `xattr -dr com.apple.quarantine`. To ship to anyone else (friends, public download), the binary must be signed with a Developer ID Application certificate and notarised through Apple's notary service.

## Goal

Define the build-and-notarise pipeline as a repeatable script + entitlements + signing setup, producing a notarised, stapled DMG that passes Gatekeeper on a fresh Mac without quarantine bypass.

## Non-goals

- Mac App Store submission. Different signing certificate, sandboxing required, out of scope.
- Sparkle / auto-update integration. Possible follow-up spec.
- Notarising the IMK target (SPEC-0009). If both ship, this spec is superseded by a joint notarisation spec.

## Acceptance criteria

Two groups: A is what the implementation can deliver and verify by inspection; B requires the user's Developer ID credentials and runs after the implementation lands.

### A. Pipeline scaffold (verifiable without user credentials)

- [ ] `scripts/notarise.sh` exists, is executable, and:
  - Validates preconditions: presence of a Developer ID Application certificate in the keychain (regex match), presence of a notarytool keychain profile (default name `NAKL_NOTARY`), Info.plist has `CFBundleVersion` and `CFBundleShortVersionString`, hardened runtime enabled in build settings.
  - Builds Release via `xcodebuild -project NAKL.xcodeproj -configuration Release -derivedDataPath build/notarise build`.
  - Re-signs the built `.app` with `codesign --force --options runtime --timestamp --sign "$IDENTITY" --entitlements NAKL/NAKL.entitlements`.
  - Packages a DMG via `hdiutil create -volname NAKL -srcfolder ... -ov -format UDZO`.
  - Submits via `xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait`.
  - Staples via `xcrun stapler staple "$DMG"` and `xcrun stapler staple "$APP"`.
  - On any failure, prints the notary log via `xcrun notarytool log` and exits non-zero.
- [ ] Script reads identity / profile / version from environment variables with documented defaults so the user can override without editing the file. Defaults documented inline in script header.
- [ ] Script is idempotent: rerunning after a successful notarisation does not error or duplicate the artefact (uses an output dir under `build/notarise/dist/` per version tag).
- [ ] Script never references credentials inline (no hard-coded Apple ID, no app-specific password).
- [ ] `shellcheck scripts/notarise.sh` exits 0 (or only warns; no errors). Verified locally.

### B. Live notarisation (user runs after the pipeline lands)

These criteria depend on the user's Developer Program membership and credentials. The implementation prepares the script and entitlements; verification is the user's run.

- [ ] User has an active Apple Developer Program membership and a `Developer ID Application` certificate in their login keychain.
- [ ] Notary credentials stored in a keychain profile (created via `xcrun notarytool store-credentials NAKL_NOTARY`), never in plaintext env vars.
- [ ] `scripts/notarise.sh` runs end-to-end producing `build/notarise/dist/<version>/NAKL.dmg`.
- [ ] `spctl --assess --type execute --verbose=4 build/notarise/dist/<version>/NAKL.app` returns `source=Notarized Developer ID`.
- [ ] `xcrun stapler validate build/notarise/dist/<version>/NAKL.dmg` exits 0.
- [ ] DMG opens cleanly on a fresh Mac (or any machine that has not previously trusted NAKL) without Gatekeeper prompts.

## Test plan

```bash
# Group A (scaffolding, runs locally without credentials):
shellcheck scripts/notarise.sh                    # static check
scripts/notarise.sh --check                       # preconditions only
test -f scripts/notarise.sh && test -x scripts/notarise.sh

# Group B (user runs once with their credentials):
xcrun notarytool store-credentials NAKL_NOTARY    # one-time setup
DEVELOPER_ID="Developer ID Application: <Your Name> (<TEAMID>)" \
NAKL_VERSION="1.5.0" \
scripts/notarise.sh

# Verify on the build host:
spctl --assess --type execute --verbose=4 build/notarise/dist/1.5.0/NAKL.app
xcrun stapler validate build/notarise/dist/1.5.0/NAKL.dmg

# Verify on a fresh Mac:
curl -LO https://github.com/.../releases/download/v1.5.0/NAKL.dmg
hdiutil attach NAKL.dmg && cp -R /Volumes/NAKL/NAKL.app /Applications/
open /Applications/NAKL.app   # no Gatekeeper prompt expected
```

## Implementation notes

- `xcrun notarytool` (modern), not `altool` (deprecated 2023).
- The SPEC-0005 entitlements file (`com.apple.security.automation.apple-events`) is sufficient. NAKL does not load external frameworks, so `com.apple.security.cs.disable-library-validation` is not needed. Hardened Runtime is already on (SPEC-0005).
- The Run Script build phase that compiles `EnableAssistiveDevices.applescript` (per SPEC-0012) runs at build time and the resulting `.scpt` is stapled inside the bundle by the CopyFiles phase; notarisation will sign over it.
- The DMG layout is minimal: a single `NAKL.app` and a symlink to `/Applications/`. No custom background art (would add icon-positioning ceremony for marginal user-facing value).
- Default keychain profile name is `NAKL_NOTARY`. Default identity match pattern is `Developer ID Application:`. Default version is `$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' NAKL/NAKL-Info.plist)`. All overridable via env vars: `NAKL_NOTARY_PROFILE`, `DEVELOPER_ID`, `NAKL_VERSION`.

## Open questions

Resolved at approval:

- **Hosting?** GitHub Releases. Single source of truth, version-tagged, free, integrates with the repo. The `huyphan.github.io/NAKL` page can link to the latest GitHub release rather than hosting the binary itself.
- **DMG vs ZIP?** DMG. Visual drag-to-Applications affordance is worth the small extra ceremony; the script generates one in `hdiutil ... UDZO` (compressed read-only). ZIP can be added later as a CI artefact if needed.
- **Auto-update?** Out of scope for this spec. The Developer ID identity used here is the one Sparkle would also use, so future integration is unblocked.

## Changelog

- 2026-04-27: drafted at status `draft`. Execution gated on the user's decision to share NAKL beyond personal use.
- 2026-04-27: refined and approved. Acceptance criteria split into A (scaffolding, verifiable now) and B (live notarisation, requires user's Developer ID + run). Open questions resolved (GitHub Releases, DMG via UDZO, auto-update deferred). Status flipped to `approved`.
- 2026-04-27: Group A (scaffolding) implemented. `scripts/notarise.sh` (199 lines, GPLv3, executable) lands the full pipeline: precondition checks → Release build → Developer ID re-sign → DMG packaging via `hdiutil ... UDZO` → notary submission via `xcrun notarytool submit --wait` → stapling of both `.app` and `.dmg` → final `spctl --assess` + `stapler validate`. On notary failure, the script auto-fetches and prints the relevant log via `xcrun notarytool log`. Identity / profile / version are env-var overridable with documented defaults; never references credentials inline. `--check` mode runs only the preconditions for fast iteration.

  Verified locally:
  - `shellcheck scripts/notarise.sh` → exit 0.
  - `scripts/notarise.sh --check` → exits 1 with a clear punch list of missing prerequisites (no Developer ID Application identity, no `NAKL_NOTARY` keychain profile on this machine — both expected). The Hardened-Runtime / entitlements / Info.plist (`CFBundleVersion` / `CFBundleShortVersionString` / `CFBundleIdentifier`) checks all pass.

  Group B (live notarisation) is the user's hand-off and remains unverified until run. The user's runbook:

  ```sh
  # one-time setup
  xcrun notarytool store-credentials NAKL_NOTARY
  # provide: Apple ID, app-specific password, Team ID

  # full pipeline (auto-detects identity + version)
  scripts/notarise.sh

  # outputs
  ls build/notarise/dist/<version>/
  # → NAKL.app  NAKL.dmg
  ```

  Once the user produces a stapled DMG, attach it to a GitHub Release tagged `v<version>` per the resolved hosting question. The `huyphan.github.io/NAKL` page can link to that release rather than self-host the binary.
