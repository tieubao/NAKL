/*
 * snapshot-engine: tiny CLI driver that links the pure nakl_engine and runs
 * a corpus of input strings through it, printing input<TAB>output rows for
 * regression diffing per SPEC-0007 § Test plan. Input on stdin, one test per
 * line, format:
 *
 *     METHOD<TAB>INPUT
 *
 * where METHOD is "off", "vni", or "telex". The driver maintains a small
 * virtual cursor (UniChar buffer) per line; for each input character it
 * either appends the original key (pass-through) or applies the engine's
 * replay sequence (kb_p_length backspaces + replacement chars). UTF-16 is
 * downcoded to UTF-8 on stdout.
 *
 * Build (no Xcode target): see scripts/dev/snapshot-engine.sh.
 */

#include "../nakl_engine.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define LINE_MAX_LEN  256
#define DOC_MAX_LEN   1024

/* Append one UTF-16 BMP code point as UTF-8 to fp. */
static void put_utf8(FILE *fp, UniChar ch)
{
    if (ch < 0x80) {
        fputc((int)ch, fp);
    } else if (ch < 0x800) {
        fputc((int)(0xC0 | (ch >> 6)),         fp);
        fputc((int)(0x80 | (ch & 0x3F)),       fp);
    } else {
        fputc((int)(0xE0 | (ch >> 12)),         fp);
        fputc((int)(0x80 | ((ch >> 6) & 0x3F)), fp);
        fputc((int)(0x80 | (ch & 0x3F)),        fp);
    }
}

static nakl_method_t parse_method(const char *s)
{
    if (strcmp(s, "telex") == 0) return NAKL_TELEX;
    if (strcmp(s, "vni")   == 0) return NAKL_VNI;
    return NAKL_OFF;
}

static int run_one(const char *method_str, const char *input)
{
    nakl_method_t method = parse_method(method_str);
    nakl_engine_t *e = nakl_engine_create(method);
    if (!e) return 1;

    UniChar doc[DOC_MAX_LEN];
    int     doc_len = 0;

    UniChar replay[2 * NAKL_WORD_SIZE];

    for (size_t i = 0; input[i] != '\0' && i < LINE_MAX_LEN; i++) {
        UniChar key = (UniChar)(unsigned char)input[i];
        int n = nakl_engine_add_key(e, key, replay, (int)(sizeof(replay) / sizeof(replay[0])));
        if (n <= 0) {
            /* Pass-through: append original key to the virtual document. */
            if (doc_len < DOC_MAX_LEN) doc[doc_len++] = key;
        } else {
            /* Replay sequence: each '\b' deletes one char, others append. */
            for (int k = 0; k < n; k++) {
                UniChar ch = replay[k];
                if (ch == '\b') {
                    if (doc_len > 0) doc_len--;
                } else {
                    if (doc_len < DOC_MAX_LEN) doc[doc_len++] = ch;
                }
            }
        }
    }

    /* Emit one TSV row: method<TAB>input<TAB>output<NL> */
    fputs(method_str, stdout);
    fputc('\t', stdout);
    fputs(input, stdout);
    fputc('\t', stdout);
    for (int i = 0; i < doc_len; i++) put_utf8(stdout, doc[i]);
    fputc('\n', stdout);

    nakl_engine_destroy(e);
    return 0;
}

int main(int argc, char **argv)
{
    (void)argc; (void)argv;

    char line[LINE_MAX_LEN];
    while (fgets(line, sizeof(line), stdin) != NULL) {
        /* Strip trailing newline. */
        size_t len = strlen(line);
        while (len > 0 && (line[len - 1] == '\n' || line[len - 1] == '\r')) {
            line[--len] = '\0';
        }
        if (len == 0 || line[0] == '#') continue;     /* skip blank / comment */

        char *tab = strchr(line, '\t');
        if (!tab) {
            fprintf(stderr, "skip: missing tab in: %s\n", line);
            continue;
        }
        *tab = '\0';
        const char *method_str = line;
        const char *input      = tab + 1;
        run_one(method_str, input);
    }
    return 0;
}
