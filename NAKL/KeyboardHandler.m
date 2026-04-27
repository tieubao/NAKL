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
 * Thin Objective-C wrapper around the pure-C nakl_engine. Per SPEC-0007 this
 * file owns no transformation state or algorithm; everything lives in
 * Engine/nakl_engine.{h,c}. The wrapper exists to:
 *
 *   1. Bridge nakl_engine_t lifecycle to the AppDelegate-owned `kbHandler`
 *      singleton (so AppDelegate keeps using `[kbHandler addKey:]` etc).
 *   2. Provide the engine's shortcut-lookup callback with access to
 *      AppData.shortcutDictionary, which the engine itself cannot see
 *      because it has no Foundation dependency.
 *   3. Expose the replay buffer as a property AppDelegate can iterate.
 */

#import "KeyboardHandler.h"
#import "AppData.h"

/* Bridge: nakl_engine asks for a shortcut substitution, we hand back the
 * NSDictionary lookup result (or 0 on miss). user_data is unused; AppData is
 * a singleton. */
static int nakl_kbh_shortcut_lookup(const UniChar *word,
                                    int            word_len,
                                    UniChar       *out,
                                    int            out_capacity,
                                    void          *user_data)
{
    (void)user_data;
    if (word_len <= 0) return 0;

    NSString *lastWord = [NSString stringWithCharacters:word length:(NSUInteger)word_len];
    NSString *text     = [[AppData sharedAppData].shortcutDictionary objectForKey:lastWord];
    if (text == nil) return 0;

    NSUInteger len = [text length];
    if (len == 0 || (int)len > out_capacity) return 0;

    [text getCharacters:out range:NSMakeRange(0, len)];
    return (int)len;
}

@implementation KeyboardHandler

- (id) init
{
    if ((self = [super init])) {
        _engine = nakl_engine_create(NAKL_OFF);
        if (!_engine) {
            return nil;
        }
        nakl_engine_set_shortcut_lookup(_engine, nakl_kbh_shortcut_lookup, NULL);
        _replayLength = 0;
    }
    return self;
}

- (void) dealloc
{
    if (_engine) {
        nakl_engine_destroy(_engine);
        _engine = NULL;
    }
}

- (int) kbMethod
{
    return (int)nakl_engine_method(_engine);
}

- (void) setKbMethod:(int)kbMethod
{
    nakl_engine_set_method(_engine, (nakl_method_t)kbMethod);
}

- (int) addKey:(UniChar)key
{
    _replayLength = nakl_engine_add_key(_engine, key, _replayBuffer, NAKL_REPLAY_CAPACITY);
    return _replayLength;
}

- (void) clearBuffer
{
    nakl_engine_clear(_engine);
    _replayLength = 0;
}

- (const UniChar *) replayBuffer
{
    return _replayBuffer;
}

- (int) replayLength
{
    return _replayLength;
}

@end
