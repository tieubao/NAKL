# SPEC-0005: Hardened Runtime and local code signing

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0004
**Blocks:** SPEC-0010

## Problem

The build now produces a Universal binary (per SPEC-0002) and is ARC-clean (per SPEC-0004), but it is not signed with Hardened Runtime. macOS 12+ requires Hardened Runtime for distribution, and more immediately for personal use it determines which entitlements the running binary may request. NAKL needs `com.apple.security.automation.apple-events` to run the bundled `EnableAssistiveDevices.scpt`, and inherits Accessibility / Input Monitoring permissions through TCC. Without an entitlements file declaring intent, future macOS versions may refuse the event tap entirely.

## Goal

Add a minimal entitlements file, enable Hardened Runtime, and confirm "Sign to Run Locally" produces an `.app` that runs and grants the necessary TCC permissions on the user's own machine.

## Non-goals

- Developer ID signing or notarisation. SPEC-0010.
- Mac App Store sandbox. Out of scope; would break the event tap.

## Acceptance criteria

- [ ] `NAKL/NAKL.entitlements` exists and contains:
  - `com.apple.security.automation.apple-events` = `true`
  - No App Sandbox key (deliberate omission).
- [ ] In `project.pbxproj`: `CODE_SIGN_ENTITLEMENTS = NAKL/NAKL.entitlements` (Debug + Release).
- [ ] In `project.pbxproj`: `ENABLE_HARDENED_RUNTIME = YES`.
- [ ] In `project.pbxproj`: `CODE_SIGN_IDENTITY = "-"` (ad-hoc / Sign to Run Locally).
- [ ] `codesign -d --entitlements - build/Release/NAKL.app` lists the apple-events entitlement.
- [ ] `codesign -d -v build/Release/NAKL.app 2>&1` shows `flags=0x10000(runtime)`.
- [ ] `codesign --verify --verbose=2 build/Release/NAKL.app` exits 0.
- [ ] `spctl --assess --type execute build/Release/NAKL.app` returns `rejected` (expected for ad-hoc; documents that distribution requires SPEC-0010).
- [ ] App runs natively on Apple Silicon: `ps -O arch -p $(pgrep NAKL)` shows `arm64`.
- [ ] AppleScript prompt for accessibility runs without crashing on first launch.

## Test plan

```bash
xcodebuild -project NAKL.xcodeproj -scheme NAKL -configuration Release clean build

# Entitlements present
codesign -d --entitlements - build/Release/NAKL.app

# Hardened runtime flag set
codesign -d -v build/Release/NAKL.app 2>&1 | grep -q "flags=0x10000(runtime)"

# Ad-hoc signature valid
codesign --verify --verbose=2 build/Release/NAKL.app

# Native arch (Apple Silicon host)
open build/Release/NAKL.app
sleep 1
ps -O arch -p $(pgrep NAKL) | tail -1 | grep -q arm64
killall NAKL || true
```

## Implementation notes

- Entitlements file (`NAKL/NAKL.entitlements`):
  ```xml
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>com.apple.security.automation.apple-events</key>
      <true/>
  </dict>
  </plist>
  ```
- Do NOT add `com.apple.security.cs.allow-unsigned-executable-memory`, `disable-library-validation`, or `allow-jit`. None are needed and each weakens hardening.
- Do NOT add the App Sandbox key. CGEventTap requires unsandboxed execution.
- Accessibility and Input Monitoring are TCC, not entitlements; they appear in System Settings → Privacy & Security after first launch.

## Open questions

- This entitlements file is reused by the notarised build (SPEC-0010). If SPEC-0009 ever ships, the IMK target gets its own entitlements; this one stays for the menu-bar app.

## Changelog

- 2026-04-27: drafted and approved
- 2026-04-27: implemented. `NAKL/NAKL.entitlements` created with `com.apple.security.automation.apple-events`. Target build settings: `CODE_SIGN_ENTITLEMENTS = NAKL/NAKL.entitlements` and `ENABLE_HARDENED_RUNTIME = YES` for both Debug and Release. `CODE_SIGN_IDENTITY = "-"` was already set in SPEC-0002. Verified: `flags=0x10002(adhoc,runtime)`, apple-events entitlement embedded, `codesign --verify` exit 0, `spctl` returns rejected (expected for ad-hoc; documents the gate to SPEC-0010 notarisation). Xcode also auto-injects `com.apple.security.get-task-allow=true` for ad-hoc builds; this is Apple's default for unsigned development builds and goes away under Developer ID signing.
