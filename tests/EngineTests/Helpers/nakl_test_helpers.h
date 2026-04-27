/*******************************************************************************
 * Copyright (c) 2026 NAKL contributors
 * This file is part of NAKL project. GPLv3.
 ******************************************************************************/

/*
 * Test-side helpers around nakl_engine. The engine itself stays pure C, so
 * the corpus runners (TelexGoldenTests, VniGoldenTests, PassthroughTests)
 * use these to: (a) drive the engine through one input string, (b) collapse
 * its replay protocol back into a final NSString.
 *
 * nakl_apply_string mirrors what AppDelegate's KeyHandler does on the
 * event-tap thread in pure userspace: per ASCII byte, call
 * nakl_engine_add_key, treat any returned replay as backspace+append on a
 * virtual document. Returns the resulting Vietnamese text.
 */

#import <Foundation/Foundation.h>

#import "nakl_engine.h"

NS_ASSUME_NONNULL_BEGIN

/* Run `input` (interpreted as a sequence of UTF-16 BMP keystrokes) through
 * a fresh engine in `method` mode and return the resulting string. */
NSString *nakl_apply_string(nakl_method_t method, NSString *input);

NS_ASSUME_NONNULL_END
