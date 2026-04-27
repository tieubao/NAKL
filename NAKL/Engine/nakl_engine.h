/*******************************************************************************
 * Copyright (c) 2012 Huy Phan <dachuy@gmail.com>
 * This file is part of NAKL project.
 *
 * NAKL is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * NAKL is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with NAKL.  If not, see <http://www.gnu.org/licenses/>.
 ******************************************************************************/

/*
 * NAKL Vietnamese transformation engine: pure C, no AppKit, no Foundation,
 * no global mutable state. Every per-session field lives in nakl_engine_t.
 *
 * Per SPEC-0007, an opaque struct + a small public API. Replaces the entangled
 * KeyboardHandler / module-globals split that previously couldn't be unit
 * tested or reused by an IMK target.
 */

#ifndef NAKL_ENGINE_H
#define NAKL_ENGINE_H

#include <stdint.h>
#include <stdbool.h>

/* UniChar is uint16_t on macOS. We avoid pulling in <MacTypes.h> here so the
 * engine compiles cleanly in any C toolchain (including the tiny CLI driver
 * that links it for the snapshot regression test). */
#ifndef NAKL_UNICHAR_DEFINED
#define NAKL_UNICHAR_DEFINED
typedef uint16_t UniChar;
#endif

typedef enum {
    NAKL_OFF   = 0,
    NAKL_VNI   = 1,
    NAKL_TELEX = 2
} nakl_method_t;

typedef struct nakl_engine_s nakl_engine_t;

/* Optional callback: invoked when a second SpaceBar is observed without an
 * intervening clearBuffer. Hands the caller the current word so it can look it
 * up in an external dictionary (e.g. NAKL's shortcut store). On hit, write the
 * replacement text to `out` (capacity `out_capacity`) and return its length;
 * on miss, return 0. The engine handles the surrounding backspaces and the
 * trailing space character itself. */
typedef int (*nakl_shortcut_lookup_fn)(const UniChar *word,
                                       int            word_len,
                                       UniChar       *out,
                                       int            out_capacity,
                                       void          *user_data);

nakl_engine_t *nakl_engine_create(nakl_method_t method);
void           nakl_engine_destroy(nakl_engine_t *e);

void           nakl_engine_set_method(nakl_engine_t *e, nakl_method_t method);
nakl_method_t  nakl_engine_method(const nakl_engine_t *e);

void           nakl_engine_clear(nakl_engine_t *e);

/* Wire up a shortcut-lookup bridge. Pass NULL to disable. The user_data
 * pointer is forwarded to the callback verbatim. */
void           nakl_engine_set_shortcut_lookup(nakl_engine_t          *e,
                                               nakl_shortcut_lookup_fn fn,
                                               void                   *user_data);

/* Process one keystroke.
 *
 * On replay: writes [`\b` * kbPLength][replacement * kbBLength] into `out`
 * and returns kbPLength + kbBLength. Caller iterates `out`, sending a
 * backspace keycode for each `\b` and a Unicode-string event for everything
 * else.
 *
 * On pass-through (the engine has no replacement to suggest): returns 0 and
 * `out` is untouched. Caller should let the original keystroke through.
 *
 * `out_capacity` should be at least 2 * NAKL_WORD_SIZE to avoid truncation;
 * the engine returns 0 if the buffer is too small to hold a candidate replay.
 */
int            nakl_engine_add_key(nakl_engine_t *e,
                                   UniChar        key,
                                   UniChar       *out,
                                   int            out_capacity);

/* Word-buffer size; matches the historical WORDSIZE define. Exposed so tests
 * and the CLI driver can size their replay buffers correctly. */
#define NAKL_WORD_SIZE 32

#endif /* NAKL_ENGINE_H */
