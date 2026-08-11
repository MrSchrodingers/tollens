#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - verificador de capacidade declarada
# (evidence/runtime-probes/declared-capabilities.py).
#
# Por que existe: a correcao trocou um parser artesanal de frontmatter (regex com `break`) por
# `yaml.safe_load`, especificamente porque o parser artesanal TRUNCAVA listas YAML validas -
# achado ALTO, reproduzido: uma projecao com `Write`/`Edit` apos uma linha em branco dentro do
# bloco de `tools:` passava PASS/exit 0, escondendo a divergencia real. Regra de metodo 2
# (docs/adr/0020): toda garantia corrigida aqui e validada por MUTACAO - reintroduzir o defeito
# tem que fazer a suite de regressao (tests/unit/capabilities.sh) reprovar no caso que prova
# exatamente aquela garantia. Um teste que sobrevive ao mutante nao testa a garantia.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"
ORIG="evidence/runtime-probes/declared-capabilities.py"
REG="tests/unit/capabilities.sh"
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.py" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.py"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=4

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

# SUBSTITUICAO LITERAL, nao sed: os alvos tem f-strings, aspas e chaves - escrever isso como
# padrao de sed produziria regex ilegivel e fragil. `troca` falha alto (ANCORA NAO CASOU) se a
# ancora nao existir com contagem exatamente 1, para nunca contar um mutante nao aplicado como
# mutante morto (mesma disciplina de tests/mutation/run.sh).
troca(){ # $1=trecho original  $2=substituto
python3 - "$ORIG" "$1" "$2" <<'PY'
import sys
alvo, velho, novo = sys.argv[1:4]
s = open(alvo, encoding="utf-8").read()
if s.count(velho) != 1:
    sys.exit("ANCORA NAO CASOU (%d ocorrencias)" % s.count(velho))
open(alvo, "w", encoding="utf-8").write(s.replace(velho, novo))
PY
}

mutante(){ # $1=nome $2=descricao $3=caso-alvo que DEVE reprovar $4..=comando
  local nome="$1" desc="$2" alvo="$3"; shift 3
  cp -f "$TMP/orig.py" "$ORIG"
  "$@"
  if cmp -s "$TMP/orig.py" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - a ancora nao casa com o codigo atual."
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

echo "== mutacao: cada garantia desta correcao DEVE quebrar a regressao =="

# MC1 - O MUTANTE CENTRAL pedido pela delegacao: reintroduz a truncagem da lista de bloco na
# primeira linha em branco, a MESMA classe de defeito do parser artesanal removido (ele fazia
# `break` no primeiro item que nao casasse `^\s*-\s*(.+?)\s*$`; uma linha em branco nunca casa).
# K10 planta o caso EXATO da reproducao do achado: canonico com 4 ferramentas, projecao com as
# mesmas 4 e mais `Write`/`Edit` apos uma linha em branco - o mutante tem que voltar a escondê-las.
mutante MC1 "o bloco de tools: nao trunca na primeira linha em branco" \
  "linha em branco no bloco NAO esconde itens extras -> exit 1 (era exit 0)" \
  troca '    try:
        doc = yaml.safe_load("\n".join(fm))
    except yaml.YAMLError:
        return YAML_INVALIDO
' \
        '    try:
        fm_trunc = []
        for _l in fm:
            if not _l.strip():
                break
            fm_trunc.append(_l)
        doc = yaml.safe_load("\n".join(fm_trunc))
    except yaml.YAMLError:
        return YAML_INVALIDO
'

# MC2 - YAML invalido na fonte canonica volta a ser classificado como VIOLACAO (defeito
# estrutural do agente) em vez de NAO_VERIFICADO (indecidivel). E a decisao explicita desta
# correcao: um documento que o parser de referencia recusa nao e prova de divergencia de
# capacidade - e prova de sintaxe quebrada, categoria distinta.
mutante MC2 "YAML invalido e indecidivel, nao violacao" \
  "YAML invalido na canonica -> exit 2 (indecidivel, nao violacao)" \
  troca '        if t_canon is YAML_INVALIDO:
            nao_verificados.append(
                f"{nome}: fonte canonica {canon_path} tem frontmatter fechado mas o YAML dentro "
                f"dele nao parseia - indecidivel, nao violacao")
            continue
        if t_canon is None or t_canon is TOOLS_AUSENTE:
' \
        '        if t_canon is None or t_canon is TOOLS_AUSENTE or t_canon is YAML_INVALIDO:
'

# MC3 - falha AMBIENTAL de leitura (permissao, E/S) na fonte canonica volta a ser classificada
# como VIOLACAO. E a decisao P5 do revisor: `frontmatter_lines() is None` conflava OSError
# (causa alheia ao autor do agente) com frontmatter malformado (defeito estrutural real).
# Classificar a primeira como a segunda e o falso positivo que ensina o operador a desligar o
# mecanismo - por isso esta garantia precisa da mesma protecao de mutacao que as demais.
mutante MC3 "falha ambiental de leitura e indecidivel, nao defeito estrutural" \
  "canonica ilegivel por permissao -> exit 2 (nao 1 - nao e defeito estrutural)" \
  troca '        if t_canon is ERRO_AMBIENTAL:
            # Falha AMBIENTAL (permissao, E/S) na fonte canonica: indecidivel, nao defeito
            # estrutural - ver docstring de `_ErroAmbiental`.
            nao_verificados.append(
                f"{nome}: fonte canonica {canon_path} nao pode ser lida (falha ambiental de "
                f"permissao ou E/S) - indecidivel, nao defeito estrutural")
            continue
        if t_canon is YAML_INVALIDO:
            nao_verificados.append(
                f"{nome}: fonte canonica {canon_path} tem frontmatter fechado mas o YAML dentro "
                f"dele nao parseia - indecidivel, nao violacao")
            continue
        if t_canon is None or t_canon is TOOLS_AUSENTE:
' \
        '        if t_canon is YAML_INVALIDO:
            nao_verificados.append(
                f"{nome}: fonte canonica {canon_path} tem frontmatter fechado mas o YAML dentro "
                f"dele nao parseia - indecidivel, nao violacao")
            continue
        if t_canon is None or t_canon is TOOLS_AUSENTE or t_canon is ERRO_AMBIENTAL:
'

# MC4 - a forma ESCALAR separada por virgula (`tools: A, B, C`) deixa de ser reconhecida. E a
# forma que os 10 agentes reais deste repositorio usam hoje (ver execution/agents/*.md); perde-la
# faz o probe sair NAO_VERIFICADO para o repositorio inteiro, em silencio de CI - a mesma classe
# de regressao que a troca de parser existe para fechar, na direcao oposta (falso negativo em
# vez de falso positivo).
mutante MC4 "escalar separado por virgula continua reconhecido como tools:" \
  "exit code 0" \
  troca '    if isinstance(valor, str):
' \
        '    if isinstance(valor, dict):
'

cp -f "$TMP/orig.py" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
