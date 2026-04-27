/*******************************************************************************
 * Copyright (c) 2026 NAKL contributors
 * This file is part of NAKL project. GPLv3.
 ******************************************************************************/

#import <XCTest/XCTest.h>

#import "nakl_test_helpers.h"

@interface VniGoldenTests : XCTestCase
@end

@implementation VniGoldenTests

- (void)testVniCorpus
{
    NSURL *fixture = [[NSBundle bundleForClass:[self class]]
                      URLForResource:@"vni-corpus" withExtension:@"tsv"];
    XCTAssertNotNil(fixture, @"vni-corpus.tsv not in test bundle");

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
        NSString *got = nakl_apply_string(NAKL_VNI, input);
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
    NSLog(@"[VNI corpus] %d / %d passed (%d%%); %d known-divergences skipped",
          passed, total, passRate, divergent);

    if (passRate < 95) {
        for (NSString *f in failures) NSLog(@"  FAIL %@", f);
        XCTFail(@"VNI pass rate %d%% < 95%% threshold", passRate);
    }
}

@end
