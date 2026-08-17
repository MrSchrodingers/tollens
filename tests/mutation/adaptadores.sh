#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - conformidade de adaptador de documento (evidence/validate-adapters.py).
#
# POR QUE EXISTE. O grupo D10 de tests/unit/document-tools.sh nasceu em 2026-08-12 junto com o
# validador que ele exercita, e um oraculo novo sem mutante e uma AFIRMACAO sobre o oraculo, nao
# uma medicao dele - regra de metodo 2 do ADR 0020: remova a garantia do codigo e exija que o
# teste REPROVE. Um teste que sobrevive ao mutante nao testa a garantia; testa outra coisa.
#
# O defeito de origem: `media.json` forkou o schema dos outros tres adaptadores (declarava
# `strategy`/`pipeline` no lugar de `probe`/`plans`), e nenhum verificador conferia conformidade
# de adaptador - `tests/unit/supply-chain.sh` lia so `.requires.python_packages` e a CI conferia
# `jq -e .`, que JSON valido sempre passa. Sobre um `.png` o caminho sancionado terminava em erro
# cru de jq.
#
# LIMITE DECLARADO - uma garantia NAO mutada aqui, e a razao. "Adaptador sem `plans` reprova" e
# protegida por DUAS checagens independentes de `validate-adapters.py`: a de chaves obrigatorias
# de topo (`TOPO_OBRIGATORIO` contem "plans") e a que exige `plans` como lista nao vazia. Nenhum
# mutante de UMA linha pode mata-la: desligada qualquer das duas, a outra ainda reprova o mesmo
# arquivo. Redundancia e o oposto do defeito que esta suite persegue, mas tambem torna a garantia
# nao mensuravel por mutacao pontual - e isso fica dito, em vez de a ausencia parecer esquecimento.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
# ARENA: muta uma COPIA da arvore, nunca a arvore candidata. Ver tests/lib/arena.sh para os
# seis incidentes medidos que motivaram isto.
. "$(dirname "$0")/../lib/arena.sh"
ORIG="evidence/validate-adapters.py"
REG="tests/unit/document-tools.sh"
# ORDEM DO TRAP: RESTAURAR ANTES DE REMOVER (tests/unit/arnes-de-mutacao.sh, AM1/AM2). O inverso
# deixa o mutante no disco em qualquer interrupcao, e um arnes que falha aberto PRODUZ a fraqueza
# que alega medir.
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.py" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.py"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=5

# BASELINE: sem isto, uma regressao ja vermelha por ambiente faria TODOS os mutantes parecerem
# mortos - o runner reportaria verde justamente quando nao esta medindo nada.
echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

troca(){ # $1=de  $2=para  - string literal, nao regex. Nao casou = nao aplicado (reverte).
  python3 - "$ORIG" "$1" "$2" <<'PY'
import sys
p, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if de not in s:
    sys.exit(f"PADRAO AUSENTE: {de!r}")
open(p, "w").write(s.replace(de, para, 1))
PY
}

mutante(){ # $1=nome $2=descricao $3=caso-alvo $4..=comando
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
  elif printf '%s' "$out" | grep -qF "FAIL  $alvo"; then
    echo "  PASS  $nome morto pelo caso certo ($alvo)"; P=$((P+1))
  else
    echo "  FAIL  $nome: suite reprovou, mas NAO em '$alvo' - kill nao atribuivel"; F=$((F+1))
  fi
  cp -f "$TMP/orig.py" "$ORIG"
}

echo "== mutacao: cada garantia removida DEVE reprovar o registro =="

# MA1 - o schema de topo deixa de ser FECHADO. E a forma exata do fork medido: `media.json` nao
# perdeu campos por descuido, ele GANHOU `strategy` e `pipeline`, o que fazia o arquivo parecer
# desenho proprio em vez de contrato quebrado.
mutante MA1 "chave de topo inventada e rejeitada (fork por ADICAO)" \
  "  chave inventada no topo REPROVA (o fork foi por ADICAO)" \
  troca '    sobra = sorted(set(doc) - set(TOPO_OBRIGATORIO) - set(TOPO_OPCIONAL))' \
        '    sobra = []  # mutante MA1'

# MA2 - a checagem de placeholder desliga. E a que pega o defeito LITERAL do arquivo forkado:
# `$IN`, `$OUT` e `$OUT_PATTERN` nunca foram substituidos por nada (doctool.sh:51-52 so substitui
# $INPUT/$WORK/$TOOLS/$TERM/$PAGE) e chegariam ao comando como texto.
mutante MA2 "placeholder desconhecido em args e rejeitado" \
  "  placeholder que o executor nao substitui REPROVA" \
  troca '        estranhos = _placeholders_estranhos(a)' \
        '        estranhos = []  # mutante MA2'

# MA3 - plano sem step produtivo passa a ser aceito. O sintoma que isso libera e o pior tipo:
# `run` sai 0 com `claims: []`, indistinguivel de "o documento nao tinha nada".
mutante MA3 "plano precisa de ao menos um step que produza saida" \
  "  plano sem step produtivo REPROVA (pack vazio com exit 0)" \
  troca '    if not produtivo:' \
        '    if False:  # mutante MA3'

# MA4 - o registro deixa de indexar extensao, e a colisao entre dois adaptadores para o mesmo
# formato deixa de ser detectavel. A rota passaria a depender da ordem de glob (doctool.sh:39-43),
# isto e, do NOME do arquivo de adaptador.
mutante MA4 "extensao ja roteada por outro adaptador e rejeitada" \
  "  extensao ja roteada por outro adaptador REPROVA" \
  troca '                extensoes_vistas[e] = base' \
        '                pass  # mutante MA4'

# MA5 - CONTROLE DE DIRECAO. Um validador que REPROVA TUDO passaria em MA1..MA4 sem esforco: todos
# esperam reprovacao. Sem este mutante, a suite nao distinguiria um oraculo que discrimina de um
# que so diz nao - o mesmo vicio de um teste que reprova sempre.
mutante MA5 "o validador APROVA um registro conforme (nao reprova por reflexo)" \
  "o validador aprova o registro real" \
  troca '    erros, ids_vistos, extensoes_vistas = [], {}, {}' \
        '    erros, ids_vistos, extensoes_vistas = ["mutante MA5"], {}, {}'

cp -f "$TMP/orig.py" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
