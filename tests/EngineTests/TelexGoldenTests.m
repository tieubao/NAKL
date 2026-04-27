/*******************************************************************************
 * Copyright (c) 2026 NAKL contributors
 * This file is part of NAKL project. GPLv3.
 ******************************************************************************/

#import <XCTest/XCTest.h>

#import "nakl_test_helpers.h"

@interface TelexGoldenTests : XCTestCase
@end

@implementation TelexGoldenTests

/* Drives the Telex corpus. Each row: input<TAB>expected[<TAB>note]. Lines
 * starting with `#` are comments. A note containing `known-divergence:` (in
 * column 3) marks an expected mismatch and is excluded from the pass-rate
 * denominator (per SPEC-0008 §Pass threshold).
 *
 * Pass-rate floor: 95% per SPEC-0008. */
- (void)testTelexCorpus
{
    NSURL *fixture = [[NSBundle bundleForClass:[self class]]
                      URLForResource:@"telex-corpus" withExtension:@"tsv"];
    XCTAssertNotNil(fixture, @"telex-corpus.tsv not in test bundle");

    NSError *err = nil;
    NSString *raw = [NSString stringWithContentsOfURL:fixture
                                             encoding:NSUTF8StringEncoding
                                                error:&err];
    XCTAssertNotNil(raw, @"failed to read corpus: %@", err);

    NSArray<NSString *> *rows = [raw componentsSeparatedByString:@"\n"];
    int line = 0, total = 0, passed = 0, divergent = 0;
    NSMutableArray<NSString *> *failures = [NSMutableArray array];

    for (NSString *row in rows) {
        line++;
        if (row.length == 0 || [row hasPrefix:@"#"]) continue;

        NSArray<NSString *> *cols = [row componentsSeparatedByString:@"\t"];
        if (cols.count < 2) continue;

        NSString *input    = cols[0];
        NSString *expected = cols[1];
        NSString *note     = cols.count >= 3 ? cols[2] : @"";

        if ([note containsString:@"known-divergence:"]) {
            divergent++;
            continue;
        }

        total++;
        NSString *got = nakl_apply_string(NAKL_TELEX, input);
        if ([got isEqualToString:expected]) {
            passed++;
        } else {
            [failures addObject:[NSString stringWithFormat:
                @"line %d: '%@' -> got '%@' expected '%@'",
                line, input, got, expected]];
        }
    }

    XCTAssertGreaterThan(total, 0, @"corpus has no executable cases");
    int passRate = total > 0 ? (passed * 100) / total : 0;
    NSLog(@"[Telex corpus] %d / %d passed (%d%%); %d known-divergences skipped",
          passed, total, passRate, divergent);

    if (passRate < 95) {
        for (NSString *f in failures) NSLog(@"  FAIL %@", f);
        XCTFail(@"Telex pass rate %d%% < 95%% threshold", passRate);
    }
}

@end
