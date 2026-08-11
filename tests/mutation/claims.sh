#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - frescor de ancora do claim ledger (evidence/validate-claims.py).
#
# Por que existe: `tests/unit/claims.sh` ganhou em 2026-08-11 o grupo L-FRESCOR, e um caso novo sem
# mutante e uma afirmacao sobre o oraculo, nao uma medicao dele. A regra de metodo 2 (ADR 0020)
# exige que garantia de seguranca seja validada por MUTACAO: remova a garantia e o teste REPROVA.
#
# O defeito que originou: a isencao de frescor cobria TODO status nao-ativo, e `not-verified` caiu
# nela. Ao renumerar C-018->C-019 a observacao foi editada, o `blob_sha` ficou apontando para o
# conteudo pre-edicao, e `validate-claims.py` saiu 0. Uma claim ABERTA desancorada e pior que uma
# fechada: ela ainda sera lida como pendencia viva, e `line_start/line_end` sao validados contra o
# blob ANCORADO - com ancora obsoleta, a faixa citada tambem deixa de significar qualquer coisa.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"
ORIG="evidence/validate-claims.py"
REG="tests/unit/claims.sh"
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.py" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.py"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=5

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

troca(){ # $1=de  $2=para  - string literal, nao regex
  python3 - "$ORIG" "$1" "$2" <<'PY'
import sys
p, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
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

echo "== mutacao: cada garantia removida DEVE quebrar o ledger =="

# MK1 - reintroduz o defeito LITERAL: `not-verified` volta a ser isenta de frescor. Alvo escolhido
# por ser o unico caso que distingue a correcao; os outros tres do grupo sobrevivem a este mutante,
# entao o kill e atribuivel por construcao.
mutante MK1 "claim aberta ('not-verified') exige ancora fresca" \
  "  ancora obsoleta em 'not-verified' TAMBEM reprova (alegacao aberta)" \
  troca 'EXIGEM_FRESCOR = frozenset({STATUS_ATIVO, "not-verified"})' \
        'EXIGEM_FRESCOR = frozenset({STATUS_ATIVO})'

# MK2 - o oposto: exigir frescor de TODO status. Mata a isencao dos terminais, que e correta -
# sem ela seria impossivel preservar o registro de uma alegacao derrubada cujo lastro mudou.
# Este mutante existe para provar que o caso `refuted` tambem discrimina, e nao e decoracao.
mutante MK2 "status terminal permanece isento de frescor" \
  "  'refuted' segue isenta (registro historico terminal)" \
  troca 'EXIGEM_FRESCOR = frozenset({STATUS_ATIVO, "not-verified"})' \
        'EXIGEM_FRESCOR = frozenset(STATUS)'

# MK3 - onda 5, D6 (CRITICO): RE_MUT volta a aceitar MENCAO em comentario (`# <ID>[-: ]`) como se
# fosse INVOCACAO - o defeito exato dos mutantes fantasmas K10/L6. So a extracao muda; nenhuma
# claim real cita um ID inventado, entao o alvo e o caso construido para o discriminante.
mutante MK3 "RE_MUT exige INVOCACAO real, nao mencao em comentario (fantasma K10/L6)" \
  "  mencao em comentario ('# ZZ9 ...') NAO entra - fantasma fechado" \
  troca 'RE_MUT = re.compile(r"^mutante\s+([A-Z]{1,3}[0-9]{1,3})\b\s")' \
        'RE_MUT = re.compile(r"^(?:mutante\s+|#\s*)([A-Z]{1,3}[0-9]{1,3})\b\s*[-: ]")'

# MK4 - onda 5, D6 (CRITICO): a checagem de colisao entre os espacos de nome regressao/mutante
# desliga. Sem ela, um ID que reusa uma regressao real como mutante resolveria em silencio.
mutante MK4 "colisao entre os espacos de nome regressao/mutante e detectada" \
  "mutante que colide com um ID de regressao ja existente -> NAO VERIFICADO (exit 2)" \
  troca '    if colisao:' \
        '    if False and colisao:'

# MK5 - onda 5, D6/D7 (CRITICO/AVISO): a checagem de ID de regressao duplicado ENTRE ARQUIVOS
# desliga - a mesma ambiguidade que L1..L18 tinham de fato entre claims.sh e literatura.sh (D7)
# antes de o prefixo do segundo ser renomeado para 'LT'.
mutante MK5 "ID de regressao duplicado entre arquivos e detectado" \
  "regressao G1 declarada em DOIS arquivos -> NAO VERIFICADO (exit 2)" \
  troca '        if len(arqs) > 1:' \
        '        if False and len(arqs) > 1:'

cp -f "$TMP/orig.py" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
