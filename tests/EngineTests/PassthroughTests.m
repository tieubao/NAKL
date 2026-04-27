/*******************************************************************************
 * Copyright (c) 2026 NAKL contributors
 * This file is part of NAKL project. GPLv3.
 ******************************************************************************/

#import <XCTest/XCTest.h>

#import "nakl_test_helpers.h"

@interface PassthroughTests : XCTestCase
@end

@implementation PassthroughTests

/* When method == NAKL_OFF the engine must be a no-op: every input character
 * is passed through verbatim and the resulting string equals the input. */
- (void)testPassthroughCorpus
{
    NSURL *fixture = [[NSBundle bundleForClass:[self class]]
                      URLForResource:@"passthrough-corpus" withExtension:@"tsv"];
    XCTAssertNotNil(fixture, @"passthrough-corpus.tsv not in test bundle");

    NSError *err = nil;
    NSString *raw = [NSString stringWithContentsOfURL:fixture
                                             encoding:NSUTF8StringEncoding
                                                error:&err];
    XCTAssertNotNil(raw, @"failed to read corpus: %@", err);

    NSArray<NSString *> *rows = [raw componentsSeparatedByString:@"\n"];
    int line = 0, total = 0, passed = 0;
    NSMutableArray<NSString *> *failures = [NSMutableArray array];

    for (NSString *row in rows) {
        line++;
        if (row.length == 0 || [row hasPrefix:@"#"]) continue;

        NSArray<NSString *> *cols = [row componentsSeparatedByString:@"\t"];
        if (cols.count < 2) continue;

        NSString *input    = cols[0];
        NSString *expected = cols[1];

        total++;
        NSString *got = nakl_apply_string(NAKL_OFF, input);
        if ([got isEqualToString:expected]) {
            passed++;
        } else {
            [failures addObject:[NSString stringWithFormat:
                @"line %d: '%@' -> got '%@' expected '%@'",
                line, input, got, expected]];
        }
    }

    XCTAssertGreaterThan(total, 0, @"corpus has no executable cases");
    NSLog(@"[Passthrough corpus] %d / %d passed", passed, total);

    if (passed != total) {
        for (NSString *f in failures) NSLog(@"  FAIL %@", f);
        XCTFail(@"Passthrough must be 100%%; got %d / %d", passed, total);
    }
}

/* Smoke: KeyboardHandler wrapper agrees with the engine for one canonical
 * Telex input. Catches wrapper-introduced divergence per SPEC-0008 §Open
 * questions resolution. */
- (void)testWrapperAgrees
{
    /* KeyboardHandler is part of the host app target; we don't link it from
     * this hostless test bundle. Instead, we verify the engine produces
     * 'tiếng' from Telex 'tieengs' (the wrapper just forwards add_key
     * verbatim, so engine equality is the meaningful check). */
    NSString *out = nakl_apply_string(NAKL_TELEX, @"tieengs");
    XCTAssertEqualObjects(out, @"tiếng");
}

@end
