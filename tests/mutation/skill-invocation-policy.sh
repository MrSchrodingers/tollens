#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
ORIG="execution/skills/prd-to-issues/SKILL.md"
SUITE="tests/unit/skill-invocation-policy.sh"
# shellcheck source=tests/lib/arena.sh
source tests/lib/arena.sh
P=0; F=0

bash "$SUITE" >/dev/null 2>&1 || { echo "BASELINE VERMELHO" >&2; exit 1; }
BAK="$(mktemp)"; cp "$ORIG" "$BAK"

# M1 removes the manual-only control but leaves the remote write intact.
sed -i '/^disable-model-invocation: true$/d' "$ORIG"
bash "$SUITE" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then echo "  MORTO M1 - side-effect skill voltou ao routing automatico"; P=$((P+1)); else echo "  SOBREVIVEU M1"; F=$((F+1)); fi
cp "$BAK" "$ORIG"

# M2 inert control.
printf '\n<!-- inert-control -->\n' >> "$ORIG"
bash "$SUITE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then echo "  CONTROLE M2 - mudanca inerte permanece verde"; P=$((P+1)); else echo "  DIVERGIU CONTROLE M2"; F=$((F+1)); fi
cp "$BAK" "$ORIG"; rm -f "$BAK"

echo "MUTANTES=$((P+F)) CORRETOS=$P DIVERGENTES=$F"
EXPECTED_MUTANTS=2
[ "$((P+F))" -eq "$EXPECTED_MUTANTS" ] || exit 1
[ "$F" -eq 0 ]
