#!/usr/bin/env bash
# MUTACAO DO EXECUTOR NO RAMO `scope: delta`.
#
# Esta suite existe porque o corpus AFIRMAVA que "os tres defeitos reintroduzidos como mutantes NO
# EXECUTOR morrem", e a afirmacao nao era reproduzivel: os mutantes foram rodados a mao e nunca
# versionados. O `refutador` mediu e achou TRES SOBREVIVENTES entre oito. E a mesma falta que a
# entrada vizinha do corpus condena na onda anterior - a acusacao foi corrigida um nivel abaixo e
# reproduzida um nivel acima.
#
# O alvo aqui e o SHELL entre o analisador e o nucleo. Foi ali que moraram TODOS os defeitos de
# aprovacao silenciosa desta onda: o nucleo tinha 35 casos e 99,2% de cobertura, e o executor,
# nenhum.
set -uo pipefail
. "$(dirname "$0")/../lib/lock.sh"
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/arena.sh"
ALVO="evidence/hooks/verify-gate.sh"
SUITE="tests/unit/delta-e2e.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mut-vg.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
cp "$ALVO" "$TMP/orig.sh"
P=0; F=0

echo "== baseline: a suite ponta a ponta precisa passar ANTES de mutar =="
if bash "$SUITE" >/dev/null 2>&1; then echo "  PASS  baseline verde"; P=$((P+1))
else echo "  FAIL  baseline VERMELHO - todo veredito abaixo seria sem sentido"; exit 1; fi

mutante(){  # $1=id  $2=defeito reintroduzido  $3=de  $4=para
  cp "$TMP/orig.sh" "$ALVO"
  # SUBSTITUICAO POR PYTHON, nao por `sed`: os alvos contem `|`, `$`, `\` e aspas, e escapar isso
  # num `sed -i` produziu TRES mutantes que nao aplicaram - e mutante que nao aplica e teste
  # invalido, nao mutante morto. O mesmo motivo pelo qual `install/hooks-spec.sh` trocou `sed` por
  # `jq --arg` depois de uma auditoria.
  python3 - "$ALVO" "$3" "$4" <<'PYEOF' || { cp "$TMP/orig.sh" "$ALVO"; echo "  FAIL  $1 NAO FOI APLICADO - o padrao nao casa. Mutante nao aplicado e teste invalido."; F=$((F+1)); return; }
import sys, pathlib
alvo, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
p = pathlib.Path(alvo); t = p.read_text(encoding="utf-8")
if t.count(de) != 1:
    sys.exit(1)
p.write_text(t.replace(de, para), encoding="utf-8")
PYEOF
  if ! bash -n "$ALVO" 2>/dev/null; then
    cp "$TMP/orig.sh" "$ALVO"; echo "  FAIL  $1 gerou sintaxe invalida - mutante inutil"; F=$((F+1)); return
  fi
  bash "$SUITE" >/dev/null 2>&1; rc=$?
  cp "$TMP/orig.sh" "$ALVO"
  if [ "$rc" -ne 0 ]; then echo "  PASS  $1 morto ($2)"; P=$((P+1))
  else echo "  FAIL  $1 SOBREVIVEU - a suite aprova o executor com: $2"; F=$((F+1)); fi
}

echo "== mutacao: cada defeito de aprovacao silenciosa, reintroduzido =="
mutante MVG1 "A1: catraca semeada do estado ATUAL, anistiando a quebra do turno" \
  'SEEDREF="$DIFFBASE"' 'SEEDREF=HEAD'
mutante MVG2 "A2: analisador morto vira zero diagnosticos, isto e, aprovacao" \
  "if ! printf '%s' \"\$RAW\" | jq -e 'type == \"array\"' >/dev/null 2>&1; then" 'if false; then'
mutante MVG3 "C1: raiz aninhada aceita entrada chamada .git, sem repositorio" \
  'git rev-parse --resolve-git-dir "$_d/.git" >/dev/null 2>&1' 'test -e "$_d/.git"'
mutante MVG4 "B1: arquivo nao rastreado sai dos hunks" \
  "git ls-files --others --exclude-standard 2>/dev/null | sed 's|^|UNTRACKED |'; }" 'true; }'
mutante MVG5 "F4: deteccao de extensao volta ao pipe que toma SIGPIPE" \
  'if case "$_NL$CHANGED$_NL" in *"${ext}${_NL}"*) true ;; *) false ;; esac; then' \
  'if printf "%s\n" "$CHANGED" | grep -q -- "${ext}\$"; then'
mutante MVG6 "upstream aceito por ECO, sem validar o objeto" \
  'if [ -z "$UPSTREAM" ] || ! git -C "$ROOT" rev-parse --verify -q "${UPSTREAM}^{commit}" >/dev/null 2>&1; then' \
  'if false; then'

echo
echo "MUTANTES=$((P-1+F)) MORTOS=$((P-1)) SOBREVIVENTES=$F"
if [ "$F" -eq 0 ]; then echo "mutacao do executor verde: todo defeito reintroduzido morreu"; exit 0; fi
echo "mutacao VERMELHA: ha defeito do executor que a suite nao protege"; exit 1
