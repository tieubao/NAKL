#!/bin/bash
# snapshot-engine.sh: build the standalone CLI driver and run the SPEC-0007
# canonical corpus through it. Output is TSV (method<TAB>input<TAB>output)
# suitable for `diff` regression checks. SPEC-0008 will expand this corpus.
#
# Usage:
#   scripts/dev/snapshot-engine.sh                     # canonical corpus
#   scripts/dev/snapshot-engine.sh path/to/corpus.tsv  # custom corpus

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
ENGINE_DIR="$REPO_ROOT/NAKL/Engine"
BIN="${TMPDIR:-/tmp}/nakl-snapshot-engine"

# Compile the CLI driver. -x c forces C (no Objective-C). The engine uses
# constructs from the legacy table headers that need <sys/types.h> for
# `ushort`; the engine .c includes it itself so no extra flag is required.
clang -std=c11 -O0 -g -Wall -x c \
    "$ENGINE_DIR/cli/snapshot-engine.c" \
    "$ENGINE_DIR/nakl_engine.c" \
    -o "$BIN"

CORPUS="${1:-}"
if [[ -n "$CORPUS" ]]; then
    "$BIN" < "$CORPUS"
else
    "$BIN" <<'EOF'
# SPEC-0007 canonical corpus (Test plan §). One row per case:
#   METHOD<TAB>INPUT
# Output appears as METHOD<TAB>INPUT<TAB>OUTPUT.
telex	tieengs vieet
telex	ddoongf laaf
telex	khoong
telex	xin chaof
telex	anh huwowngr
vni	tie61ng vie65t
vni	d9o62ng la2
vni	khong
vni	xin chao2
off	tieengs
EOF
fi
