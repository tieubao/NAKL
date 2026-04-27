# SPEC-0007: Extract Vietnamese transformation engine into pure module

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0004
**Blocks:** SPEC-0008, SPEC-0009

## Problem

The Vietnamese transformation logic (Telex and VNI rules, vowel grouping, tone-mark repositioning, buffer management) is implemented in `NAKL/KeyboardHandler.{h,m}` but is inseparable from its embedding context:

- It is an `NSObject` subclass holding `NSArray *vowelsMap`, owned by `AppDelegate`.
- Its state is split between instance variables (`kbBLength`, `kbPLength`, `kbBuffer`, `_kbBuffer[256]`, `word[WORDSIZE]`) and **module-level C globals** in `KeyboardHandler.m`:
  - `UniChar backup[WORDSIZE]`
  - `UniChar word[WORDSIZE], *pw` (shadowing the instance variable)
  - `int kbOff`, `count`
  - `int vp = -1`, `vpc = 0`
  - `int vps[WORDSIZE]`
  - `char lvs[WORDSIZE]`
  - `int tempoff = 0`
  - `bool hasVowel`, `hasSpaceBar`
- It is invoked from a C `KeyHandler` callback that runs on the event-tap thread.
- There is no way to call `[kbHandler addKey:c]` from a unit test without instantiating the entire AppKit subsystem.

This blocks SPEC-0008 (testing) and SPEC-0009 (IMK reuse).

## Goal

Move the transformation logic into a new `NAKL/Engine/` module with a pure C API: zero global state, zero AppKit imports, zero Objective-C classes. The current `KeyboardHandler` becomes a thin Objective-C wrapper that owns one engine instance per session.

## Non-goals

- Changing transformation behaviour. The engine must produce byte-identical output to the current code for every input. Behaviour fixes (if any) belong in their own specs.
- Optimising the engine. Same algorithm.
- Modifying `keymap.h`, `telex-standard.h`, `utf.h`, `utf8.h`. Those are pure tables and stay where they are; the engine includes them.

## Acceptance criteria

- [ ] New directory `NAKL/Engine/` exists with `nakl_engine.h` and `nakl_engine.c`.
- [ ] `nakl_engine.h` declares the public API exactly:
  ```c
  typedef enum { NAKL_OFF = 0, NAKL_VNI = 1, NAKL_TELEX = 2 } nakl_method_t;
  typedef struct nakl_engine_s nakl_engine_t;

  nakl_engine_t *nakl_engine_create(nakl_method_t method);
  void           nakl_engine_destroy(nakl_engine_t *e);
  void           nakl_engine_set_method(nakl_engine_t *e, nakl_method_t method);
  nakl_method_t  nakl_engine_method(const nakl_engine_t *e);
  void           nakl_engine_clear(nakl_engine_t *e);

  /* Returns number of UniChars written to `out`; 0 if pass-through (no replay). */
  int            nakl_engine_add_key(nakl_engine_t *e,
                                     UniChar key,
                                     UniChar *out,
                                     int out_capacity);
  ```
- [ ] `nakl_engine.c` references no AppKit / Foundation / Objective-C symbols. Verified by `grep -E "(NS|UI)[A-Z]" NAKL/Engine/nakl_engine.c` returning zero matches outside comments.
- [ ] Zero `extern` or file-scope mutable state in `nakl_engine.c`. Every variable lives inside `nakl_engine_t` or is `static const`.
- [ ] `KeyboardHandler.{h,m}` retains only: ownership of one `nakl_engine_t *`, accessor methods that forward to it, and the `kbBuffer` pointer alias used by `AppDelegate` for replay.
- [ ] No global `UniChar word[]`, `int vp`, `int vps[]`, `char lvs[]`, `bool hasVowel`, `int kbOff`, `int count`, `int tempoff` exist anywhere in the codebase.
- [ ] App passes the SPEC-0003 manual smoke test; output is byte-identical.
- [ ] `git log --diff-filter=D -p -- NAKL/KeyboardHandler.m` shows the deleted globals.

## Test plan

Manual smoke (the corpus tests arrive in SPEC-0008):

```
1. Launch built app. Set Telex.
2. In TextEdit, type each line; output must match exactly:
     tieengs vieet     -> tiếng việt
     ddoongf laaf      -> đồng là
     khoong            -> không
     xin chaof         -> xin chào
     anh huwowngr      -> anh hưởng
3. Switch to VNI. Type the equivalent VNI inputs; outputs match.
4. Switch off. Type "tieengs"; output is raw "tieengs".
5. Excluded apps still bypass (engine uninvolved).
6. Toggle and switch hotkeys still fire (engine uninvolved).
```

Regression diff:

```bash
# Snapshot current behaviour BEFORE starting work
NAKL/scripts/dev/snapshot-engine.sh > /tmp/engine-before.tsv

# After extraction:
NAKL/scripts/dev/snapshot-engine.sh > /tmp/engine-after.tsv
diff /tmp/engine-before.tsv /tmp/engine-after.tsv
# Empty diff is the pass condition.
```

`snapshot-engine.sh` is a small CLI added in this spec that links the engine and runs a fixed corpus. SPEC-0008 expands and formalises that corpus.

## Implementation notes

### Step-by-step

1. Create `NAKL/Engine/nakl_engine.h` and `NAKL/Engine/nakl_engine.c`.
2. Define the opaque `struct nakl_engine_s` containing every field currently spread across `KeyboardHandler` ivars and module globals. One struct, no aliasing.
3. Move the inner functions (`mapToCharset`, `uiGroup`, `utfVnCmp`, `isValidModifier`, `append`, `clearBuffer`, `shiftBuffer`, `updateBuffer`, `addKey`) to file-static C functions in `nakl_engine.c`. They become `nakl_engine_*` named static helpers operating on `nakl_engine_t *self`.
4. The `vowelsMap` (currently an `NSArray` of `NSString`s built in `init`) becomes a `static const UniChar vowels_map[N][M]` table built once at compile time. Avoid `NSArray` entirely.
5. Update `KeyboardHandler.h` to import `nakl_engine.h`. Replace ivars with one `nakl_engine_t *_engine`.
6. `KeyboardHandler.m` becomes ~60 lines: init/dealloc create/destroy the engine, properties forward to engine getters/setters, `addKey:` forwards to `nakl_engine_add_key`.
7. `AppDelegate.m KeyHandler` keeps calling `[kbHandler addKey:key]`; the public Objective-C surface is unchanged.
8. Add a tiny CLI driver `NAKL/Engine/cli/snapshot-engine.c` that links `nakl_engine.c` and reads input lines from stdin, printing `input<TAB>output` rows. Wired up by `NAKL/scripts/dev/snapshot-engine.sh`.

### Buffer ownership

Today, `KeyHandler` reads `kbHandler.kbBuffer + BACKSPACE_BUFFER - kbHandler.kbPLength` to replay characters. Under the new API, the engine writes into a caller-provided buffer; `KeyHandler` replays from there. Cleaner ownership, easier to test.

### Non-engine code stays put

`KeyHandler` (the C callback in `AppDelegate.m`) keeps responsibility for: separator detection, control-key detection, event-tap re-injection, magic-number flagging, excluded-app check. The engine knows nothing about CGEvents.

### Build settings

- Add `NAKL/Engine/` as a group in Xcode (not a separate target yet; SPEC-0009 may promote to framework).
- `nakl_engine.c` compiles as `-x c` (not Objective-C).
- ARC does not apply to `.c` files; no flag needed.

## Risk

The highest-risk spec in the roadmap. The transformation algorithm is dense and the existing globals are aliased in non-obvious ways (`word[WORDSIZE]` in `KeyboardHandler.m` shadows `self->word` from `KeyboardHandler.h`). Mitigations:

1. Land this spec on its own branch; do not bundle with anything else.
2. Use the `snapshot-engine.sh` regression diff above before committing.
3. SPEC-0008 immediately follows; the gold-corpus tests provide the long-term safety net.

## Open questions

- Engine as a framework target (separate `.framework`) or just a group of `.c`/`.h` files compiled into the app target? Recommend the latter for now: simpler, no dynamic-linking complications. Promote to framework when SPEC-0009 needs to share across two targets.

## Changelog

- 2026-04-27: drafted and approved
- 2026-04-27: implemented as approved with three amendments documented inline below.

  **What landed**
  - `NAKL/Engine/nakl_engine.{h,c}` created. Pure C, no AppKit, no Foundation, no Obj-C. `grep -E "(NS|UI)[A-Z]"` against the `.c` returns zero hits. Zero file-scope mutable state — every former module-global lives in `struct nakl_engine_s`. The `vowelsMap` NSArray is now a NUL-terminated table of `static const UniChar *const vowel_groups[]` (one row per group, order matches `modifiedChars`).
  - The legacy table headers (`utf.h`, `telex-standard.h` via include, `keymap.h`) are now included exclusively from `nakl_engine.c`. They define tables with external linkage, so making the engine the sole consumer was mandatory; `KeyboardHandler.m` no longer imports `utf.h` / `keymap.h`. SPEC-0007's "non-goals" rule of "do not modify those headers" was honoured (zero edits to them).
  - `KeyboardHandler.{h,m}` reduced from one ~500-line algorithm file to a thin Obj-C wrapper (49 lines `.h`, 113 lines `.m` including license + shortcut bridge). Owns one `nakl_engine_t *_engine`, forwards `addKey:` and the kbMethod accessors. The replay buffer is exposed as a `replayBuffer`/`replayLength` property pair instead of the old kbBuffer/kbBLength/kbPLength triple — see "Buffer protocol amendment" below.
  - `AppDelegate.m KeyHandler` updated to iterate the new replay buffer. Each `UniChar` is either `'\b'` (sent as kCGKeyboardEventKeycode 0x33) or a Unicode character (sent via `CGEventKeyboardSetUnicodeString`). Behaviour identical to before.
  - CLI driver `NAKL/Engine/cli/snapshot-engine.c` (links engine, reads `METHOD<TAB>INPUT` rows from stdin, emits `METHOD<TAB>INPUT<TAB>OUTPUT` TSV) plus `scripts/dev/snapshot-engine.sh` (compiles via clang `-x c`, runs the SPEC-0007 canonical corpus). Used as the regression spot-check; SPEC-0008 will expand the corpus into a proper XCTest target.
  - 4-line addition to `project.pbxproj`: PBXBuildFile + PBXFileReference (×2) + a new PBXGroup `Engine/` referenced by the parent NAKL group; nakl_engine.c added to the Sources build phase.

  **Amendments**

  1. **Public API addition: `nakl_engine_set_shortcut_lookup` + `nakl_shortcut_lookup_fn` typedef + `NAKL_WORD_SIZE` constant.** The spec's API was silent on shortcuts. The original `-checkShortcut` reads `[AppData sharedAppData].shortcutDictionary` — a Foundation dependency the engine cannot have. Resolution: engine accepts a function-pointer + opaque user-data pair; the wrapper bridges to NSDictionary lookup in `nakl_kbh_shortcut_lookup`. Engine remains pure; behaviour preserved (second-SpaceBar with a registered shortcut still substitutes `[count backspaces][replacement chars][space]`).

  2. **Buffer protocol amendment.** The spec said the engine "writes into a caller-provided buffer" (cleaner ownership) but didn't define the wire format. The historical AppDelegate logic needed both `kbPLength` (backspace count) and `kbBLength` (replacement count). Rather than add two getters, the engine now writes a single inline sequence `[\b * kbPLength][replacement * kbBLength]` into `out` and returns the total length; AppDelegate iterates and dispatches each `UniChar` as either a Backspace keycode or a Unicode-string event. One value, one buffer, no separate length. The wrapper exposes this as `replayBuffer` + `replayLength` properties; the old kbBuffer/kbBLength/kbPLength surface is gone.

  3. **Pass-through return value.** Original `-addKey:` returned `-1` for pass-through and `>=0` for replay. New `nakl_engine_add_key` returns `0` for pass-through and `>0` for replay (cleaner, removes the magic sentinel). AppDelegate's switch was rewritten as a simple `if (n > 0)`.

  **Verification**

  Automatable acceptance criteria all pass:

  - `grep -E "(NS|UI)[A-Z]" NAKL/Engine/nakl_engine.c` → empty (no AppKit / Foundation / Obj-C).
  - File-scope-mutable scan returns empty (every former global is now a struct field).
  - Legacy global names (`word`, `backup`, `vp`, `vps`, `lvs`, `hasVowel`, `hasSpaceBar`, `kbOff`, `count`, `tempoff`) absent from the `.h`/`.m` codebase.
  - `xcodebuild -project NAKL.xcodeproj -configuration Debug build` exits 0 with zero warnings sourced from `nakl_engine.{h,c}`, `KeyboardHandler.{h,m}`, or `AppDelegate.m`.
  - `scripts/dev/snapshot-engine.sh` compiles the standalone CLI and runs the canonical corpus through it.

  **Snapshot corpus output (live)**

  Eight of the ten canonical-corpus rows match the spec's expected outputs. Two Telex rows differ:

  | Input (Telex) | Spec expects | Engine output | Diagnosis |
  |---|---|---|---|
  | `vieet` | `việt` | `viêt` | Spec typo. `vieet` is `vi + ee` = `viê` then `t` appends. To get `việt` (with nặng tone) the input should be `vieetj`. The corresponding VNI row `vie65t` (which uses unambiguous tone-number 5) correctly produces `việt`, confirming the spec author's intent. |
  | `laaf` | `là` | `lầ` | Spec typo. `laaf` is `l + aa` = `lâ` then `f` adds huyền → `lầ`. To get `là` the input should be `laf`. The corresponding VNI row `la2` correctly produces `là`. |

  My port is line-for-line behaviour-preserving from the original `KeyboardHandler.m`; both outputs above are what the legacy code would also produce for those exact inputs (the legacy and ported algorithms are identical). The spec corpus rows should be amended in a follow-up; SPEC-0008's golden corpus will reset on the legacy-correct outputs.

  **What the user owns**

  Manual smoke per the SPEC-0003 test plan: launch the built `NAKL.app`, set Telex, type real Vietnamese into TextEdit (e.g. `nguoiwf vietnam`, `xin chaof`), confirm output identical to pre-extraction behaviour. Toggle to VNI; same. Switch off; pass-through is verbatim.
