# SPEC-0010: Notarised distribution pipeline (deferred draft)

**Status:** draft
**Owner:** @tieubao
**Depends on:** SPEC-0005, SPEC-0006
**Blocks:** none

> ⚠️ This spec is `draft`, not `approved`. Notarisation is deferred until the user decides to share NAKL beyond personal use.

## Problem

A personal-use ad-hoc-signed binary (per SPEC-0005) cannot be distributed: Gatekeeper blocks it on first launch with a "cannot verify the developer" prompt that requires right-click → Open or `xattr -dr com.apple.quarantine`. To ship to anyone else (friends, public download), the binary must be signed with a Developer ID Application certificate and notarised through Apple's notary service.

## Goal

Define the build-and-notarise pipeline as a repeatable script + entitlements + signing setup, producing a notarised, stapled DMG that passes Gatekeeper on a fresh Mac without quarantine bypass.

## Non-goals

- Mac App Store submission. Different signing certificate, sandboxing required, out of scope.
- Sparkle / auto-update integration. Possible follow-up spec.
- Notarising the IMK target (SPEC-0009). If both ship, this spec is superseded by a joint notarisation spec.

## Acceptance criteria (proposed; may change before approval)

- [ ] User has an active Apple Developer Program membership and a `Developer ID Application` certificate in their login keychain.
- [ ] Notary credentials stored in a keychain profile (created via `xcrun notarytool store-credentials`), never in plaintext env vars.
- [ ] `scripts/notarise.sh` exists and:
  - Builds Release configuration.
  - Signs with the Developer ID identity (read from the keychain profile).
  - Creates a DMG via `hdiutil`.
  - Submits via `xcrun notarytool submit --wait`.
  - Staples with `xcrun stapler staple`.
- [ ] `spctl --assess --type execute NAKL.app` returns `accepted: source=Notarized Developer ID`.
- [ ] `xcrun stapler validate NAKL.app` exits 0.
- [ ] DMG opens cleanly on a fresh Mac without quarantine prompts.

## Test plan

To be detailed at approval time. Expected shape:

```bash
./scripts/notarise.sh
# On a clean Mac:
curl -LO https://example.com/NAKL.dmg
hdiutil attach NAKL.dmg
cp -R /Volumes/NAKL/NAKL.app /Applications/
open /Applications/NAKL.app
# Expect: no Gatekeeper prompt; AppleScript permission flow as usual.
```

## Implementation notes

To be detailed at approval time. Expected shape:

- Use `notarytool` (modern), not `altool` (deprecated 2023).
- The `com.apple.security.cs.disable-library-validation` entitlement is sometimes needed for apps loading bundled frameworks; NAKL does not load external frameworks at present, so the SPEC-0005 entitlements file should suffice as-is.
- Hardened Runtime (already enabled in SPEC-0005) is mandatory for notarisation.
- Status-bar app icon, Info.plist completeness (CFBundleVersion, NSHumanReadableCopyright, LSMinimumSystemVersion), and proper deployment target all gate notarisation. Surface these as preconditions in the script.

## Open questions (resolve before approval)

- Hosting: GitHub Releases, the existing `huyphan.github.io/NAKL` page, or both?
- DMG vs ZIP delivery? DMG renders better for end users; ZIP is smaller and simpler.
- Auto-update: out of scope, but the signing identity used here constrains future Sparkle integration.

## Changelog

- 2026-04-27: drafted at status `draft`. Execution gated on the user's decision to share NAKL beyond personal use.
