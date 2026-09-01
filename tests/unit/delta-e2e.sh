#!/usr/bin/env bash
# PONTA A PONTA DO RAMO `scope: delta`, atraves do HOOK - nao do nucleo.
#
# POR QUE ESTA SUITE EXISTE. O `refutador` fez a pergunta de contramortem - "se isto estivesse
# errado do jeito mais plausivel, o que pegaria?" - e a resposta era NADA: o nucleo tinha 35 casos
# e cobertura de 99,2%, mas o EXECUTOR nao tinha nenhum. Quatro caminhos em que o portao APROVAVA
# EM SILENCIO sobreviveram a seis suites verdes e a CI completa, porque todos moravam no shell
# entre o analisador e o nucleo.
#
# Cada caso aqui e um desses quatro, mais os controles que os separam de "portao desligado".
set -uo pipefail
. "$(dirname "$0")/../lib/lock.sh"
cd "$(dirname "$0")/../.." || exit 1
GATE="$PWD/evidence/hooks/verify-gate.sh"
export CLAUDE_ADAPTERS_DIR="$PWD/execution/adapters/code"
command -v ruff >/dev/null 2>&1 || { echo "NAO VERIFICADO: ruff ausente do PATH." >&2; exit 2; }
TMP="$(mktemp -d "${TMPDIR:-/tmp}/d2e.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

repo(){  # $1=nome; cria repo com upstream real, para que DIFFBASE exista
  R="$TMP/$1"; rm -rf "$R"; mkdir -p "$R/rem" "$R/w"
  ( cd "$R/rem" && git init -q --bare . ) >/dev/null 2>&1
  cd "$R/w" || exit 1
  git init -q .; git config user.email t@t; git config user.name t
  echo "x = 1" > a.py; git add -A; git commit -qm base >/dev/null
  git remote add origin "$R/rem" >/dev/null 2>&1
  git push -q -u origin HEAD:refs/heads/main >/dev/null 2>&1
  git branch --set-upstream-to=origin/main >/dev/null 2>&1
  export TOLLENS_BASELINE_DIR="$R/bl"; rm -rf "$R/bl"
}
gate(){ printf '{}' | timeout 120 bash "$GATE" >"$TMP/o" 2>"$TMP/e"; echo $?; }

echo "== DE1. turno que COMMITA a propria quebra NAO e anistiado =="
# A1 do refutador. Semear de HEAD fechava so a variante arvore-suja: com o turno commitado, HEAD
# E o estado do turno e a catraca gravava a digital do defeito recem-criado.
repo d1
printf 'def f():\n    return jamais_definido\n' > q.py; git add -A; git commit -qm "turno commitou" >/dev/null
chk "1a parada barra" "$(gate)" 2
chk "  2a parada CONTINUA barrando (nao virou catraca)" "$(gate)" 2
chk "  e o baseline nao contem a quebra do turno" \
    "$(cat "$TMP/d1/bl"/*.json 2>/dev/null | head -1)" "[]"

echo "== DE2. divida PREEXISTENTE e tolerada, e a NOVA bloqueia =="
# O caso que a onda existe para resolver, e o discriminante que o separa de portao desligado.
repo d2
printf 'import os\n__all__ = ["nao_existe"]\n' > velho.py; git add -A; git commit -qm divida >/dev/null
git push -q origin HEAD:refs/heads/main >/dev/null 2>&1
printf 'def f():\n    return 1\n' > novo.py; git add -A
chk "1a parada cria a catraca e barra uma vez" "$(gate)" 2
chk "  2a parada com a divida preexistente PASSA" "$(gate)" 0
chk "  e a quebra tolerada e REPORTADA, nao calada" \
    "$(grep -c 'QUEBRA PREEXISTENTE TOLERADA' "$TMP/e" 2>/dev/null | head -1)" 1
printf 'def g():\n    return jamais\n' > q2.py; git add -A
chk "  quebra NOVA volta a barrar" "$(gate)" 2

echo "== DE3. analisador que FALHA e LACUNA, nunca aprovacao =="
# A2 do refutador, regressao do G16 dentro do ramo novo: `[ -n "$RAW" ] || RAW='[]'` transformava
# ferramenta morta em "nenhum diagnostico" - isto e, em aprovacao, com ledger `verdict: pass`.
repo d3
mkdir -p bin; printf '#!/bin/sh\nexit 2\n' > bin/ruff; chmod +x bin/ruff
printf 'def f():\n    return 1\n' > novo.py; git add -A
RC=$(PATH="$PWD/bin:$PATH" bash -c "printf '{}' | timeout 120 bash '$GATE' >'$TMP/o' 2>'$TMP/e'; echo \$?")
chk "ferramenta morta nao aprova" "$RC" 2
chk "  e a causa e nomeada (nao 'reprovou')" \
    "$(grep -c 'NAO produziu array JSON' "$TMP/o" "$TMP/e" 2>/dev/null | awk -F: '{s+=$2} END{print (s>0)?1:0}')" 1

echo "== DE4. arquivo NOVO nao rastreado tem a higiene julgada =="
# B1 do refutador: `git diff HEAD` nao ve untracked, mas o analisador o examina - e `Write`/`Edit`
# nao indexam, entao esse e o caso PADRAO de arquivo novo.
repo d4
printf 'import os\n' > untracked.py
chk "untracked com F401 barra" "$(gate)" 2
chk "  CONTROLE: arquivo limpo untracked NAO barra" \
    "$(rm -f untracked.py; printf 'y = 2\n' > limpo.py; gate)" 0

echo "== DE5. `.git` FALSO nao esconde codigo rastreado =="
# C1 do refutador: `find -name .git` casava ARQUIVO vazio - um comando escondia codigo do
# analisador. A derivacao declarada era "diretorio com repositorio proprio".
repo d5
mkdir -p sub; printf 'def f():\n    return jamais\n' > sub/mal.py; git add -A
chk "sem o .git falso: barra" "$(gate)" 2
: > sub/.git
chk "  COM o .git falso: CONTINUA barrando" "$(gate)" 2
chk "  CONTROLE: checkout de verdade e ignorado" \
    "$(rm -f sub/.git; ( cd sub && git init -q . && git add -A 2>/dev/null && git -c user.email=t@t -c user.name=t commit -qm x >/dev/null 2>&1 ); gate)" 0

EXPECTED=14
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
echo
echo "================ PASS=$P  FAIL=$F ================"
[ "$F" -eq 0 ] && echo "delta ponta a ponta verde ($P/$EXPECTED)" || echo "delta ponta a ponta VERMELHO ($F falhas)"
exit "$F"
