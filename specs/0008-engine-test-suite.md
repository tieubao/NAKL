# SPEC-0008: XCTest target with golden corpus

**Status:** approved
**Owner:** @tieubao
**Depends on:** SPEC-0007
**Blocks:** SPEC-0009

## Problem

Once the Vietnamese transformation engine is a pure module (per SPEC-0007), it can be unit-tested. There is currently no XCTest target in the project, no fixtures, and no way to detect regressions in the transformation algorithm. This becomes critical before SPEC-0009 (IMK rewrite), where any subtle behaviour change between engines would silently break Vietnamese typing.

## Goal

Add an XCTest target that drives `nakl_engine_*` against a golden TSV corpus of Telex and VNI input/output pairs (≥200 cases combined), with a ≥95% pass rate, integrated into `xcodebuild test`.

## Non-goals

- Testing AppKit-side glue (event-tap callback, status item, hotkey registration). Those remain manual smoke tests.
- Property-based testing or fuzzing. Possible follow-up spec.
- 100% coverage. Aim is correctness on a representative corpus, not coverage metrics.

## Acceptance criteria

- [ ] New Xcode test target `NAKLEngineTests`, type `Unit Testing Bundle`, host `NAKL.app`, deployment target 12.0.
- [ ] `tests/EngineTests/TelexGoldenTests.m` and `tests/EngineTests/VniGoldenTests.m` exist.
- [ ] `tests/EngineTests/fixtures/telex-corpus.tsv` contains ≥150 cases.
- [ ] `tests/EngineTests/fixtures/vni-corpus.tsv` contains ≥50 cases.
- [ ] `tests/EngineTests/fixtures/passthrough-corpus.tsv` contains ≥10 cases (method = OFF, output equals input).
- [ ] Each corpus line: `input<TAB>expected<TAB>note` where `note` is optional commentary or rule reference.
- [ ] Pass rate ≥95% across all three corpora. Failures are explicitly marked `# known-divergence: SPEC-XXXX` in the corpus, never silently skipped.
- [ ] `xcodebuild test -project NAKL.xcodeproj -scheme NAKL -destination 'platform=macOS' -only-testing:NAKLEngineTests` exits 0.
- [ ] Test runs complete in <5 seconds locally. Slower means the test loop is wrong (e.g. spinning up an engine per case instead of per file).

## Test plan

```bash
xcodebuild test -project NAKL.xcodeproj -scheme NAKL \
    -destination 'platform=macOS' -only-testing:NAKLEngineTests \
    2>&1 | tee /tmp/nakl-test.log

# Pass-rate sanity: count XCTFail lines, divide by case total
grep -c "Test Case .* passed" /tmp/nakl-test.log
grep -c "Test Case .* failed" /tmp/nakl-test.log

# Corpus minimums
[ "$(grep -cv '^#\|^$' tests/EngineTests/fixtures/telex-corpus.tsv)" -ge 150 ]
[ "$(grep -cv '^#\|^$' tests/EngineTests/fixtures/vni-corpus.tsv)"   -ge  50 ]
[ "$(grep -cv '^#\|^$' tests/EngineTests/fixtures/passthrough-corpus.tsv)" -ge 10 ]
```

## Implementation notes

### Test driver shape

```objc
// TelexGoldenTests.m
- (void)testTelexCorpus {
    NSURL *fixture = [[NSBundle bundleForClass:[self class]]
                      URLForResource:@"telex-corpus" withExtension:@"tsv"];
    NSString *raw = [NSString stringWithContentsOfURL:fixture
                                              encoding:NSUTF8StringEncoding error:nil];
    int line = 0, total = 0, passed = 0;
    for (NSString *row in [raw componentsSeparatedByString:@"\n"]) {
        line++;
        if ([row hasPrefix:@"#"] || row.length == 0) continue;
        NSArray<NSString*> *cols = [row componentsSeparatedByString:@"\t"];
        if (cols.count < 2) continue;
        NSString *input = cols[0], *expected = cols[1];
        total++;
        NSString *got = nakl_apply_string(NAKL_TELEX, input);
        if ([got isEqualToString:expected]) {
            passed++;
        } else {
            XCTFail(@"line %d: '%@' -> got '%@' expected '%@'",
                    line, input, got, expected);
        }
    }
    XCTAssertGreaterThanOrEqual((passed * 100) / total, 95);
}
```

### `nakl_apply_string` helper

A test-only helper in `tests/EngineTests/Helpers/nakl_test_helpers.{h,m}`:

1. Creates an engine with the given method.
2. Iterates input UTF-16 codepoints.
3. For each, calls `nakl_engine_add_key`. If the call returns `>0`, reset the accumulator's last `n` characters (per the engine's backspace protocol) and append the replay.
4. Returns the resulting `NSString *`.

This mirrors what `KeyHandler` does on the event-tap thread, in pure userspace.

### Corpus construction

| Source | Method | Count target | Notes |
|---|---|---|---|
| Hand-written canonicals from xvnkb docs | Telex | 50 | One per published rule. |
| Vietnamese paragraph fixtures (Wikipedia public domain) | Telex | 80 | Real prose; generates the long tail. |
| Edge cases (consonant clusters, double tones, capitalisation) | Telex | 30 | Historically buggy area. |
| VNI canonicals + edge cases | VNI | 50 | Distinct ruleset; build last. |
| Passthrough (OFF mode) | OFF | 10 | Output must equal input. |

Reuse public-domain prose only; do not include copyrighted text.

### Pass threshold

`≥95%` not `100%` because xvnkb itself has known divergent behaviour for a handful of edge cases, and the original NAKL implementation may or may not match every one. Fail-listed cases must be marked explicitly in the corpus comment column so they surface in code review and link back to a future spec.

## Open questions

- Add a quick fuzz target (10K random ASCII strings, assert engine doesn't crash)? Cheap to write and valuable for SPEC-0009. Defer to follow-up unless trivial in this spec.
- Should the test target also link `KeyboardHandler.{h,m}` and verify the Objective-C wrapper? Recommend yes, one tiny smoke test, to confirm wrapper does not introduce divergence.

## Changelog

- 2026-04-27: drafted and approved
