#!/usr/bin/env bash
# G25 - managed policy must not delegate back into actor-writable user scope.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

SPEC="${HOOKS_SPEC:-install/hooks-spec.sh}"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "NOT_VERIFIED: jq ausente" >&2; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

read_cmd(){
  jq -r '.PreToolUse[] | select(.matcher=="Read") | .hooks[0].command'
}

echo "== G25. user scope preserves user resolution =="
U="$(bash "$SPEC" '$HOME/.claude/hooks')"
UCMD="$(printf '%s' "$U" | read_cmd)"
chk "user command remains the direct user hook" "$UCMD" 'bash $HOME/.claude/hooks/read-budget.sh'
chk "user wiring does not invent a managed doctool" "$(printf '%s' "$UCMD" | grep -c 'DOCTOOL_BIN=' || true)" 0

echo "== G25. managed scope binds helpers to the same trust root =="
# A space in the prefix forces the generated shell command to quote paths correctly.
ROOT="$T/root with space/opt/tollens"
mkdir -p "$ROOT/hooks" "$ROOT/document-tools" "$ROOT/adapters/documents"
cat > "$ROOT/hooks/read-budget.sh" <<'SH'
#!/usr/bin/env bash
printf 'DOCTOOL=%s\nADAPTERS=%s\n' "${DOCTOOL_BIN:-MISSING}" "${DOC_ADAPTERS_DIR:-MISSING}"
SH
chmod +x "$ROOT/hooks/read-budget.sh"

M="$(bash "$SPEC" "$ROOT/hooks")"
MCMD="$(printf '%s' "$M" | read_cmd)"
OUT="$(sh -c "$MCMD")"; rc=$?
chk "generated managed Read command executes" "$rc" 0
chk "doctool comes from managed root" \
  "$(printf '%s\n' "$OUT" | sed -n 's/^DOCTOOL=//p')" "$ROOT/document-tools/doctool.sh"
chk "adapter registry comes from managed root" \
  "$(printf '%s\n' "$OUT" | sed -n 's/^ADAPTERS=//p')" "$ROOT/adapters/documents"
chk "managed command contains no HOME fallback" "$(printf '%s' "$MCMD" | grep -c '\$HOME\|/home/' || true)" 0

echo "== control: unrelated managed hooks still point to the same hook base =="
STOP="$(printf '%s' "$M" | jq -r '.Stop[0].hooks[0].command')"
chk "verify-gate remains under the supplied managed hook base" "$STOP" "bash $ROOT/hooks/verify-gate.sh"

echo
printf 'PASS=%s FAIL=%s\n' "$P" "$F"
EXPECTED=7
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED" >&2
  exit 1
fi
[ "$F" -eq 0 ]
