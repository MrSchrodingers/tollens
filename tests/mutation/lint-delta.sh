#!/usr/bin/env bash
# MUTACAO DO NUCLEO QUE JULGA O DELTA.
#
# Esta suite existe porque o ADR 0042 AFIRMAVA que mutantes sobre as decisoes centrais morriam, e
# a afirmacao era falsa como escrita: os mutantes foram rodados A MAO no shell, nunca versionados.
# O `refutador` apontou: "nao ha tests/mutation/lint-delta*; nao reproduzivel". Citacao nao
# conferida dentro do documento que explica uma correcao - a classe que o ADR 0011 registra.
#
# Cada mutante ataca UMA decisao do desenho. Um mutante que sobrevive nao e curiosidade: significa
# que a suite unitaria aprova um nucleo que decide errado naquela dimensao.
set -uo pipefail
. "$(dirname "$0")/../lib/lock.sh"
cd "$(dirname "$0")/../.." || exit 1
# ARENA: muta uma COPIA da arvore, nunca a arvore candidata. Backup-e-restaura no `trap` garante
# EventuallyRestored, que NAO implica NeverObservableAsMutant - um SIGTERM no meio deixa o mutante
# no disco, e e isso que `tests/unit/arnes-de-mutacao.sh` AM3 mede. Este arnes nasceu sem a arena
# e a suite o pegou: "todo arnes de mutacao carrega a arena (got=lint-delta.sh want=nenhum)".
. "$(dirname "$0")/../lib/arena.sh"
ALVO="evidence/lint-delta.py"
SUITE="tests/unit/lint-delta.sh"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/mut-ld.XXXXXX")"; trap 'rm -rf "$TMP"' EXIT
cp "$ALVO" "$TMP/orig.py"
P=0; F=0

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$SUITE" >/dev/null 2>&1; then echo "  PASS  baseline verde"; P=$((P+1))
else echo "  FAIL  baseline VERMELHO - todo 'MORTO' abaixo seria sem sentido"; exit 1; fi

mutante(){  # $1=id  $2=decisao atacada  $3=sed
  cp "$TMP/orig.py" "$ALVO"
  if ! sed -i "$3" "$ALVO" 2>/dev/null || cmp -s "$TMP/orig.py" "$ALVO"; then
    cp "$TMP/orig.py" "$ALVO"
    echo "  FAIL  $1 NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); return
  fi
  if ! python3 -c "import ast,sys;ast.parse(open('$ALVO').read())" 2>/dev/null; then
    cp "$TMP/orig.py" "$ALVO"; echo "  FAIL  $1 gerou sintaxe invalida - mutante inutil"; F=$((F+1)); return
  fi
  bash "$SUITE" >/dev/null 2>&1; rc=$?
  cp "$TMP/orig.py" "$ALVO"
  if [ "$rc" -ne 0 ]; then echo "  PASS  $1 morto ($2)"; P=$((P+1))
  else echo "  FAIL  $1 SOBREVIVEU - a suite aprova um nucleo que decide errado em: $2"; F=$((F+1)); fi
}

echo "== mutacao: cada decisao do desenho, atacada =="
mutante MLD1 "classificacao quebra-vs-higiene" 's/^        quebra = d\["code"\] in codigos_de_quebra$/        quebra = False/'
mutante MLD2 "a catraca tolera o que esta no baseline" 's/(tolerados if fp in baseline else bloqueiam)/(bloqueiam)/'
mutante MLD3 "a catraca NAO tolera o que esta fora" 's/(tolerados if fp in baseline else bloqueiam)/(tolerados)/'
mutante MLD4 "escopo por hunk: a linha tem de cair na faixa" 's/return any(ini <= linha <= fim for ini, fim in faixas)/return True/'
mutante MLD5 "escopo por hunk: fora da faixa NAO bloqueia" 's/return any(ini <= linha <= fim for ini, fim in faixas)/return False/'
mutante MLD6 "exclusao de checkout aninhado" 's/^    return any(caminho == r or/    return False and any(caminho == r or/'
mutante MLD7 "digital ignora a linha (sobrevive a deslocamento)" 's/base = f"{caminho}\\x00{codigo}\\x00{normaliza(mensagem)}"/base = f"{caminho}"/'
mutante MLD8 "numero da mensagem vira # (nao gera falso-novo)" 's/_NUM.sub("#", msg or "")/(msg or "")/'
mutante MLD9 "prefixo absoluto removido do caminho" 's/reg\["path"\] = reg\["path"\]\[len(prefixo):\]/pass/'

echo
# O contador anterior derivava MORTOS de P, entao MUTANTES e MORTOS saiam SEMPRE iguais: com
# um sobrevivente imprimiria "MUTANTES=8 MORTOS=8 SOBREVIVENTES=1" para 9 mutantes. Numero que
# nao pode discordar do outro nao mede nada.
echo "MUTANTES=$((P-1+F)) MORTOS=$((P-1)) SOBREVIVENTES=$F"
if [ "$F" -eq 0 ]; then echo "mutacao verde: todo mutante morreu no caso correspondente"; exit 0; fi
echo "mutacao VERMELHA: ha decisao do nucleo que a suite nao protege"; exit 1
