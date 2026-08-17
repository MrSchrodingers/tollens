#!/usr/bin/env bash
# Mutacao dos instaladores. Cada mutante ataca uma garantia existente e deve morrer por um
# oraculo atribuivel a essa mesma propriedade.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"
# ARENA: muta uma COPIA da arvore, nunca a arvore candidata. Ver tests/lib/arena.sh para os
# seis incidentes medidos que motivaram isto.
. "$(dirname "$0")/../lib/arena.sh"

ORIG="install/apply.sh"
ORIG_M="install/apply-managed.sh"
REG="tests/unit/regressao-gate.sh"
REG_TX="tests/unit/managed-transaction.sh"
REG_TRUST="tests/unit/managed-root-trust.sh"
TMP="$(mktemp -d)"
trap 'cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null; cp -f "$TMP/orig-managed.sh" "$ORIG_M" 2>/dev/null; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.sh"
cp -f "$ORIG_M" "$TMP/orig-managed.sh"

P=0
F=0
EXPECTED_MUTANTS=5
restore_common(){ cp -f "$TMP/orig.sh" "$ORIG"; }
restore_managed(){ cp -f "$TMP/orig-managed.sh" "$ORIG_M"; }
kill_ok(){ echo "  PASS  $1"; P=$((P+1)); }
kill_fail(){ echo "  FAIL  $1"; F=$((F+1)); }
# TERCEIRO ESTADO. MI4 e MI5 exigem oraculo ROOT (tests/unit/managed-root-trust.sh), que sai SKIP
# quando `sudo -n` nao esta disponivel. Ate 2026-08-14 os dois reportavam
# "sobreviveu OU oraculo root foi indisponivel" e contavam como FALHA - duas proposicoes
# diferentes colapsadas num veredito so.
#
# Mutante que SOBREVIVEU e defeito: a garantia nao esta testada. Oraculo AUSENTE e NAO VERIFICADO:
# nao se sabe. Colapsar os dois em FAIL e exatamente o que o contrato de tres estados deste
# repositorio existe para impedir, e produzia vermelho permanente nesta estacao - o tipo de
# vermelho que se aprende a ignorar, e que no dia em que significar outra coisa nao se distingue.
#
# NAO_MEDIDO nunca vira verde: o exit final e 2 se houver qualquer um, nunca 0.
NAO_MEDIDOS=0
nao_medido(){ echo "  NAO MEDIDO  $1"; NAO_MEDIDOS=$((NAO_MEDIDOS+1)); }
oraculo_root_disponivel(){ sudo -n true 2>/dev/null; }

echo "== baseline =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  regressao baseline verde"; else echo "  FAIL  regressao baseline vermelha"; exit 1; fi
if bash "$REG_TX" >/dev/null 2>&1; then echo "  PASS  transacao managed baseline verde"; else echo "  FAIL  transacao managed baseline vermelha"; exit 1; fi
if bash "$REG_TRUST" >/dev/null 2>&1; then echo "  PASS  trust boundary baseline verde/skip explicito"; else echo "  FAIL  trust boundary baseline vermelha"; exit 1; fi

echo "== MI1. dry-run nao pode atravessar o portao de escrita =="
restore_common
sed -i 's|^if \[ "$DRY" -eq 1 \]; then$|if false; then|' "$ORIG"
if cmp -s "$TMP/orig.sh" "$ORIG"; then
  kill_fail "MI1 NAO FOI APLICADO"
elif ! bash -n "$ORIG" 2>/dev/null; then
  kill_fail "MI1 nao compila"
else
  out="$(bash "$REG" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then kill_fail "MI1 SOBREVIVEU"
  elif printf '%s' "$out" | grep -q "FAIL.*orfao continua no disco\|FAIL.*estado identico"; then kill_ok "MI1 morto pelo dry-run destrutivo"
  else kill_fail "MI1 reprovou por causa nao atribuivel"; fi
fi
restore_common

echo "== MI2. falha do delegado deve restaurar o estado anterior =="
restore_managed
python3 - "$ORIG_M" <<'PY'
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
alvo='  rollback && exit "$rc" || exit 70\n'
if s.count(alvo)!=1: raise SystemExit(f'ANCORA MI2 NAO CASOU ({s.count(alvo)})')
s=s.replace(alvo,'  exit "$rc"  # MUTANTE: omite rollback\n')
open(p,'w',encoding='utf-8').write(s)
PY
out="$(bash "$REG_TX" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "FAIL first-deploy-tree\|FAIL first-deploy-policy\|FAIL existing-tree\|FAIL existing-policy"; then
  kill_ok "MI2 morto pela restauracao transacional"
else
  kill_fail "MI2 sobreviveu ou morreu sem atribuicao"
fi
restore_managed

echo "== MI3. modo exato deve ser pos-condicao, nao intencao de chmod =="
restore_managed
python3 - "$ORIG_M" <<'PY'
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
alvo='if [ -n "$mode_bad" ]; then\n'
if s.count(alvo)!=1: raise SystemExit(f'ANCORA MI3 NAO CASOU ({s.count(alvo)})')
s=s.replace(alvo,'if false; then  # MUTANTE: ignora modo inesperado\n')
open(p,'w',encoding='utf-8').write(s)
PY
out="$(bash "$REG_TX" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "FAIL exact-mode-rc\|FAIL exact-mode-cleanup"; then
  kill_ok "MI3 morto pela pos-condicao de modo"
else
  kill_fail "MI3 sobreviveu ou morreu sem atribuicao"
fi
restore_managed

echo "== MI4. execucao root nao pode aceitar fonte gravavel pelo ator =="
restore_managed
python3 - "$ORIG_M" <<'PY'
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
alvo='if [ "$REAL" -eq 1 ] && [ "$(id -u)" -eq 0 ]; then\n'
if s.count(alvo)!=1: raise SystemExit(f'ANCORA MI4 NAO CASOU ({s.count(alvo)})')
s=s.replace(alvo,'if false; then  # MUTANTE: remove trust preflight\n',1)
open(p,'w',encoding='utf-8').write(s)
PY
out="$(bash "$REG_TRUST" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "FAIL user-owned-source-rejected\|FAIL source-symlink-rejected\|FAIL writable-source-rejected"; then
  kill_ok "MI4 morto pela fronteira de fonte privilegiada"
else
  if oraculo_root_disponivel; then
    kill_fail "MI4 sobreviveu com o oraculo root DISPONIVEL - a garantia nao esta testada"
  else
    nao_medido "MI4: oraculo root indisponivel (sudo -n nega) - nao se sabe se morre"
  fi
fi
restore_managed

echo "== MI5. owner OU group incorreto deve ser detectado com -print no conjunto inteiro =="
restore_managed
python3 - "$ORIG_M" <<'PY'
import sys
p=sys.argv[1]; s=open(p,encoding='utf-8').read()
alvo='owner_bad="$(find "$OPT" -xdev \\( \\! -user root -o \\! -group root \\) -print -quit 2>/dev/null || true)"'
if s.count(alvo)!=1: raise SystemExit(f'ANCORA MI5 NAO CASOU ({s.count(alvo)})')
mut='owner_bad="$(find "$OPT" -xdev \\! -user root -o \\! -group root -print -quit 2>/dev/null || true)"'
s=s.replace(alvo,mut)
open(p,'w',encoding='utf-8').write(s)
PY
out="$(bash "$REG_TRUST" 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "FAIL wrong-owner-rejected"; then
  kill_ok "MI5 morto pelo caso owner!=root, group=root"
else
  if oraculo_root_disponivel; then
    kill_fail "MI5 sobreviveu com o oraculo root DISPONIVEL - a garantia nao esta testada"
  else
    nao_medido "MI5: oraculo root indisponivel (sudo -n nega) - nao se sabe se morre"
  fi
fi
restore_managed

echo
printf 'mutantes_esperados=%s  mortos=%s  falhas=%s  nao_medidos=%s\n' \
       "$EXPECTED_MUTANTS" "$P" "$F" "$NAO_MEDIDOS"
# INVARIANTE DE CONTAGEM, e ele estava INALCANCAVEL. Ate 2026-08-17 o unico ponto que comparava
# com EXPECTED_MUTANTS ficava no ramo verde, depois dos ramos de falha e de nao-medido. Nesta
# estacao, onde `sudo -n` nega e NAO_MEDIDOS e sempre 2, esse ponto NUNCA era alcancado - e
# revisao independente mostrou que P=3, P=1 e P=0 produziam a MESMA saida e o MESMO exit 2:
#
#   A) real (P=3,F=0,N=2)  -> NAO VERIFICADA (2 de 5) / mortos: 3   exit=2
#   B) (P=1,F=0,N=2)       -> NAO VERIFICADA (2 de 5) / mortos: 1   exit=2
#   C) (P=0,F=0,N=2)       -> NAO VERIFICADA (2 de 5) / mortos: 0   exit=2
#
# Antes do terceiro estado, `[ "$P" -eq "$EXPECTED_MUTANTS" ]` gateava tudo e qualquer perda saia
# 1. O terceiro estado corrigiu a confusao entre "sobreviveu" e "nao medido" e, no caminho,
# perdeu o invariante. Aqui ele volta, e ANTES dos tres ramos: mutante que nao executou nao e
# nem falha nem lacuna de oraculo - e caso que sumiu, e isso e sempre vermelho.
if [ $((P + F + NAO_MEDIDOS)) -ne "$EXPECTED_MUTANTS" ]; then
  echo "CONTAGEM INESPERADA: $P mortos + $F falhas + $NAO_MEDIDOS nao-medidos != $EXPECTED_MUTANTS"
  echo "  Algum mutante nao executou. Caso removido, ancora quebrada, ou saida antecipada."
  exit 1
fi

# TRES SAIDAS, na convencao deste repositorio: 0 verde, 1 vermelho, 2 NAO VERIFICADO.
# A ordem importa. FALHA tem precedencia sobre NAO MEDIDO: um mutante que comprovadamente
# sobreviveu e defeito medido, e nao pode ser rebaixado a "nao se sabe" so porque outro caso
# ficou sem oraculo. NAO MEDIDO nunca sai 0 - medicao parcial declarada nao e aprovacao.
if [ "$F" -ne 0 ]; then
  echo "mutacao do instalador VERMELHA ($F mutante(s) sobreviveram com o oraculo disponivel)"
  exit 1
fi
if [ "$NAO_MEDIDOS" -ne 0 ]; then
  echo "mutacao do instalador NAO VERIFICADA ($NAO_MEDIDOS de $EXPECTED_MUTANTS sem oraculo root)"
  echo "  mortos: $P. Rode com sudo nao-interativo disponivel para medir os demais."
  exit 2
fi
if [ "$P" -eq "$EXPECTED_MUTANTS" ]; then
  echo "mutacao do instalador verde ($P/$EXPECTED_MUTANTS)"
  exit 0
fi
echo "CONTAGEM INESPERADA: mortos=$P, esperado $EXPECTED_MUTANTS"
exit 1
