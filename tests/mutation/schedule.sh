#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - orchestration/schedule.py (docs/adr/0020, regra de metodo 2).
#
# Por que existe: tests/unit/schedule.sh so prova que o validador REJEITA as fixtures F2/F3/F5
# hoje. Isso nao prova que a rejeicao vem da garantia certa - um teste que sobrevive a remocao
# da garantia nao testa a garantia, testa outra coisa (o precedente proprio deste repositorio,
# ADR 0020: um hash desalinhado era o unico obstaculo, e o teste passava com a checagem de posse
# removida). Cada mutante abaixo remove UMA das quatro garantias do modelo (1)(2)(3)+cap e EXIGE
# que tests/unit/schedule.sh reprove no caso especifico que aquela garantia protege.
#
# O MUTANTE CENTRAL e M2: sem a deteccao de escritas sobrepostas, o escalonador vira decoracao -
# aceitaria dois nos escrevendo o mesmo arquivo em paralelo, exatamente o que o mecanismo existe
# para impedir.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
ORIG="orchestration/schedule.py"
REG="tests/unit/schedule.sh"
# ORDEM DO TRAP: restaurar ANTES de remover o diretorio temporario que guarda a copia limpa -
# uma interrupcao no meio do jogo nao pode deixar o mutante instalado no arquivo real
# (defeito ja medido em tests/mutation/run.sh, ver o comentario la).
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.py" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.py"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=4

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

# `troca` opera sobre string literal, nao regex de sed: os alvos tem colchetes e parenteses, e
# escapar isso em sed foi a origem de mutante-que-nao-aplica em outra suite deste repo.
troca(){ # $1=de  $2=para
  python3 - "$ORIG" "$1" "$2" <<'PY'
import sys
p, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
n = s.count(de)
if n != 1:
    sys.exit(f"padrao nao e unico no arquivo (achado {n}x): {de!r}")
open(p, 'w').write(s.replace(de, para, 1))
PY
}

mutante(){ # $1=nome $2=descricao $3=caso-alvo (regex) que DEVE reprovar $4..=comando de mutacao
  local nome="$1" desc="$2" alvo="$3"; shift 3
  cp -f "$TMP/orig.py" "$ORIG"
  "$@"
  if cmp -s "$TMP/orig.py" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); cp -f "$TMP/orig.py" "$ORIG"; return
  fi
  if ! python3 -m py_compile "$ORIG" 2>/dev/null; then
    echo "  FAIL  $nome nao compila apos a mutacao"; F=$((F+1)); cp -f "$TMP/orig.py" "$ORIG"; return
  fi
  local out rc
  out="$(bash "$REG" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  $nome SOBREVIVEU - a suite passa sem a garantia: $desc"; F=$((F+1))
  elif printf '%s\n' "$out" | grep -qE "^  FAIL.*$alvo"; then
    echo "  PASS  $nome morto pelo caso certo ($alvo)"; P=$((P+1))
  else
    echo "  FAIL  $nome: suite reprovou, mas NAO em '$alvo' - kill nao atribuivel"; F=$((F+1))
    printf '%s\n' "$out" | grep '^  FAIL' | sed 's/^/        /'
  fi
  cp -f "$TMP/orig.py" "$ORIG"
}

echo "== mutacao: cada garantia removida DEVE quebrar o caso que a exercita =="

# M1 - condicao (1): o nivelamento por caminho mais longo perde o incremento de nivel. Sem ele
# todo no colapsa para o nivel 0 - duas etapas com dependencia direta (ex.: red -> implement)
# passam a ser declaradas "na mesma onda", violando a propria definicao de precedencia.
mutante M1 "nivelamento respeita a precedencia (aresta incrementa o nivel)" \
  "ondas exatas de standard-change" \
  troca 'level[m] = max(level[m], level[n] + 1)' \
        'level[m] = max(level[m], level[n])'

# M2 - condicao (2), MUTANTE CENTRAL: a deteccao de escritas sobrepostas nunca dispara. Dois
# nos escrevendo o mesmo arquivo em paralelo deixam de ser recusados - a garantia que da nome a
# este escalonador (paralelismo mecanico, nao por raciocinio) desaparece.
mutante M2 "escritas sobrepostas sao recusadas (Writes(a) intersecta Writes(b))" \
  "F2 escritas sobrepostas" \
  troca 'if base_a.startswith(base_b) or base_b.startswith(base_a):' \
        'if False:'

# M3 - condicao (3): o limite de um lock de suite compartilhado por onda e desativado. Dois nos
# do MESMO checkout tomando tests/lib/lock.sh na mesma onda deixam de ser recusados - a suite
# de um colidiria com a do outro (exit 3), e o escalonador teria certificado a colisao.
mutante M3 "no maximo um no compartilhado toma o lock de suite por onda" \
  "F3 dois nos compartilhados disputando o lock de suite" \
  troca 'if len(lockers_compartilhados) > 1:' \
        'if len(lockers_compartilhados) > 99:'

# M4 - read_parallelism_cap: o limite do registry deixa de ser respeitado. Um fan-out de
# leitores maior do que o declarado em orchestration/registry.json deixa de ser recusado.
mutante M4 "read_parallelism_cap do registry e respeitado" \
  "F5 5 leitores com cap=4" \
  troca 'if len(leitores) > cap:' \
        'if len(leitores) > 99:'

cp -f "$TMP/orig.py" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
