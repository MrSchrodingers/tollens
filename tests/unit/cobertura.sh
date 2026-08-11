#!/usr/bin/env bash
# MECANISMO - a suite de evidence/cobertura.sh (piso de cobertura de DECISAO por arquivo).
#
# O caso que importa aqui NAO e "o piso bate com o numero medido hoje" (isso e verificado a
# cada execucao do CI, nao e propriedade do MECANISMO). O caso que importa e o DISCRIMINANTE:
# remover um caso de teste que exercita um ramo tem que fazer `--check` REPROVAR. Sem esse
# caso negativo, `evidence/cobertura.sh` podia estar sempre imprimindo "OK" e nada aqui notaria
# - exatamente a forma do defeito que motivou esta ferramenta (mutation testing cego a omissao).
#
# COPIA, NAO MUTACAO NO LUGAR: ao contrario de tests/mutation/*.sh (que editam o ARQUIVO SOB
# TESTE no proprio repositorio, protegidos pelo lock reentrante), aqui removemos um CASO DE
# TESTE de uma COPIA descartavel de tests/unit/schedule.sh. Mutar a suite real, mesmo com
# restauracao por trap, arriscaria uma leitura concorrente de outro processo observar o
# arquivo sem o caso F12 e reportar uma contagem errada por corrida - o mesmo risco que
# tests/lib/lock.sh existe para fechar, mas aqui o alvo mutado seria a PROPRIA suite, nao um
# executavel de producao. Trabalhar em copia elimina a janela por construcao.
#
# ALVO: orchestration/schedule.py + tests/unit/schedule.sh (o par mais rapido dos cinco -
# ~3s por execucao). O caso F12 ("ciclo no grafo do workflow") e o UNICO que exercita a branch
# `if processados != len(nodes): raise ValueError("ciclo detectado"...)` em
# orchestration/schedule.py; nenhum outro caso do arquivo passa por ali (F14/F15 cobrem arestas
# fantasma, que sao rejeitadas ANTES do nivelamento). Removê-lo e o menor mutante possivel que
# ainda muda a cobertura MEDIDA de um jeito atribuivel a um ramo especifico.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

for bin in coverage python3 jq; do
  command -v "$bin" >/dev/null 2>&1 || {
    echo "NAO VERIFICADO: '$bin' ausente - o mecanismo sob teste nao pode ser exercitado." >&2
    exit 2
  }
done

SCRATCH="$(mktemp -d)"; trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/evidence" "$SCRATCH/orchestration/workflows" "$SCRATCH/orchestration/schedule" \
         "$SCRATCH/tests/unit" "$SCRATCH/tests/lib"
cp -f evidence/cobertura.sh          "$SCRATCH/evidence/cobertura.sh"
cp -f orchestration/schedule.py      "$SCRATCH/orchestration/schedule.py"
# orchestration/schedule.py resolve a RAIZ pelo proprio `__file__` (nao por $PWD/cwd) quando
# EVIDENCE_GATE_ROOT nao esta setado - o grupo "os TRES workflows reais" de schedule.sh chama
# o validador SEM override, entao a copia precisa dos dados de producao tambem, ou aquele grupo
# reprova por dado ausente (NAO pelo piso) e o suite falha antes do que queremos medir.
cp -f orchestration/registry.json          "$SCRATCH/orchestration/registry.json"
cp -f orchestration/workflows/*.json       "$SCRATCH/orchestration/workflows/"
cp -f orchestration/schedule/*.json        "$SCRATCH/orchestration/schedule/"
cp -f tests/unit/schedule.sh         "$SCRATCH/tests/unit/schedule.sh"
cp -f tests/lib/lock.sh              "$SCRATCH/tests/lib/lock.sh"
chmod +x "$SCRATCH/evidence/cobertura.sh"

# `medido()`: roda a copia em modo relatorio (piso 0 - nunca reprova por si) e devolve o
# percentual MEDIDO (ja arredondado para baixo a 1 casa, a mesma unidade que --check compara).
medido(){
  COBERTURA_ALVOS="orchestration/schedule.py:0.0" \
  COBERTURA_SUITES="tests/unit/schedule.sh" \
    bash "$SCRATCH/evidence/cobertura.sh" 2>/dev/null \
    | awk -F'\t' '$1=="COBFILE"{print $3}'
}

echo "== baseline: cobertura medida da copia intacta =="
BASE="$(medido)"
[ -n "$BASE" ]; chk "baseline produziu um numero" $? 0

echo
echo "== C1. piso == medido (limite inclusive): --check PASSA =="
COBERTURA_ALVOS="orchestration/schedule.py:$BASE" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" --check >/dev/null 2>&1
chk "piso igual ao medido nao reprova" $? 0

echo
echo "== C2. piso 0.1 ACIMA do medido, sem tocar nada: --check REPROVA (sanity de direcao) =="
ACIMA="$(python3 -c "print(round($BASE + 0.1, 1))")"
COBERTURA_ALVOS="orchestration/schedule.py:$ACIMA" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" --check >/dev/null 2>&1
RC_ACIMA=$?
echo "  (rc observado: $RC_ACIMA)"
chk "piso acima do medido reprova mesmo sem mutacao" "$RC_ACIMA" 1

echo
echo "== mutacao (em COPIA): remove o UNICO caso que exercita 'ciclo detectado' (F12) =="
python3 - "$SCRATCH/tests/unit/schedule.sh" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
bloco = '''OUT12="$(roda f12-ciclo 2>&1)"; RC12=$?
chk "F12 ciclo no grafo do workflow: RECUSADO" "$RC12" 1
printf '%s' "$OUT12" | grep -qF "ciclo detectado"
chk "  F12 diagnostica ciclo" $? 0

'''
if bloco not in s:
    print("BLOCO_NAO_ENCONTRADO", file=sys.stderr)
    sys.exit(1)
s = s.replace(bloco, "", 1)
# dois `chk` removidos - a copia precisa continuar se autovalidando (EXPECTED) para que o
# oraculo de "suite falhou" de evidence/cobertura.sh nao mascare o resultado que queremos medir.
s = s.replace("EXPECTED=29", "EXPECTED=27", 1)
open(p, "w", encoding="utf-8").write(s)
PY
chk "bloco F12 removido da copia" $? 0

echo
echo "== C3. cobertura MEDIDA cai na copia mutada =="
# controle: a copia mutada ainda precisa se autovalidar (PASS=27/27) - senao o proximo --check
# reprovaria por SUITE QUEBRADA (NOT_VERIFIED, exit 2), nao pelo piso, e o caso deixaria de ser
# atribuivel ao mecanismo de cobertura.
bash "$SCRATCH/tests/unit/schedule.sh" >"$SCRATCH/copia-mutada.log" 2>&1
RC_SUITE_MUTADA=$?
chk "copia mutada ainda se autovalida (PASS=27/27, exit 0)" "$RC_SUITE_MUTADA" 0
BASE2="$(medido)"
[ -n "$BASE2" ] && python3 -c "import sys; sys.exit(0 if float('$BASE2') < float('$BASE') else 1)"
chk "medido caiu apos remover F12 (antes=$BASE depois=$BASE2)" $? 0

echo
echo "== C4. MESMO piso que passava em C1 agora REPROVA (o discriminante) =="
COBERTURA_ALVOS="orchestration/schedule.py:$BASE" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" --check >"$SCRATCH/check-c4.log" 2>&1
RC_C4=$?
[ "$RC_C4" -eq 1 ]; chk "piso antigo agora reprova apos remover o caso que o sustentava" $? 0

echo
echo "== C5. a reprovacao NOMEIA o arquivo abaixo do piso =="
grep -qF "orchestration/schedule.py" "$SCRATCH/check-c4.log"
chk "saida nomeia orchestration/schedule.py como abaixo do piso" $? 0

echo
echo "== C6. SEM --check (modo relatorio), a mesma copia mutada NAO reprova =="
COBERTURA_ALVOS="orchestration/schedule.py:$BASE" \
COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" >/dev/null 2>&1
chk "modo relatorio (sem --check) nunca reprova, mesmo abaixo do piso" $? 0

echo
echo "== C7. 'coverage' ausente do PATH: NAO_VERIFICADO (exit 2), nunca PASS nem FAIL silencioso =="
COVDIR="$(dirname "$(command -v coverage)")"
SEMCOV="$(printf '%s\n' "$PATH" | tr ':' '\n' | grep -vF "$COVDIR" | paste -sd: -)"
PATH="$SEMCOV" COBERTURA_SUITES="tests/unit/schedule.sh" \
  bash "$SCRATCH/evidence/cobertura.sh" >"$SCRATCH/c7.log" 2>&1
RC_C7=$?
[ "$RC_C7" -eq 2 ]; chk "coverage ausente produz exit 2 (got=$RC_C7)" $? 0
grep -qF "NAO VERIFICADO" "$SCRATCH/c7.log"
chk "  C7 rotula a lacuna como NAO VERIFICADO, nao como reprovacao" $? 0

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=11
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "mecanismo de cobertura verde ($P/$EXPECTED)" || echo "mecanismo de cobertura VERMELHO"
exit "$F"
