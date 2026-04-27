/*******************************************************************************
 * Copyright (c) 2026 NAKL contributors
 * This file is part of NAKL project. GPLv3.
 ******************************************************************************/

#import "nakl_test_helpers.h"

#define DOC_MAX_LEN  1024

NSString *nakl_apply_string(nakl_method_t method, NSString *input)
{
    nakl_engine_t *e = nakl_engine_create(method);
    NSCAssert(e != NULL, @"nakl_engine_create failed");

    UniChar doc[DOC_MAX_LEN];
    int     doc_len = 0;

    UniChar replay[2 * NAKL_WORD_SIZE];

    NSUInteger inputLen = input.length;
    for (NSUInteger i = 0; i < inputLen; i++) {
        UniChar key = [input characterAtIndex:i];
        int n = nakl_engine_add_key(e, key, replay, (int)(sizeof(replay) / sizeof(replay[0])));
        if (n <= 0) {
            if (doc_len < DOC_MAX_LEN) doc[doc_len++] = key;
        } else {
            for (int k = 0; k < n; k++) {
                UniChar ch = replay[k];
                if (ch == '\b') {
                    if (doc_len > 0) doc_len--;
                } else if (doc_len < DOC_MAX_LEN) {
                    doc[doc_len++] = ch;
                }
            }
        }
    }

    nakl_engine_destroy(e);
    return [NSString stringWithCharacters:doc length:(NSUInteger)doc_len];
}
