#!/usr/bin/env bash
# ESCALONAMENTO - orchestration/schedule.py e um VALIDADOR DE CONFIGURACAO DE ESCALONAMENTO:
# verifica (1) precedencia (fecho transitivo do DAG, nao so pares na mesma onda de nivelamento),
# (2) escritas par-a-par disjuntas entre nos sem relacao de precedencia, (3) no maximo um no
# COMPARTILHADO tomando o lock de suite entre nos sem precedencia, e o `read_parallelism_cap`
# de orchestration/registry.json (esse, sim, por onda). Ate aqui nada impunha isso - o
# paralelismo declarado em `orchestration/workflows/*.json` (ex.: review/refute/security sem
# aresta entre si) dependia da leitura do orquestrador, nao de um oraculo executavel.
#
# NAO e "garantia mecanica de paralelismo" sobre os workflows reais: medido, ha 9 pares de nos
# concorrentes nos 3 workflows de producao e em ZERO deles a checagem de conflito de escrita (2)
# chega a ser avaliada (todo no de codigo declara writes:["**"], os demais writes:[] - a
# condicao `writes_a and writes_b` nunca fica verdadeira entre dois nos concorrentes reais). O
# poder discriminante demonstrado abaixo vem inteiramente das fixtures SINTETICAS F1-F15,
# construidas sob EVIDENCE_GATE_ROOT (mesma convencao de tests/unit/methodology.py e do
# `_prepara` de tests/mutation/fronteira.sh): sem elas, um validador inerte (que sempre sai 0)
# passaria despercebido, porque os dados reais nunca exercitam o caminho de rejeicao.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
SCHED="$PWD/orchestration/schedule.py"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "NAO VERIFICADO: jq ausente - oraculo de ondas exatas nao pode ser avaliado." >&2; exit 2; }

echo "== fixtures sinteticas: F1-F15 sob EVIDENCE_GATE_ROOT proprio =="
python3 - "$TMP" <<'PY'
import json, os, sys
root = sys.argv[1]


def node(actor="x", isolation="shared", lock=False, writes=None, produces=None):
    return {
        "actor": actor, "isolation": isolation, "holds_suite_lock": lock,
        "reads": [], "writes": writes or [], "produces": produces or [],
    }


def write(scenario, cap, nodes, edges, meta):
    d = os.path.join(root, scenario, "orchestration")
    os.makedirs(os.path.join(d, "workflows"), exist_ok=True)
    os.makedirs(os.path.join(d, "schedule"), exist_ok=True)
    reg = {"schema_version": 1, "invariants": {"single_writer": True, "read_parallelism_cap": cap}}
    with open(os.path.join(d, "registry.json"), "w") as f:
        json.dump(reg, f)
    wf = {"id": "w", "entry": nodes[0], "nodes": nodes, "edges": edges}
    with open(os.path.join(d, "workflows", "w.json"), "w") as f:
        json.dump(wf, f)
    with open(os.path.join(d, "schedule", "w.json"), "w") as f:
        json.dump(meta, f)


# F1 - legal: dois escritores em paralelo com escritas disjuntas.
write("f1-legal-escritas-disjuntas", 4,
      ["a", "b", "c"], [["a", "b"], ["a", "c"]],
      {"a": node(), "b": node(writes=["src/b.py"]), "c": node(writes=["src/c.py"])})

# F2 - ilegal (MUTANTE CENTRAL): escritas sobrepostas - glob de diretorio x arquivo dentro dele.
write("f2-conflito-escrita", 4,
      ["a", "b", "c"], [["a", "b"], ["a", "c"]],
      {"a": node(), "b": node(writes=["src/shared/*"]), "c": node(writes=["src/shared/x.py"])})

# F3 - ilegal: dois nos COMPARTILHADOS disputam o lock de suite na mesma onda.
write("f3-lock-duplo-compartilhado", 4,
      ["a", "b", "c"], [["a", "b"], ["a", "c"]],
      {"a": node(), "b": node(lock=True), "c": node(lock=True)})

# F4 - legal: dois nos em WORKTREE proprio tomam lock na mesma onda - checkouts distintos nao
# competem pelo mesmo arquivo de lock (medido: tests/lib/lock.sh cai em caminho por checkout).
write("f4-lock-duplo-worktree", 4,
      ["a", "b", "c"], [["a", "b"], ["a", "c"]],
      {"a": node(), "b": node(isolation="worktree", lock=True), "c": node(isolation="worktree", lock=True)})

# F5 - ilegal: cap de leitura excedido (5 leitores, cap=4).
letras = ["b", "c", "d", "e", "f"]
write("f5-cap-excedido", 4,
      ["a"] + letras, [["a", n] for n in letras],
      {n: node() for n in ["a"] + letras})

# F6 - legal (controle negativo de F5): exatamente no limite do cap (4 leitores, cap=4). Sem
# este caso, F5 nao provaria um LIMITE - provaria so que "muitos leitores" e barrado, e um
# validador excessivamente estrito (barra qualquer fan-out >1) passaria por F5 sem detectar
# que tambem esta barrando configuracao legitima.
letras6 = ["b", "c", "d", "e"]
write("f6-cap-no-limite", 4,
      ["a"] + letras6, [["a", n] for n in letras6],
      {n: node() for n in ["a"] + letras6})

# F7 - ilegal: inventario diverge (schedule sem metadado para um no do workflow).
write("f7-inventario-diverge", 4,
      ["a", "b"], [["a", "b"]],
      {"a": node()})

# F8 - ilegal: campo obrigatorio ausente no metadado de um no.
m8 = node()
del m8["writes"]
write("f8-campo-ausente", 4, ["a", "b"], [["a", "b"]], {"a": node(), "b": m8})

# F9 - ilegal: valor de isolation fora do dominio conhecido.
m9 = node()
m9["isolation"] = "outro"
write("f9-isolation-invalida", 4, ["a", "b"], [["a", "b"]], {"a": node(), "b": m9})

# F10 - ilegal: mesmo arquivo com grafias diferentes ("./x" vs "x") - so detecta com
# normalizacao de caminho em _glob_base (sem ela, falso negativo medido pela revisao
# independente).
write("f10-normaliza-caminho", 4,
      ["a", "b", "c"], [["a", "b"], ["a", "c"]],
      {"a": node(), "b": node(writes=["./src/x.py"]), "c": node(writes=["src/x.py"])})

# F11 - ilegal (na VALIDACAO, nao na comparacao): expansao de chaves e fora do dialeto de
# glob suportado - RECUSADA em vez de comparada errado (a comparacao por prefixo trataria
# "src/{a,b}/x.py" como literal e nunca acusaria conflito com "src/a/x.py").
write("f11-dialeto-glob-invalido", 4,
      ["a", "b"], [["a", "b"]],
      {"a": node(), "b": node(writes=["src/{a,b}/x.py"])})

# F12 - ilegal: ciclo no grafo do workflow. Sem esta fixture, um mutante que remove o guard
# `processados != len(nodes)` sobrevive (nenhum caso do repositorio tem ciclo).
write("f12-ciclo", 4,
      ["a", "b", "c"], [["a", "b"], ["b", "c"], ["c", "a"]],
      {"a": node(), "b": node(), "c": node()})

# F13 - ilegal: anticadeia SEM precedencia entre si, em NIVEIS diferentes do nivelamento por
# caminho mais longo. nodes=[a,b,x], edges=[[a,b]]: "x" nao depende de nada (nivel 0, junto
# com "a"), "b" fica no nivel 1 - mas "x" e "b" continuam sem relacao `<` entre si, escrevem
# o MESMO arquivo e os dois tomam o lock de suite compartilhado. A checagem por ONDA (nivel)
# nao pega este par; a checagem pelo fecho transitivo do DAG pega.
write("f13-anticadeia-sem-precedencia", 4,
      ["a", "b", "x"], [["a", "b"]],
      {"a": node(), "b": node(writes=["src/x.py"], lock=True), "x": node(writes=["src/x.py"], lock=True)})

# F14 - ilegal: aresta cujo DESTINO nao esta em "nodes". Sem validacao previa, isto
# estourava KeyError cru (sem SCHEDULE_ERROR nenhum) dentro do nivelamento.
write("f14-aresta-destino-fantasma", 4,
      ["a", "b"], [["a", "b"], ["a", "fantasma"]],
      {"a": node(), "b": node()})

# F15 - ilegal: aresta cuja ORIGEM nao esta em "nodes". Sem validacao previa, isto inflava o
# indegree de "b" sem nunca processar a origem fantasma, e o sintoma (processados != len(nodes))
# era reportado como "ciclo detectado" - diagnostico ERRADO, nao ha ciclo aqui.
write("f15-aresta-origem-fantasma", 4,
      ["a", "b"], [["a", "b"], ["fantasma", "b"]],
      {"a": node(), "b": node()})
PY

roda(){ EVIDENCE_GATE_ROOT="$TMP/$1" python3 "$SCHED" --check; }

OUT1="$(roda f1-legal-escritas-disjuntas 2>&1)"; RC1=$?
chk "F1 escritas disjuntas em paralelo: legal" "$RC1" 0

OUT2="$(roda f2-conflito-escrita 2>&1)"; RC2=$?
chk "F2 escritas sobrepostas: RECUSADO (exit != 0)" "$RC2" 1
printf '%s' "$OUT2" | grep -qF "conflito de escrita entre 'b' e 'c'"
chk "  F2 nomeia os dois nos em conflito" $? 0

OUT3="$(roda f3-lock-duplo-compartilhado 2>&1)"; RC3=$?
chk "F3 dois nos compartilhados disputando o lock de suite: RECUSADO" "$RC3" 1
printf '%s' "$OUT3" | grep -qF "disputa o lock de suite"
chk "  F3 nomeia a disputa do lock" $? 0

OUT4="$(roda f4-lock-duplo-worktree 2>&1)"; RC4=$?
chk "F4 dois nos em worktree proprio tomando lock: legal (checkouts distintos)" "$RC4" 0

OUT5="$(roda f5-cap-excedido 2>&1)"; RC5=$?
chk "F5 5 leitores com cap=4: RECUSADO" "$RC5" 1
printf '%s' "$OUT5" | grep -qF "read_parallelism_cap=4"
chk "  F5 cita o cap do registry" $? 0

OUT6="$(roda f6-cap-no-limite 2>&1)"; RC6=$?
chk "F6 4 leitores com cap=4: legal (limite exato, controle negativo de F5)" "$RC6" 0

OUT7="$(roda f7-inventario-diverge 2>&1)"; RC7=$?
chk "F7 schedule sem metadado de um no do workflow: RECUSADO" "$RC7" 1

OUT8="$(roda f8-campo-ausente 2>&1)"; RC8=$?
chk "F8 metadado sem campo obrigatorio: RECUSADO" "$RC8" 1

OUT9="$(roda f9-isolation-invalida 2>&1)"; RC9=$?
chk "F9 isolation fora do dominio conhecido: RECUSADO" "$RC9" 1

OUT10="$(roda f10-normaliza-caminho 2>&1)"; RC10=$?
chk "F10 mesmo arquivo grafado como './x' e 'x': RECUSADO" "$RC10" 1
printf '%s' "$OUT10" | grep -qF "conflito de escrita entre 'b' e 'c'"
chk "  F10 normalizacao de caminho detecta o conflito" $? 0

OUT11="$(roda f11-dialeto-glob-invalido 2>&1)"; RC11=$?
chk "F11 writes com expansao de chaves: RECUSADO" "$RC11" 1
printf '%s' "$OUT11" | grep -qF "fora do dialeto suportado"
chk "  F11 recusa em vez de comparar errado" $? 0

OUT12="$(roda f12-ciclo 2>&1)"; RC12=$?
chk "F12 ciclo no grafo do workflow: RECUSADO" "$RC12" 1
printf '%s' "$OUT12" | grep -qF "ciclo detectado"
chk "  F12 diagnostica ciclo" $? 0

OUT13="$(roda f13-anticadeia-sem-precedencia 2>&1)"; RC13=$?
chk "F13 anticadeia sem precedencia em niveis diferentes: RECUSADO" "$RC13" 1
printf '%s' "$OUT13" | grep -qF "conflito de escrita entre 'b' e 'x'"
chk "  F13 pega conflito de escrita fora da mesma onda" $? 0
printf '%s' "$OUT13" | grep -qF "disputa o lock de suite"
chk "  F13 pega disputa de lock fora da mesma onda" $? 0

OUT14="$(roda f14-aresta-destino-fantasma 2>&1)"; RC14=$?
chk "F14 aresta com destino fora de 'nodes': RECUSADO" "$RC14" 1
printf '%s' "$OUT14" | grep -qF "aresta referencia no inexistente em 'nodes': 'fantasma' (destino)"
chk "  F14 erro estruturado, sem KeyError cru" $? 0

OUT15="$(roda f15-aresta-origem-fantasma 2>&1)"; RC15=$?
chk "F15 aresta com origem fora de 'nodes': RECUSADO" "$RC15" 1
printf '%s' "$OUT15" | grep -qF "aresta referencia no inexistente em 'nodes': 'fantasma' (origem)"
chk "  F15 diagnostica aresta invalida" $? 0
! printf '%s' "$OUT15" | grep -qF "ciclo detectado"
chk "  F15 nao rotula como ciclo (diagnostico errado)" $? 0

echo
echo "== os TRES workflows reais deste repositorio =="
OUTP="$(python3 "$SCHED" --check 2>&1)"; RCP=$?
chk "producao: os 3 workflows reais escalonam sem conflito" "$RCP" 0
NW="$(printf '%s' "$OUTP" | grep -c '^ONDAS ')"
chk "  emite ondas para os 3 workflows" "$NW" 3

# ORACULO DE ONDAS EXATAS - alvo do mutante de precedencia (condicao 1). O nivelamento por
# caminho mais longo garante, por construcao, que dois nos com relacao de precedencia nunca
# caem na mesma onda; este caso observa o resultado concreto em vez de confiar na prova.
GOT="$(printf '%s' "$OUTP" | grep '^ONDAS standard-change ' | sed 's/^ONDAS standard-change //' | jq -c .)"
WANT="$(printf '%s' '[["classify"],["investigate","map"],["plan"],["red"],["implement"],["test"],["review","refute"],["evidence"],["candidate"]]' | jq -c .)"
chk "  ondas exatas de standard-change (nivelamento de precedencia correto)" "$GOT" "$WANT"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=29
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "escalonamento verde ($P/$EXPECTED)" || echo "escalonamento VERMELHO"
exit "$F"
