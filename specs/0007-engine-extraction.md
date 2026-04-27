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
