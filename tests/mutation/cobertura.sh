#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - o proprio piso de cobertura de decisao (evidence/cobertura.sh).
#
# Regra de metodo 2 (ADR 0020): garantia de seguranca so vale se, ao remove-la, o teste
# REPROVA. Os dois mutantes abaixo sao os dois modos OBVIOS de o mecanismo virar decoracao,
# citados na propria delegacao desta mudanca:
#   MC1 - o piso vai a ZERO (todo alvo passa, qualquer que seja a cobertura real).
#   MC2 - `--check` DEIXA DE COMPARAR com o piso (a violacao e detectada e impressa, mas nunca
#         vira reprovacao - o passo de CI ficaria sempre verde).
# tests/unit/cobertura.sh (REG) e quem precisa morder cada um: ele ja teve motivo pra existir
# (a mesma suite discrimina o mutante de CONTEUDO em orchestration/schedule.py - ver C3/C4
# daquele arquivo); aqui o alvo sob mutacao e o MECANISMO, nao o conteudo medido por ele.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"
ORIG="evidence/cobertura.sh"
REG="tests/unit/cobertura.sh"
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.sh"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=2

echo "== baseline: tests/unit/cobertura.sh precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

troca(){ # $1=de  $2=para  - string literal, nao regex
  python3 - "$ORIG" "$1" "$2" <<'PY'
import sys
p, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
if de not in s:
    sys.exit(1)
open(p, "w").write(s.replace(de, para, 1))
PY
}

mutante(){ # $1=nome $2=descricao $3=caso-alvo $4..=comando
  local nome="$1" desc="$2" alvo="$3"; shift 3
  cp -f "$TMP/orig.sh" "$ORIG"
  if ! "$@"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  if cmp -s "$TMP/orig.sh" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  bash -n "$ORIG" || { echo "  FAIL  $nome nao compila (bash -n) apos a mutacao"; F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return; }
  local out rc
  out="$(bash "$REG" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  $nome SOBREVIVEU - $REG passa sem a garantia: $desc"; F=$((F+1))
  elif printf '%s' "$out" | grep -qF "FAIL  $alvo"; then
    echo "  PASS  $nome morto pelo caso certo ($alvo)"; P=$((P+1))
  else
    echo "  FAIL  $nome: $REG reprovou, mas NAO em '$alvo' - kill nao atribuivel"; F=$((F+1))
    printf '%s\n' "$out" | grep '  FAIL  ' | sed 's/^/        visto: /'
  fi
  cp -f "$TMP/orig.sh" "$ORIG"
}

echo "== mutacao: cada garantia removida DEVE fazer tests/unit/cobertura.sh reprovar =="

# MC1 - o piso vai a zero: todo `float(piso)` lido do arquivo de alvos e descartado em favor de
# 0.0. Com piso=0.0, `medido >= piso` e sempre verdadeiro para qualquer percentual medido -
# --check nunca mais reprova nada, qualquer que seja a regressao de cobertura.
mutante MC1 "o piso e MEDIDO/comparado - nao pode ir a zero por baixo do CLI" \
  "piso antigo agora reprova apos remover o caso que o sustentava" \
  troca 'alvos.append((caminho, float(piso)))' \
        'alvos.append((caminho, 0.0))'

# MC2 - `--check` deixa de comparar com o piso: a violacao ainda e IMPRESSA (abaixo continua
# populado), mas o exit code nunca reflete isso - o passo de CI ficaria sempre verde, tornando
# o piso decoracao (o mesmo defeito, na FERRAMENTA, que motivou esta ferramenta sobre o probe).
mutante MC2 "'--check' reprova (exit 1) quando ha alvo abaixo do piso" \
  "piso acima do medido reprova mesmo sem mutacao" \
  troca '    if check:
        sys.exit(1)' \
        '    if False:
        sys.exit(1)'

cp -f "$TMP/orig.sh" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que $REG nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
