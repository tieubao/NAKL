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

#import <Foundation/Foundation.h>
#import "Engine/nakl_engine.h"

/* Replay buffer must hold at most one full word's worth of backspaces plus
 * one full word's worth of replacement chars. NAKL_WORD_SIZE comes from the
 * engine header. */
#define NAKL_REPLAY_CAPACITY (2 * NAKL_WORD_SIZE)

@interface KeyboardHandler : NSObject {
    nakl_engine_t *_engine;
    UniChar        _replayBuffer[NAKL_REPLAY_CAPACITY];
    int            _replayLength;
}

@property (nonatomic) int kbMethod;

/* Pointer + length of the most recent replay sequence produced by addKey:.
 * Each element is either '\b' (caller sends a Backspace keycode) or a
 * Unicode character (caller sends as a Unicode-string event). */
@property (nonatomic, readonly) const UniChar *replayBuffer;
@property (nonatomic, readonly) int            replayLength;

- (id) init;

/* Forward to nakl_engine_add_key. Returns the replay-buffer length, or 0 on
 * pass-through (caller should let the original keystroke through). */
- (int) addKey: (UniChar) key;

- (void) clearBuffer;

@end
