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

echo "== DE5. '.git' FALSO nao esconde codigo rastreado =="
# C1 do refutador: `find -name .git` casava ARQUIVO vazio - um comando escondia codigo do
# analisador. A derivacao declarada era "diretorio com repositorio proprio".
repo d5
mkdir -p sub; printf 'def f():\n    return jamais\n' > sub/mal.py; git add -A
chk "sem o .git falso: barra" "$(gate)" 2
: > sub/.git
chk "  COM o .git falso: CONTINUA barrando" "$(gate)" 2
chk "  CONTROLE: checkout de verdade e ignorado" \
    "$(rm -f sub/.git; ( cd sub && git init -q . && git add -A 2>/dev/null && git -c user.email=t@t -c user.name=t commit -qm x >/dev/null 2>&1 ); gate)" 0

echo "== DE6. CHANGED grande nao desliga o adaptador (SIGPIPE) =="
# F4 do refutador, e o mutante MV5 sobreviveu ate este caso existir. `printf | grep -q` sob
# `pipefail` devolve 141 quando o grep casa CEDO e sai antes de o printf terminar: o adaptador e
# DESCARTADO EM SILENCIO e o portao sai 0. Depende do DADO - casamento no fim devolve 0, no inicio
# devolve 141 - entao um repo de teste com CHANGED pequeno nunca ve. Em /var/www/amaral-intern-hub
# o CHANGED tem 161 KB, e e de la que vem a maior parte dos registros que abrem esta onda.
repo de6
# O que precisa exceder o buffer do pipe (~65536 B) e o TAMANHO de `git status --porcelain`, nao
# a contagem de arquivos. 400 nomes longos dao 76,8 KB em 108 ms; 9000 nomes curtos dao 126 KB em
# 487 ms - e o arnes de mutacao roda esta suite uma vez por mutante, entao o custo multiplica.
python3 -c "
import pathlib
n = 'n' * 180
for i in range(400): pathlib.Path('%s%04d.txt' % (n, i)).write_text('x')
" 2>/dev/null
printf 'def f():\n    return jamais_definido\n' > aaa.py   # `.py` cedo na ordenacao: dispara o SIGPIPE
chk "CHANGED grande ainda barra quebra (adaptador NAO descartado)" "$(gate)" 2
# O buffer do pipe e ~65536 B: abaixo disso o `printf` cabe inteiro e o SIGPIPE NAO ocorre, entao
# o caso passaria sem exercitar nada. Medido: 4000 arquivos dao 56 KB (insuficiente), 9000 dao
# 126 KB.
chk "  e o CHANGED excede o buffer do pipe (o caso nao e vacuo)" \
    "$([ "$(git status --porcelain | wc -c)" -gt 70000 ] && echo sim || echo nao)" sim

echo "== DE7. upstream inexistente nao vira base por ECO =="
# `git rev-parse --abbrev-ref '@{u}'` ECOA `@{u}` quando nao ha upstream: sai nao-zero, mas o
# `|| true` engolia e a string literal virava BASE, DIFFBASE e SEEDREF. `git archive '@{u}'`
# falhava e a catraca nunca era semeada - silenciosamente. Medido em amaral-intern-hub.
repo de7
git branch --unset-upstream >/dev/null 2>&1
git remote remove origin >/dev/null 2>&1
printf 'def f():\n    return jamais\n' > q.py; git add -A; git commit -qm turno >/dev/null
printf 'y = 2\n' > untracked.py
chk "sem upstream nem remoto: barra e NAO semeia" "$(gate)" 2
chk "  2a parada continua barrando (nao anistiou por base falsa)" "$(gate)" 2
chk "  e nenhum baseline foi gravado" \
    "$(ls "$TMP/de7/bl"/*.json 2>/dev/null | wc -l | tr -d ' ')" 0

echo "== DE8. remoto SEM upstream: base derivada, nao a string ecoada =="
# O caso de /var/www/amaral-intern-hub, e o mutante MV6 sobreviveu ate ele existir. DE7 remove o
# remoto, e ali o eco de `@{u}` nao muda nada. Com remoto presente e branch sem upstream,
# `git rev-parse --abbrev-ref '@{u}'` imprime `@{u}` em stdout e sai nao-zero; o `|| true` engolia
# o codigo e a string LITERAL virava BASE, DIFFBASE e SEEDREF. `git archive '@{u}'` falhava e a
# catraca nunca era semeada - em silencio. E o nome do remoto tambem nao pode ser presumido:
# naquele repositorio chamam-se `debt-hub` e `debthub`, e a lista fixa em `origin/*` nao casava.
repo de8
# A CONDICAO DO ECO E ESPECIFICA, e a primeira versao deste caso nao a reproduzia. `git rev-parse
# --abbrev-ref '@{u}'` so ECOA a entrada quando o upstream esta CONFIGURADO e a ref NAO EXISTE -
# "ambiguous argument". Com upstream simplesmente ausente ele imprime vazio, e o mutante
# sobrevivia. Medido: com a ref presente sai `origin/main`; apagada, sai `@{u}` com rc=128.
git remote rename origin outro-nome >/dev/null 2>&1
printf 'import os\n__all__ = ["nao_existe"]\n' > velho.py; git add -A; git commit -qm divida >/dev/null
git push -q outro-nome HEAD:refs/heads/main >/dev/null 2>&1
# A REF E APAGADA POR ULTIMO: o `push` acima RECRIA `refs/remotes/<remoto>/main`, e com a ref
# presente o `@{u}` resolve e o eco nunca ocorre - foi assim que a primeira versao deste caso
# deixou o mutante MV6 sobreviver. O estado a reproduzir e upstream CONFIGURADO com ref AUSENTE.
git update-ref -d refs/remotes/outro-nome/main >/dev/null 2>&1
printf 'def f():\n    return 1\n' > novo.py; git add -A
chk "upstream configurado com ref AUSENTE: barra" "$(gate)" 2
# Sem base real - upstream aponta para ref que nao existe e nenhum candidato de remoto resolve -
# a resposta honesta e RECUSAR semear. Semear da arvore vazia gravaria um baseline que tolera nada
# e, pelo `[ ! -f ]`, impediria a re-semeadura quando uma base real aparecesse.
chk "  e NAO semeia catraca de uma base falsa" \
    "$(ls "$TMP/de8/bl"/*.json 2>/dev/null | wc -l | tr -d ' ')" 0
chk "  2a parada CONTINUA barrando (nao anistiou por eco)" "$(gate)" 2
# O DISCRIMINANTE E A CAUSA NOMEADA, nao o codigo de saida: com o eco aceito, `SEEDREF` vira a
# string `@{u}`, `git archive` falha e o portao relata "NAO foi possivel semear" - diagnostico
# ERRADO, que manda o operador procurar defeito na semeadura em vez de na base. Com a validacao,
# ele relata "sem base anterior ao turno", que e a causa real. Portao que erra a causa ensina a
# procurar no lugar errado.
chk "  e a causa nomeada e a BASE, nao a semeadura" \
    "$(grep -c 'sem base anterior ao turno' "$TMP/o" "$TMP/e" 2>/dev/null | awk -F: '{s+=$2} END{print (s>0)?1:0}')" 1

EXPECTED=23
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
echo
echo "================ PASS=$P  FAIL=$F ================"
[ "$F" -eq 0 ] && echo "delta ponta a ponta verde ($P/$EXPECTED)" || echo "delta ponta a ponta VERMELHO ($F falhas)"
exit "$F"
