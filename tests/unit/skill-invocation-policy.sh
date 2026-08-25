#!/usr/bin/env bash
# Narrow policy oracle: the known GitHub-mutating workflow must be user-triggered, while a
# read-oriented skill remains eligible for routing. This is deliberately NOT a lexical classifier
# for every possible side effect; it protects the two decisions actually made by this PR.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

frontmatter(){ sed -n '1,/^---$/p' "$1"; }

ISSUES="execution/skills/prd-to-issues/SKILL.md"
GRAPH="execution/skills/graphify/SKILL.md"

chk "prd-to-issues exists" "$([ -f "$ISSUES" ] && echo sim)" sim
chk "prd-to-issues really contains the remote write this policy protects" \
    "$(grep -q 'gh issue create' "$ISSUES" && echo sim || echo nao)" sim
chk "prd-to-issues is manual-only" \
    "$(frontmatter "$ISSUES" | grep -c '^disable-model-invocation: true$' || true)" 1

# Negative control. The PR is not allowed to solve routing risk by disabling every Skill.
chk "graphify remains available to model routing" \
    "$(frontmatter "$GRAPH" | grep -c '^disable-model-invocation: true$' || true)" 0

echo
printf 'PASS=%s FAIL=%s\n' "$P" "$F"
EXPECTED=4
[ "$P" -eq "$EXPECTED" ] || { echo "CONTAGEM INESPERADA: PASS=$P esperado=$EXPECTED" >&2; exit 1; }
[ "$F" -eq 0 ]
