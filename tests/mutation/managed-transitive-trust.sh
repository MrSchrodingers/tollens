#!/usr/bin/env bash
# Mutation validation for G25. Remove the managed-root binding and require the unit test to fail.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

SUITE="tests/unit/managed-transitive-trust.sh"
SRC="install/hooks-spec.sh"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
P=0; F=0

baseline(){ HOOKS_SPEC="$1" bash "$SUITE" >/dev/null 2>&1; }

baseline "$SRC" || { echo "BASELINE VERMELHO" >&2; exit 1; }
echo "baseline verde"

# M1: make the managed pattern unreachable. The generated managed Read command then falls back
# to the user-style direct hook and the trust-root assertions must fail.
M1="$T/hooks-spec-no-managed.sh"
cp "$SRC" "$M1"
python3 - "$M1" <<'PY'
import pathlib, sys
p=pathlib.Path(sys.argv[1]); t=p.read_text()
old='  */opt/tollens/hooks) MANAGED_ROOT="${BASE%/hooks}" ;;'
new='  */never-matches-managed-hooks) MANAGED_ROOT="${BASE%/hooks}" ;;'
assert t.count(old)==1, t.count(old)
p.write_text(t.replace(old,new))
PY
HOOKS_SPEC="$M1" bash "$SUITE" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ]; then echo "  MORTO M1 - sem binding managed, a suite reprova"; P=$((P+1)); else echo "  SOBREVIVEU M1"; F=$((F+1)); fi

# M2 control: an inert comment must not make the suite red. This prevents a test that merely
# fingerprints bytes from looking mutation-sensitive.
M2="$T/hooks-spec-comment.sh"
cp "$SRC" "$M2"
printf '\n# inert mutation-control\n' >> "$M2"
HOOKS_SPEC="$M2" bash "$SUITE" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ]; then echo "  MORTO-CONTROLE M2 - comentario inerte permanece verde"; P=$((P+1)); else echo "  DIVERGIU CONTROLE M2"; F=$((F+1)); fi

echo "MUTANTES=$((P+F)) CORRETOS=$P DIVERGENTES=$F"
EXPECTED_MUTANTS=2
[ "$((P+F))" -eq "$EXPECTED_MUTANTS" ] || exit 1
[ "$F" -eq 0 ]
