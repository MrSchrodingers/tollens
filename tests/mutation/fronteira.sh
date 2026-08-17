#!/usr/bin/env bash
# Mutacao da FRONTEIRA EXTERNA. Alvo separado porque a garantia nao vive no gate nem no
# instalador: vive na configuracao que decide qual check-run o ruleset avalia.
#
# Existe porque `tests/unit/fronteira-externa.sh` nasceu VERDE. Uma suite que nunca reprovou nao
# demonstrou discriminar nada - e o defeito exato que este repositorio ja pagou duas vezes
# (docs/adr/0020, regra 2): o unico obstaculo do teste era um hash desalinhado, e ele passava com
# a checagem de posse removida. Aqui cada mutante remove UMA garantia e exige o caso certo morrer.
#
# ALEM DOS MUTANTES, HA UM CONTROLE NEGATIVO. A revisao independente do PR #5 mostrou que a
# primeira versao de FE1 exigia `jobs_decisorios == 1` - isto e, proibia QUALQUER segundo job em
# `pull_request`. Adicionar CodeQL, lint separado ou validacao de Dependabot com contexto proprio
# e legitimo e teria reprovado a suite. Um teste que proibe configuracao legitima nao protege a
# garantia: treina o operador a afrouxa-lo. O controle abaixo exige que a suite CONTINUE VERDE
# diante dessa configuracao - e um mutante sobrevivente ali seria falha, tanto quanto um mutante
# sobrevivente entre os negativos.
#
# MECANICA: a suite aceita `FRONTEIRA_WF_DIR`, entao a mutacao acontece numa COPIA em diretorio
# temporario. O repositorio nunca fica, nem por um instante, com o workflow real quebrado.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
# ARENA: muta uma COPIA da arvore, nunca a arvore candidata. Ver tests/lib/arena.sh para os
# seis incidentes medidos que motivaram isto.
. "$(dirname "$0")/../lib/arena.sh"
SUITE="tests/unit/fronteira-externa.sh"
SRC=".github/workflows"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P=0; F=0; EXPECTED_MUTANTS=7

python3 -c 'import yaml' 2>/dev/null || {
  echo "NAO VERIFICADO: pyyaml ausente - a mutacao da fronteira nao pode ser avaliada." >&2; exit 2; }

echo "== baseline =="
if FRONTEIRA_WF_DIR="$SRC" bash "$SUITE" >/dev/null 2>&1; then
  echo "  PASS  baseline verde"
else
  echo "  FAIL  baseline vermelho; abortando"; exit 1
fi

_prepara(){ local d="$TMP/$1"; rm -rf "$d"; mkdir -p "$d"; cp "$SRC"/*.yml "$d/"; printf '%s' "$d"; }

# $1=id  $2=descricao  $3=comando de mutacao (recebe $D)  $4=trecho esperado no FAIL
mutante(){
  local id="$1" desc="$2" mut="$3" esperado="$4"
  local D; D="$(_prepara "$id")"
  ( D="$D"; eval "$mut" )
  # A MUTACAO FOI APLICADA? Sem esta checagem, um padrao que nao casa produz "mutante morto"
  # por arquivo intacto - falso verde com a forma de rigor.
  if diff -rq "$SRC" "$D" >/dev/null 2>&1; then
    echo "  FAIL  $id NAO FOI APLICADO (padrao nao casa) - $desc"; F=$((F+1)); return
  fi
  local out rc
  out="$(FRONTEIRA_WF_DIR="$D" bash "$SUITE" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  $id SOBREVIVEU - $desc"; F=$((F+1))
  elif printf '%s' "$out" | grep -q "FAIL.*$esperado"; then
    echo "  PASS  $id morto pelo caso certo ($esperado)"; P=$((P+1))
  else
    echo "  FAIL  $id: reprovou, mas nao em '$esperado' - kill nao atribuivel"; F=$((F+1))
    printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'
  fi
}

echo "== mutacao da fronteira externa =="

# MF1: o job de push volta a usar o nome do contexto exigido. E o defeito ORIGINAL medido:
# dois check-runs homonimos sobre o mesmo SHA.
mutante MF1 "colisao de contexto entre push e PR" \
  'sed -i "s/^  verify-push:/  verify-pr:/; s/^    name: verify-push\$/    name: verify-pr/" "$D/verify-push.yml"' \
  "um unico produtor do contexto exigido"

# MF2: o job exigido perde o gatilho de PR. O ruleset passa a exigir um contexto que nenhum
# evento decisorio produz - fail-closed, mas nenhum PR fecha e o motivo nao aparece.
mutante MF2 "o contexto exigido responde a pull_request" \
  'python3 - "$D/verify-pr.yml" <<PY
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("on:\n  pull_request:\n  merge_group:", "on:\n  merge_group:")
open(p,"w").write(s)
PY' \
  "inclui pull_request"

# MF3: os dois workflows divergem no QUE verificam. E o preco de ter dois arquivos; se este
# mutante sobrevive, a duplicacao virou drift silencioso.
mutante MF3 "o workflow de push deixa de rodar a mutacao do gate" \
  'python3 - "$D/verify-push.yml" <<PY
import sys
p=sys.argv[1]; L=open(p).read().split("\n")
i=[k for k,l in enumerate(L) if "tests/mutation/run.sh" in l][0]
del L[i-1:i+1]
open(p,"w").write("\n".join(L))
PY' \
  "contrato de execucao equivalente"

# MF4: o cabecalho manda exigir um contexto que job nenhum produz. O operador configuraria o
# ruleset para algo inexistente, e o PR ficaria pendente para sempre.
mutante MF4 "cabecalho declara um contexto que existe" \
  'sed -i "s/required status check = \"verify-pr\"/required status check = \"verify\"/" "$D/verify-pr.yml"' \
  "um unico produtor do contexto exigido"

# MF5: some `merge_group`. A fila de merge nunca reporta o contexto exigido, e nada sai dela.
# Gatilho sutil: o PR fica verde, a fila trava - sintoma distante da causa.
mutante MF5 "merge_group entre os gatilhos do exigido" \
  'python3 - "$D/verify-pr.yml" <<PY
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("on:\n  pull_request:\n  merge_group:", "on:\n  pull_request:")
open(p,"w").write(s)
PY' \
  "inclui merge_group"

# MF6: o job exigido passa a responder tambem a `push`. Volta a haver dois check-runs com o
# MESMO nome sobre o mesmo SHA - o defeito original, por outro caminho.
mutante MF6 "o exigido NAO responde a push" \
  'python3 - "$D/verify-pr.yml" <<PY
import sys
p=sys.argv[1]; s=open(p).read()
s=s.replace("on:\n  pull_request:\n  merge_group:", "on:\n  pull_request:\n  merge_group:\n  push:")
open(p,"w").write(s)
PY' \
  "NAO responde a push"

# MF7: divergencia FORA de `steps`. Este mutante existe por causa da revisao independente do
# PR #5: a versao anterior de FE3 comparava SOMENTE o array de passos, entao os dois workflows
# podiam rodar os mesmos comandos sob runner, permissoes ou ambiente diferentes e a suite
# continuava verde. "Mesma verificacao" era afirmacao sobre os comandos, nao sobre a execucao.
mutante MF7 "equivalencia cobre o CONTRATO, nao so os passos" \
  'sed -i "s/^  contents: read\$/  contents: write/" "$D/verify-push.yml"' \
  "contrato de execucao equivalente"

echo "== controle negativo: configuracao LEGITIMA nao pode reprovar =="
# A propriedade correta e sobre o CONTEXTO EXIGIDO, nao sobre a populacao de jobs de PR.
D="$(_prepara controle)"
cat > "$D/codeql.yml" <<'YML'
name: codeql
on:
  pull_request:
permissions:
  contents: read
jobs:
  codeql:
    name: codeql
    runs-on: ubuntu-24.04
    steps:
      - run: echo "analise estatica de terceiro, contexto proprio"
YML
out="$(FRONTEIRA_WF_DIR="$D" bash "$SUITE" 2>&1)"; rc=$?
if [ "$rc" -eq 0 ]; then
  echo "  PASS  segundo job em pull_request, com contexto PROPRIO, nao reprova"; P=$((P+1))
else
  echo "  FAIL  a suite reprova configuracao legitima - propriedade forte demais"; F=$((F+1))
  printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'
fi

echo
printf 'mutantes_esperados=%s  mortos=%s  falhas=%s\n' "$EXPECTED_MUTANTS" "$P" "$F"
# O controle negativo conta junto com os mutantes: ele tambem e uma condicao que a suite precisa
# satisfazer, e deixa-lo fora do total faria o numero publicado nao corresponder ao verificado.
ALVO=$((EXPECTED_MUTANTS + 1))
if [ "$F" -eq 0 ] && [ "$P" -eq "$ALVO" ]; then
  echo "mutacao da fronteira verde ($EXPECTED_MUTANTS mutantes + 1 controle negativo)"; exit 0
else
  echo "mutacao da fronteira VERMELHA"; exit 1
fi
