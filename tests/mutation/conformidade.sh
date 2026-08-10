#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - conformidade de dois escopos (control/hooks/session-integrity.sh).
#
# Por que existe: a garantia adicionada em 2026-08-10 e "o hook nao declara conformidade sobre
# um escopo que nao olhou". Essa e uma garantia de SEGURANCA - ela decide se o operador e
# avisado de que a arvore root-owned diverge - e a regra de metodo 2 (docs/adr/0020) exige que
# toda garantia de seguranca seja validada por MUTACAO: remova a garantia e o teste tem de
# REPROVAR. Um teste que sobrevive ao mutante nao testa a garantia.
#
# O caso concreto que originou isto: o banner anunciava "48/49 ok | 1 divergentes" com DUAS
# divergencias vivas em /opt/evidence-gate. O comparador managed existia e acertava; o hook
# nao o chamava. A suite nova precisa ser sensivel a reintroducao exata desse silencio.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"
ORIG="control/hooks/session-integrity.sh"
REG="tests/unit/conformidade-managed.sh"
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.sh"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=6

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

# `troca` opera sobre string literal: os alvos tem aspas, colchetes e cifrao, e escapar isso em
# regex de sed foi a origem de mutante-que-nao-aplica em outra suite deste repo.
troca(){ # $1=de  $2=para
  python3 - "$ORIG" "$1" "$2" <<'PY'
import sys
p, de, para = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
open(p, 'w').write(s.replace(de, para, 1))
PY
}

mutante(){ # $1=nome $2=descricao $3=caso-alvo que DEVE reprovar $4..=comando
  local nome="$1" desc="$2" alvo="$3"; shift 3
  cp -f "$TMP/orig.sh" "$ORIG"
  "$@"
  if cmp -s "$TMP/orig.sh" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - o padrao nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
  fi
  if ! bash -n "$ORIG" 2>/dev/null; then
    echo "  FAIL  $nome nao compila apos a mutacao"; F=$((F+1)); cp -f "$TMP/orig.sh" "$ORIG"; return
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
  cp -f "$TMP/orig.sh" "$ORIG"
}

echo "== mutacao: cada garantia removida DEVE quebrar a conformidade de dois escopos =="

# MC1 - o silencio volta a depender so do escopo de usuario. E a reintroducao LITERAL do
# defeito medido: escopo de usuario conforme autorizava calar sobre a arvore root-owned.
mutante MC1 "silencio exige os DOIS escopos conformes" \
  "hook NAO se cala quando so o escopo managed diverge" \
  troca '[ "$RC" -eq 0 ] && [ "$MRC" -eq 0 ] && exit 0' \
        '[ "$RC" -eq 0 ] && exit 0'

# MC2 - o bloco managed some da mensagem. O hook detecta e agrega, mas o operador nunca fica
# sabendo QUAL escopo divergiu: deteccao sem canal e o defeito do ADR 0021 outra vez.
mutante MC2 "o resumo managed chega ao modelo" \
  "  o resumo managed chega ao modelo" \
  troca 'BLOCO_MANAGED="
$MRESUMO' \
        'BLOCO_MANAGED="
sem-resumo'

# MC3 - a guarda de existencia da arvore some, e maquina SEM fase managed passa a reportar
# drift. Falso positivo e o que faz o operador desligar o mecanismo - por isso `absent` e
# `drift` sao estados distintos, e nao um so.
mutante MC3 "ausencia de managed nao e drift" \
  "sem arvore managed, hook fica calado" \
  troca 'if { [ -d "$MTREE" ] || [ -f "$MSET" ]; } && [ -f "$REPO/install/apply-managed.sh" ]; then' \
        'if [ -f "$REPO/install/apply-managed.sh" ]; then'

# MC4 - a guarda volta a testar SO a arvore. Reintroduz o achado critico da revisao
# independente: politica viva com arvore apagada - o pior drift possivel - passa por `absent`,
# o estado que o codigo define como benigno e silencioso.
mutante MC4 "a guarda e a UNIAO dos artefatos julgados" \
  "politica orfa (sem arvore) NAO passa por 'absent'" \
  troca 'if { [ -d "$MTREE" ] || [ -f "$MSET" ]; } && [ -f "$REPO/install/apply-managed.sh" ]; then' \
        'if [ -d "$MTREE" ] && [ -f "$REPO/install/apply-managed.sh" ]; then'

# MC5 - recusa de verificar volta a ser coagida para `drift`. O alerta passa a AFIRMAR
# divergencia exibindo resumo verde e nenhuma evidencia: alerta sem referente.
mutante MC5 "recusa de verificar e not_verified, nao drift" \
  "estado e not_verified (nao drift)" \
  troca '    1) MSTATE="drift" ;;
    *) MSTATE="not_verified" ;;' \
        '    *) MSTATE="drift" ;;'

# MC6 - a guarda volta a exigir bit de execucao num arquivo invocado com `bash`. Fail-open:
# perder o bit desliga a verificacao managed inteira, em silencio.
mutante MC6 "guarda usa -f, coerente com a chamada por bash" \
  "sem bit +x, a verificacao NAO e pulada em silencio" \
  troca '[ -f "$REPO/install/apply-managed.sh" ]; then' \
        '[ -x "$REPO/install/apply-managed.sh" ]; then'

cp -f "$TMP/orig.sh" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
