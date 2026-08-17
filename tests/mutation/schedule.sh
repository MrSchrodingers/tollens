#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - orchestration/schedule.py (docs/adr/0020, regra de metodo 2).
#
# Por que existe: tests/unit/schedule.sh so prova que o validador REJEITA as fixtures hoje.
# Isso nao prova que a rejeicao vem da garantia certa - um teste que sobrevive a remocao da
# garantia nao testa a garantia, testa outra coisa (o precedente proprio deste repositorio,
# ADR 0020: um hash desalinhado era o unico obstaculo, e o teste passava com a checagem de posse
# removida). Cada mutante abaixo remove UMA garantia do modelo - (1) precedencia/ciclo/aresta
# valida, (2) escritas disjuntas, (3) lock de suite compartilhado, cap de leitura, normalizacao
# de caminho e dialeto de glob restrito - e EXIGE que tests/unit/schedule.sh reprove no caso
# especifico que aquela garantia protege.
#
# O MUTANTE CENTRAL e MS2: sem a deteccao de escritas sobrepostas, o escalonador vira decoracao -
# aceitaria dois nos escrevendo o mesmo arquivo em paralelo, exatamente o que o mecanismo existe
# para impedir. MS5-MS10 cobrem garantias acrescentadas depois da revisao independente medir tres
# falsos negativos e um defeito de diagnostico neste modulo (normalizacao de caminho, dialeto de
# glob, ciclo sem fixture, cobertura de anticadeia fora da onda, arestas para no inexistente).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
# ARENA: muta uma COPIA da arvore, nunca a arvore candidata. Ver tests/lib/arena.sh para os
# seis incidentes medidos que motivaram isto.
. "$(dirname "$0")/../lib/arena.sh"
ORIG="orchestration/schedule.py"
REG="tests/unit/schedule.sh"
# ORDEM DO TRAP: restaurar ANTES de remover o diretorio temporario que guarda a copia limpa -
# uma interrupcao no meio do jogo nao pode deixar o mutante instalado no arquivo real
# (defeito ja medido em tests/mutation/run.sh, ver o comentario la).
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.py" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.py"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=10

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

# MS1 - condicao (1): o nivelamento por caminho mais longo perde o incremento de nivel. Sem ele
# todo no colapsa para o nivel 0 - duas etapas com dependencia direta (ex.: red -> implement)
# passam a ser declaradas "na mesma onda", violando a propria definicao de precedencia.
mutante MS1 "nivelamento respeita a precedencia (aresta incrementa o nivel)" \
  "ondas exatas de standard-change" \
  troca 'level[m] = max(level[m], level[n] + 1)' \
        'level[m] = max(level[m], level[n])'

# MS2 - condicao (2), MUTANTE CENTRAL: a deteccao de escritas sobrepostas nunca dispara. Dois
# nos escrevendo o mesmo arquivo em paralelo deixam de ser recusados - a checagem que da nome
# a este validador (conflito de escrita mecanico, nao por raciocinio) desaparece.
mutante MS2 "escritas sobrepostas sao recusadas (Writes(a) intersecta Writes(b))" \
  "F2 escritas sobrepostas" \
  troca 'if base_a.startswith(base_b) or base_b.startswith(base_a):' \
        'if False:'

# MS3 - condicao (3): o limite de um lock de suite compartilhado entre nos sem precedencia e
# desativado. Dois nos do MESMO checkout tomando tests/lib/lock.sh sem relacao `<` entre si
# deixam de ser recusados - a suite de um colidiria com a do outro (exit 3), e o validador
# teria certificado a colisao.
mutante MS3 "no maximo um no compartilhado toma o lock de suite entre nos sem precedencia" \
  "F3 dois nos compartilhados disputando o lock de suite" \
  troca 'and sched[b]["holds_suite_lock"] and sched[b]["isolation"] == "shared"' \
        'and False'

# MS4 - read_parallelism_cap: o limite do registry deixa de ser respeitado. Um fan-out de
# leitores maior do que o declarado em orchestration/registry.json deixa de ser recusado.
mutante MS4 "read_parallelism_cap do registry e respeitado" \
  "F5 5 leitores com cap=4" \
  troca 'if len(leitores) > cap:' \
        'if len(leitores) > 99:'

# MS5 - normalizacao de caminho em _glob_base: sem ela, "./x" e "x" (o MESMO arquivo)
# geram bases literais diferentes e o conflito de escrita nunca e detectado.
mutante MS5 "caminho e normalizado antes de extrair a base literal do glob" \
  "F10 mesmo arquivo grafado como" \
  troca 'pattern = posixpath.normpath(pattern) if pattern else pattern' \
        'pattern = pattern'

# MS6 - dialeto de glob restrito: sem a recusa de sintaxe fora do dialeto, um padrao com
# expansao de chaves e aceito e comparado errado (tratado como literal), voltando a
# produzir falso negativo em vez de ser barrado na validacao.
mutante MS6 "writes fora do dialeto suportado e recusado na validacao" \
  "F11 writes com expansao de chaves" \
  troca 'ch = _dialeto_glob_invalido(padrao)' \
        'ch = None'

# MS7 - condicao (1) contra ciclo: remover o guard `processados != len(nodes)` faz um
# workflow ciclico ser aceito como se tivesse escalonamento valido.
mutante MS7 "ciclo no grafo do workflow e detectado (processados != len(nodes))" \
  "F12 ciclo no grafo do workflow" \
  troca 'if processados != len(nodes):' \
        'if False:'

# MS8 - condicao (2)/(3) sobre TODA anticadeia (M4 do achado externo): sem o fecho
# transitivo, dois nos sem precedencia entre si mas em niveis DIFERENTES do nivelamento
# escapam da checagem de escrita/lock.
mutante MS8 "conflito de escrita/lock cobre pares sem precedencia em QUALQUER nivel" \
  "F13 anticadeia sem precedencia" \
  troca 'if b in descendentes[a] or a in descendentes[b]:' \
        'if True:'

# MS9 - aresta com DESTINO fora de 'nodes': sem a validacao previa, o nivelamento estoura
# KeyError cru em vez de SCHEDULE_ERROR estruturado. Exit code sozinho nao discrimina (o
# KeyError cru TAMBEM sai != 0) - o alvo e a mensagem estruturada, nao o exit code.
mutante MS9 "aresta com destino fora de 'nodes' produz erro estruturado, nao KeyError" \
  "F14 erro estruturado" \
  troca "if b not in node_set:" \
        "if False:"

# MS10 - aresta com ORIGEM fora de 'nodes': sem a validacao previa, o sintoma e reportado
# como "ciclo detectado" - diagnostico errado, nao ha ciclo no grafo real. Exit code sozinho
# nao discrimina (o diagnostico errado TAMBEM sai != 0) - o alvo e a mensagem certa.
mutante MS10 "aresta com origem fora de 'nodes' e diagnosticada corretamente, nao como ciclo" \
  "F15 diagnostica aresta invalida" \
  troca "if a not in node_set:" \
        "if False:"

cp -f "$TMP/orig.py" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
