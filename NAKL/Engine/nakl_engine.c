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
 * Pure-C port of the Vietnamese transformation engine that previously lived
 * inside KeyboardHandler.m. Behaviour-preserving: every branch of the
 * original algorithm was carried across without rewrites. SPEC-0007 forbids
 * algorithm changes (those belong in their own specs).
 *
 * The historical KeyboardHandler.m stored half its state in instance
 * variables and half in module-level C globals (word[], backup[], vp, vps[],
 * lvs[], hasVowel, hasSpaceBar, kbOff, count, tempoff). Every one of those
 * is now a field of nakl_engine_t. There is no file-scope mutable state.
 *
 * The vowelsMap NSArray-of-NSStrings is now a NUL-terminated table of UniChar
 * pointers (vowel_groups[]). The order of the seven groups matches
 * modifiedChars = "aeiouyd" so isValidModifier can index modifiersMap by the
 * group's first character.
 */

#include "nakl_engine.h"

#include <stdlib.h>
#include <string.h>
#include <sys/types.h>   /* ushort, used by the legacy table headers below */

/* The legacy table headers define structures, helper macros, and large arrays
 * with external linkage. Including them here makes nakl_engine.c the sole
 * compilation unit that owns these symbols; KeyboardHandler.m must not
 * include them anymore (or the linker will complain about duplicates). */
#include "../utf.h"      /* vietcode_t, modifier_t, modes[], modifierKeys[],
                          * modifiersMap[], modifiedChars[], etc.            */
#include "../keymap.h"   /* XK_SpaceBar, XK_BackSpace                       */

/* Forward declarations matching the original KeyboardHandler.m method
 * decomposition; static C functions taking the engine pointer first. */
static void engine_clear(nakl_engine_t *self);
static int  engine_ui_group(UniChar u);
static int  engine_utf_vn_cmp(UniChar u1, UniChar u2);
static bool engine_is_valid_modifier(const nakl_engine_t *self, UniChar c, char key);
static void engine_append(nakl_engine_t *self, UniChar lastkey, UniChar key);
static int  engine_map_to_charset(nakl_engine_t *self,
                                  UniChar       *out,
                                  int            out_capacity,
                                  const UniChar *src,
                                  int            src_count,
                                  int            kb_p_length);

/* Constants lifted verbatim from KeyboardHandler.m. */
#define chr_A 'A'
#define chr_a 'a'
#define chr_D 'D'
#define chr_d 'd'
#define chr_U 'U'
#define chr_u 'u'
#define chr_G 'G'
#define chr_g 'g'
#define chr_Q 'Q'
#define chr_q 'q'

#define LookupChar(t, c) for( ; *t && *t!=c; t++ )

/* These were file-scope constants in KeyboardHandler.m; same role here. */
static const char *const vowels_str     = "AIUEOYaiueoy";
static const char *const consonants_str = "BCDFGHJKLMNPQRSTVWXZbcdfghjklmnpqrstvwxz";

/* Vowel groups, replacing the NSArray vowelsMap. Order MUST match
 * modifiedChars = "aeiouyd"; isValidModifier indexes modifiersMap via the
 * position of the group's first character in that string. */
static const UniChar vowel_group_a[] = {
    utf_a,  utf_a1,  utf_a2,  utf_a3,  utf_a4,  utf_a5,
    utf_a6, utf_a61, utf_a62, utf_a63, utf_a64, utf_a65,
    utf_a8, utf_a81, utf_a82, utf_a83, utf_a84, utf_a85,
    utf_A,  utf_A1,  utf_A2,  utf_A3,  utf_A4,  utf_A5,
    utf_A6, utf_A61, utf_A62, utf_A63, utf_A64, utf_A65,
    utf_A8, utf_A81, utf_A82, utf_A83, utf_A84, utf_A85,
    0
};
static const UniChar vowel_group_e[] = {
    utf_e,  utf_e1,  utf_e2,  utf_e3,  utf_e4,  utf_e5,
    utf_e6, utf_e61, utf_e62, utf_e63, utf_e64, utf_e65,
    utf_E,  utf_E1,  utf_E2,  utf_E3,  utf_E4,  utf_E5,
    utf_E6, utf_E61, utf_E62, utf_E63, utf_E64, utf_E65,
    0
};
static const UniChar vowel_group_i[] = {
    utf_i,  utf_i1,  utf_i2,  utf_i3,  utf_i4,  utf_i5,
    utf_I,  utf_I1,  utf_I2,  utf_I3,  utf_I4,  utf_I5,
    0
};
static const UniChar vowel_group_o[] = {
    utf_o,  utf_o1,  utf_o2,  utf_o3,  utf_o4,  utf_o5,
    utf_o6, utf_o61, utf_o62, utf_o63, utf_o64, utf_o65,
    utf_o7, utf_o71, utf_o72, utf_o73, utf_o74, utf_o75,
    utf_O,  utf_O1,  utf_O2,  utf_O3,  utf_O4,  utf_O5,
    utf_O6, utf_O61, utf_O62, utf_O63, utf_O64, utf_O65,
    utf_O7, utf_O71, utf_O72, utf_O73, utf_O74, utf_O75,
    0
};
static const UniChar vowel_group_u[] = {
    utf_u,  utf_u1,  utf_u2,  utf_u3,  utf_u4,  utf_u5,
    utf_u7, utf_u71, utf_u72, utf_u73, utf_u74, utf_u75,
    utf_U,  utf_U1,  utf_U2,  utf_U3,  utf_U4,  utf_U5,
    utf_U7, utf_U71, utf_U72, utf_U73, utf_U74, utf_U75,
    0
};
static const UniChar vowel_group_y[] = {
    utf_y,  utf_y1,  utf_y2,  utf_y3,  utf_y4,  utf_y5,
    utf_Y,  utf_Y1,  utf_Y2,  utf_Y3,  utf_Y4,  utf_Y5,
    0
};
static const UniChar vowel_group_d[] = {
    utf_d,
    utf_D,
    utf_d9,
    utf_D9,
    utf_vnd,
    0
};
static const UniChar *const vowel_groups[] = {
    vowel_group_a, vowel_group_e, vowel_group_i,
    vowel_group_o, vowel_group_u, vowel_group_y, vowel_group_d,
    NULL
};

/* Engine instance: every per-session field that used to be split between
 * KeyboardHandler ivars and KeyboardHandler.m globals lives here. */
struct nakl_engine_s {
    nakl_method_t method;

    int     count;                /* word length                            */
    UniChar word  [NAKL_WORD_SIZE];
    UniChar backup[NAKL_WORD_SIZE];

    int     kb_off;
    int     tempoff;
    int     vp;                   /* index of current vowel; -1 if none     */
    int     vpc;                  /* vowel-position-count stack pointer     */
    int     vps[NAKL_WORD_SIZE];
    char    lvs[NAKL_WORD_SIZE];

    bool    has_vowel;
    bool    has_space_bar;

    nakl_shortcut_lookup_fn shortcut_fn;
    void                   *shortcut_user;
};

/* ---------------------------------------------------------------------------
 *  Construction / destruction
 * ------------------------------------------------------------------------ */

nakl_engine_t *nakl_engine_create(nakl_method_t method)
{
    nakl_engine_t *e = (nakl_engine_t *)calloc(1, sizeof(*e));
    if (!e) return NULL;
    e->method = method;
    e->vp     = -1;       /* historical initial value (was `int vp = -1`)  */
    return e;
}

void nakl_engine_destroy(nakl_engine_t *e)
{
    free(e);
}

/* ---------------------------------------------------------------------------
 *  Trivial accessors
 * ------------------------------------------------------------------------ */

void          nakl_engine_set_method(nakl_engine_t *e, nakl_method_t m) { e->method = m; }
nakl_method_t nakl_engine_method   (const nakl_engine_t *e)             { return e->method; }
void          nakl_engine_clear    (nakl_engine_t *e)                   { engine_clear(e); }

void nakl_engine_set_shortcut_lookup(nakl_engine_t          *e,
                                     nakl_shortcut_lookup_fn fn,
                                     void                   *user_data)
{
    e->shortcut_fn   = fn;
    e->shortcut_user = user_data;
}

/* ---------------------------------------------------------------------------
 *  engine_clear: matches KeyboardHandler -clearBuffer exactly.
 * ------------------------------------------------------------------------ */

static void engine_clear(nakl_engine_t *self)
{
    self->tempoff       = 0;
    self->count         = 0;
    self->word[0]       = 0;
    self->has_vowel     = false;
    self->has_space_bar = false;
}

/* ---------------------------------------------------------------------------
 *  Vowel lookup helpers, lifted verbatim from KeyboardHandler.m
 * ------------------------------------------------------------------------ */

static int engine_ui_group(UniChar u)
{
    static const UniChar UI[] = {
        utf_U,  utf_U1,  utf_U2,  utf_U3,  utf_U4,  utf_U5,
        utf_u,  utf_u1,  utf_u2,  utf_u3,  utf_u4,  utf_u5,
        utf_U7, utf_U71, utf_U72, utf_U73, utf_U74, utf_U75,
        utf_u7, utf_u71, utf_u72, utf_u73, utf_u74, utf_u75,
        utf_I,  utf_I1,  utf_I2,  utf_I3,  utf_I4,  utf_I5,
        utf_i,  utf_i1,  utf_i2,  utf_i3,  utf_i4,  utf_i5, 0
    };
    const UniChar *ui = UI;
    while (*ui) {
        if (u == *ui++) {
            return (int)(ui - UI);
        }
    }
    return 0;
}

static int engine_utf_vn_cmp(UniChar u1, UniChar u2)
{
    static const UniChar V[] = {
        utf_a, utf_A, utf_a1, utf_A1, utf_a2, utf_A2,
        utf_a3, utf_A3, utf_a4, utf_A4, utf_a5, utf_A5,
        utf_a6, utf_A6, utf_a61, utf_A61, utf_a62, utf_A62,
        utf_a63, utf_A63, utf_a64, utf_A64, utf_a65, utf_A65,
        utf_a8, utf_A8, utf_a81, utf_A81, utf_a82, utf_A82,
        utf_a83, utf_A83, utf_a84, utf_A84, utf_a85, utf_A85,
        utf_e, utf_E, utf_e1, utf_E1, utf_e2, utf_E2,
        utf_e3, utf_E3, utf_e4, utf_E4, utf_e5, utf_E5,
        utf_e6, utf_E6, utf_e61, utf_E61, utf_e62, utf_E62,
        utf_e63, utf_E63, utf_e64, utf_E64, utf_e65, utf_E65,
        utf_o, utf_O, utf_o1, utf_O1, utf_o2, utf_O2,
        utf_o3, utf_O3, utf_o4, utf_O4, utf_o5, utf_O5,
        utf_o6, utf_O6, utf_o61, utf_O61, utf_o62, utf_O62,
        utf_o63, utf_O63, utf_o64, utf_O64, utf_o65, utf_O65,
        utf_o7, utf_O7, utf_o71, utf_O71, utf_o72, utf_O72,
        utf_o73, utf_O73, utf_o74, utf_O74, utf_o75, utf_O75,
        utf_y, utf_Y, utf_y1, utf_Y1, utf_y2, utf_Y2,
        utf_y3, utf_Y3, utf_y4, utf_Y4, utf_y5, utf_Y5,
        utf_u, utf_U, utf_u1, utf_U1, utf_u2, utf_U2,
        utf_u3, utf_U3, utf_u4, utf_U4, utf_u5, utf_U5,
        utf_u7, utf_U7, utf_u71, utf_U71, utf_u72, utf_U72,
        utf_u73, utf_U73, utf_u74, utf_U74, utf_u75, utf_U75,
        utf_i, utf_I, utf_i1, utf_I1, utf_i2, utf_I2,
        utf_i3, utf_I3, utf_i4, utf_I4, utf_i5, utf_I5,
        utf_d9, utf_D9, 0
    };
    int i = -1, j = -1;
    const UniChar *v = V;

    LookupChar(v, u1);
    if (*v) i = (int)(v - V);

    v = V;
    LookupChar(v, u2);
    if (*v) j = (int)(v - V);

    return i - j;
}

/* isValidModifier: replaces the NSArray loop + NSString rangeOfString: with
 * a flat C scan over the vowel_groups[][] table. Behaviour preserved. */
static bool engine_is_valid_modifier(const nakl_engine_t *self, UniChar c, char key)
{
    char *m = modifierKeys[self->method - 1];
    if (65 <= key && key <= 90) {
        key += 32;          /* lowercase */
    }
    char *p = strchr(m, key);
    if (!p) return false;

    for (int g = 0; vowel_groups[g] != NULL; g++) {
        const UniChar *grp = vowel_groups[g];
        for (int k = 0; grp[k] != 0; k++) {
            if (grp[k] == c) {
                /* grp[0] is the group's primary character (utf_a, utf_e, ...);
                 * its position in modifiedChars indexes modifiersMap. */
                char *mc = strchr(modifiedChars, (char)grp[0]);
                if (!mc) return false;       /* defensive: shouldn't happen */
                UniChar v = modifiersMap[self->method - 1][mc - modifiedChars];
                return (1L & (v >> (p - m))) != 0;
            }
        }
    }
    return false;
}

/* engine_append: lifted verbatim from KeyboardHandler -append:: */
static void engine_append(nakl_engine_t *self, UniChar lastkey, UniChar key)
{
    static const char *spchk = "AIUEOYaiueoy|BDFJKLQSVWXZbdfjklqsvwxz|'`~?.^*+=";
    static const char *vwchk = "|ia|ua|oa|ai|ui|oi|au|iu|eu|ie|ue|oe|ye|ao|uo|eo|ay|uy|uu|ou|io|";
    char *sp = strchr((char *)spchk, (char)key);
    int   kp = sp ? (int)(sp - spchk) : -1;

    if (!self->count) {
        if (kp >= 0 && kp < 12) {
            self->vpc        = 1;
            self->vp         = 0;
            self->vps[0]     = -1;
            self->lvs[0]     = (char)key;
        } else {
            if (kp == 12 || kp > 37) {
                return;
            } else {
                self->vp  = -1;
                self->vpc = 0;
            }
        }
    } else {
        if (kp == 12 || kp > 37) {
            engine_clear(self);
            return;
        } else if (kp > 12) {        /* b, d, f, ... */
            self->tempoff = self->count;
        } else if (kp >= 0) {        /* vowels */
            if (!self->has_vowel) {
                self->has_vowel = true;
            } else {
                char *lsp = strchr((char *)spchk, (char)lastkey);
                /* NOTE: original used `sp` (not `lsp`) to gate this index;
                 * preserving the bug-or-feature exactly per non-goal #1. */
                int   lkp = sp ? (int)(lsp - spchk) : -1;
                if ((lastkey < 127) && (lkp > 12) && (lkp < 37)) {
                    self->tempoff = self->count;
                }
            }
            if (self->vp < 0) {
                self->vps[self->vpc++] = self->vp;
                self->vp               = self->count;
                self->lvs[0]           = (char)key;
            } else if (self->count - self->vp > 1) {
                self->tempoff = self->count;
            } else {
#define lower(c) ((c) <= 'Z' ? (c) + 'a' - 'A' : c)
                static char w[5] = { '|', 0, 0, '|', 0 };
                w[1] = (char)lower(self->lvs[self->vpc - 1]);
                w[2] = (char)lower(key);
                if (!strstr(vwchk, w)) {
                    self->tempoff = self->count;
                } else {
                    self->lvs[self->vpc]   = (char)key;
                    self->vps[self->vpc++] = self->vp;
                    self->vp               = self->count;
                }
#undef lower
            }
        } else {
            switch (key) {
                case 'h':
                case 'H': /* [cgknpt]h */
                    if (lastkey > 127 || !strchr("CGKNPTcgknpt", lastkey))
                        self->tempoff = self->count;
                    break;
                case 'g':
                case 'G': /* [n]g */
                    if (lastkey != 'n' && lastkey != 'N')
                        self->tempoff = self->count;
                    break;
                case 'r':
                case 'R': /* [t]r */
                    if (lastkey != 't' && lastkey != 'T')
                        self->tempoff = self->count;
                    break;
                default:
                    if (strchr(consonants_str, (char)lastkey))
                        self->tempoff = self->count;
                    break;
            }
        }
    }
    self->word[self->count++] = key;
}

/* engine_map_to_charset: writes the replay sequence
 * [`\b` * kb_p_length][src * src_count] into out, returning total. Replaces
 * KeyboardHandler -mapToCharset:: which was tied to the old kbBuffer layout. */
static int engine_map_to_charset(nakl_engine_t *self,
                                 UniChar       *out,
                                 int            out_capacity,
                                 const UniChar *src,
                                 int            src_count,
                                 int            kb_p_length)
{
    (void)self;   /* no longer touches engine state; kept for symmetry */

    int total = kb_p_length + src_count;
    if (total > out_capacity) return 0;

    int idx = 0;
    for (int i = 0; i < kb_p_length; i++) out[idx++] = (UniChar)'\b';
    for (int i = 0; i < src_count;   i++) out[idx++] = src[i];
    return total;
}

/* ---------------------------------------------------------------------------
 *  Public addKey: the only externally observable processing entry point.
 *  Algorithm preserved verbatim from KeyboardHandler -addKey:.
 * ------------------------------------------------------------------------ */

int nakl_engine_add_key(nakl_engine_t *e, UniChar key, UniChar *out, int out_capacity)
{
    if (e->method == NAKL_OFF) {
        return 0;
    }

    if (key == XK_SpaceBar) {
        int written = 0;
        if (e->has_space_bar && e->shortcut_fn) {
            /* Shortcut substitution path: equivalent to old -checkShortcut.
             * On hit, build [count backspaces][replacement chars][space] and
             * return total. On miss, fall through to the normal clear. */
            UniChar replacement[NAKL_WORD_SIZE];
            int rep_len = e->shortcut_fn(e->word, e->count,
                                         replacement, NAKL_WORD_SIZE,
                                         e->shortcut_user);
            if (rep_len > 0 && rep_len < NAKL_WORD_SIZE) {
                int kb_p_length = e->count;
                /* Append the trailing space character to the replacement
                 * (the original wrote XK_SpaceBar at word[i] before
                 * mapToCharset). */
                replacement[rep_len] = (UniChar)XK_SpaceBar;
                written = engine_map_to_charset(e, out, out_capacity,
                                                replacement, rep_len + 1,
                                                kb_p_length);
            }
        }
        engine_clear(e);
        e->has_space_bar = true;
        return written;
    }

    int    p = -1;
    int    i, j = -1;
    UniChar c = 0;
    UniChar cc;
    modifier_t *m = modes[e->method - 1];
    vietcode_t *v = NULL;

    if (!e->count || e->tempoff) {
        engine_append(e, c, key);
        return 0;
    }

    c = e->word[p = e->count - 1];

    for (i = 0; m[i].modifier; i++) {
        if (key == m[i].modifier) {
            v = m[j = i].code;
        }
    }

    if (!v) {
        engine_append(e, c, key);
        return 0;
    }

    i = p;

    /* Loop back to find the closest character that can match the current key. */
    while ((i >= 0) && !engine_is_valid_modifier(e, e->word[i], (char)key)) {
        i--;
    }

    if (i < 0) {
        engine_append(e, c, key);
        return 0;
    }

    /* If there's an earlier character we can also match, prefer it. */
    while ((i - 1 >= 0)
           && (strchr(vowels_str, e->word[i - 1]) || e->word[i - 1] > 0x80)
           && (engine_utf_vn_cmp(e->word[i - 1], e->word[i]) < 0)
           && engine_is_valid_modifier(e, e->word[i - 1], (char)key)) {
        i--;
    }

    if (i == e->count - 1 && i - 1 >= 0 && (j = engine_ui_group(e->word[i - 1])) > 0) {
        switch (e->word[i]) {
            case chr_a:
            case chr_A:
                if (((i - 2 < 0)
                     || (((j < 24 && e->word[i - 2] != chr_q && e->word[i - 2] != chr_Q)
                          || (j > 24 && e->word[i - 2] != chr_g && e->word[i - 2] != chr_G))))
                    && engine_is_valid_modifier(e, e->word[i - 1], (char)key)) {
                    i = i - 1;
                }
                break;
            case chr_u:
            case chr_U:
                if (i - 2 < 0 || (e->word[i - 2] != chr_g && e->word[i - 2] != chr_G)) {
                    i = i - 1;
                }
                break;
        }
    }

    /* Bail on long words to avoid mangling foreign-language input. */
    if (p - i >= 20 /* BACKSPACE_BUFFER */) {
        engine_append(e, c, key);
        return 0;
    }

    c = e->word[p = i];

    for (i = 0; (cc = v[i].c) != 0 && c != cc; i++);

    if (!cc) {
        engine_append(e, c, key);
        return 0;
    }

    int kb_p_length = e->count - p;
    if (!v[i].r2) {
        e->word[p]   = v[i].r1;
        e->backup[p] = c;
    } else {
        e->word[e->tempoff = e->count++] = key;
        e->word[p] = e->backup[p];
    }

    return engine_map_to_charset(e, out, out_capacity,
                                 &e->word[p], e->count - p,
                                 kb_p_length);
}
