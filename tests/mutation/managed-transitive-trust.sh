#!/usr/bin/env bash
# Mutation validation for G25. The experiment runs in an isolated arena; production tree is never
# observable as a mutant.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
ORIG="execution/hooks/read-budget.sh"
SUITE="tests/unit/managed-transitive-trust.sh"
# shellcheck source=tests/lib/arena.sh
source tests/lib/arena.sh

P=0; F=0
bash "$SUITE" >/dev/null 2>&1 || { echo "BASELINE VERMELHO" >&2; exit 1; }
echo "baseline verde"

BAK="$(mktemp)"; cp "$ORIG" "$BAK"

# M1: make the managed-location branch unreachable. With hostile overrides supplied by the unit
# test, the hook falls back to user/override paths and the oracle must fail.
python3 - "$ORIG" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1]); t=p.read_text()
old='  */opt/tollens/hooks)'
new='  */never-matches-managed/hooks)'
assert t.count(old)==1, t.count(old)
p.write_text(t.replace(old,new))
PY
bash "$SUITE" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then echo "  MORTO M1 - sem classificacao managed, a suite reprova"; P=$((P+1)); else echo "  SOBREVIVEU M1"; F=$((F+1)); fi
cp "$BAK" "$ORIG"

# M2 control: an inert comment must leave the behavior green. This rejects a byte-fingerprint
# oracle that would call any edit a successful mutation kill.
printf '\n# inert mutation-control\n' >> "$ORIG"
bash "$SUITE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then echo "  CONTROLE M2 - comentario inerte permanece verde"; P=$((P+1)); else echo "  DIVERGIU CONTROLE M2"; F=$((F+1)); fi
cp "$BAK" "$ORIG"; rm -f "$BAK"

echo "MUTANTES=$((P+F)) CORRETOS=$P DIVERGENTES=$F"
EXPECTED_MUTANTS=2
[ "$((P+F))" -eq "$EXPECTED_MUTANTS" ] || exit 1
[ "$F" -eq 0 ]
