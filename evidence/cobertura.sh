#!/usr/bin/env bash
# COBERTURA DE DECISAO (branch coverage) sobre os executaveis de evidencia listados em ALVOS
# abaixo. Existe porque mutation testing (tests/mutation/*.sh) e estruturalmente CEGO A
# OMISSAO: um mutante so pode morrer se algum teste EXERCITAR o ramo mutado; um ramo que
# nenhum teste alcanca nunca produz mutante morto nem vivo - ele nem aparece na contagem.
#
# Prova medida (motivo desta ferramenta): apagar as duas deteccoes de violacao em
# evidence/probes/github-ruleset.py (`elif enforcement != "active":` e `elif cucb != "never":`,
# trocadas por `elif False:`) deixava as 78 assercoes de tests/unit/fronteira-viva.sh em
# PASS=78 FAIL=0 e os 11 mutantes de tests/mutation/fronteira-viva.sh todos mortos, com um
# ruleset `enforcement=evaluate` + `current_user_can_bypass=always` saindo PASS em vez de FAIL.
# Nenhum teste jamais exercitava um ruleset com esses dois campos fora do valor esperado.
# `coverage` mediu 79% no arquivo, com as duas linhas na lista Missing. Este script fecha a
# lacuna de OBSERVACAO (o ramo nao testado agora reprova o piso) - NAO a lacuna de teste em si
# (escrever o caso que falta e correcao de conteudo do validador, fora do escopo desta mudanca:
# ver o probe medido e o executavel proibido de tocar por esta tarefa).
#
# LIMITE DECLARADO - repita-se onde este mecanismo for apresentado: cobertura de decisao PROVA
# que um ramo foi EXECUTADO por algum teste. NAO prova que a ASSERCAO daquele teste esta
# correta. Um teste que executa `elif enforcement != "active":` e nao verifica que o resultado
# vira FAIL passaria neste piso do mesmo jeito. Isto e PISO, nao TETO: torna a omissao
# DETECTAVEL (ramo nunca exercitado por teste nenhum), nunca a torna IMPOSSIVEL (ramo
# exercitado e mal testado continua passando). A garantia de que a assercao certa existe
# continua sendo tests/unit/*.sh (o oraculo de comportamento) e tests/mutation/*.sh (mutation
# testing, que so pode avaliar ramos que a cobertura aqui prova alcancados).
#
# MECANICA - por que `coverage run` comum nao basta: toda suite deste repositorio invoca os
# executaveis medidos em SUBPROCESSO (`python3 "$V" ...`, nunca via import). `coverage run` so
# instrumenta o processo que ele mesmo inicia. Medir subprocesso exige o auto-arranque do
# coverage.py: um `sitecustomize.py` num diretorio somado a PYTHONPATH chama
# `coverage.process_startup()`, que le COVERAGE_PROCESS_START (um coveragerc com
# `parallel = True`) e liga a medicao antes de qualquer outro codigo do processo filho rodar.
# Cada processo grava seu proprio `.coverage.<host>.<pid>...`; `coverage combine` os funde
# depois que as suites terminam.
#
# POR QUE `source = <raiz do repo>` no lugar de `include` no coveragerc apontado por
# COVERAGE_PROCESS_START: medido nesta sessao - com `include` configurado NAQUELE arquivo, os
# processos filhos nao gravavam nenhum dado (0 bytes em disco), mesmo saindo 0. `source`
# restringe o rastreamento a arvore do repositorio (evita instrumentar biblioteca padrao e
# pacotes de terceiros - lento, e desnecessario) e sempre grava dado; o filtro por arquivo
# especifico e aplicado depois, na leitura (`coverage json --include=...`).
#
# PISO, NAO TETO, E MEDIDO, NUNCA ARBITRADO: cada piso abaixo e o numero MEDIDO nesta sessao
# (ver RESULTADO/EVIDENCIA do commit que introduziu este arquivo), arredondado PARA BAIXO a uma
# casa decimal. So regride se um ramo hoje coberto deixar de ser exercitado por teste algum -
# nunca por variacao de ponto flutuante entre execucoes: a comparacao tambem arredonda o valor
# fresco para baixo a uma casa antes de comparar (ver `arredonda_baixo` no bloco Python abaixo).
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh). Tomado UMA vez aqui
# e mantido (reentrante por EVIDENCE_GATE_LOCK=held) por toda a bateria de suites abaixo -
# soltar e retomar entre cada suite abriria uma janela de corrida com outro processo.
. "$(dirname "$0")/../tests/lib/lock.sh"
export LC_ALL=C

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# ALVOS e SUITES sao AUTOSSUFICIENTES por padrao - producao nunca precisa das variaveis abaixo.
# COBERTURA_ALVOS e COBERTURA_SUITES existem SO para tests/unit/cobertura.sh (mecanismo) e
# tests/mutation/cobertura.sh (mutacao) validarem sobre um subconjunto rapido e, no caso da
# suite unitaria, uma COPIA descartavel. NAO USAR EM CI REAL - mesma doutrina de
# EVIDENCE_GATE_LOCK_FILE em tests/lib/lock.sh: apontar a medicao de producao para um
# subconjunto arbitrario desliga a garantia, nao a configura.
ALVOS="${COBERTURA_ALVOS:-$(cat <<'EOF'
evidence/probes/github-ruleset.py:78.8
evidence/validate-claims.py:77.7
evidence/validate-literature.py:92.3
evidence/runtime-probes/declared-capabilities.py:90.0
orchestration/schedule.py:88.4
EOF
)}"

SUITES="${COBERTURA_SUITES:-$(cat <<'EOF'
tests/unit/fronteira-viva.sh
tests/unit/claims.sh
tests/unit/literatura.sh
tests/unit/capabilities.sh
tests/unit/schedule.sh
tests/unit/runtime-ports.sh
EOF
)}"

command -v coverage >/dev/null 2>&1 || {
  echo "NAO VERIFICADO: 'coverage' ausente do PATH - a medicao de decisao nao pode ser feita." >&2
  exit 2
}
command -v python3 >/dev/null 2>&1 || {
  echo "NAO VERIFICADO: python3 ausente do PATH - nada aqui pode rodar." >&2
  exit 2
}

TMP="$(mktemp -d)" || exit 1
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/site" "$TMP/data"

cat > "$TMP/site/sitecustomize.py" <<'PY'
# Auto-arranque de cobertura em subprocesso - ver o cabecalho de evidence/cobertura.sh.
import coverage
coverage.process_startup()
PY

cat > "$TMP/coveragerc" <<EOF
[run]
branch = True
parallel = True
relative_files = True
data_file = $TMP/data/.coverage
source =
    $PWD
EOF

export COVERAGE_PROCESS_START="$TMP/coveragerc"
export PYTHONPATH="$TMP/site${PYTHONPATH:+:$PYTHONPATH}"

printf '%s\n' "$ALVOS" | sed '/^$/d' > "$TMP/alvos.txt"

echo "== executando as suites que exercitam os alvos (subprocesso instrumentado) =="
falhou=""
while IFS= read -r suite; do
  [ -z "$suite" ] && continue
  echo "-- $suite --"
  if ! bash "$suite"; then
    falhou="$falhou $suite"
  fi
  echo
done <<<"$SUITES"

if [ -n "$falhou" ]; then
  echo "NAO VERIFICADO: suite(s) abaixo saiu(ram) vermelha(s) - a medicao de cobertura nao e" >&2
  echo "confiavel sobre um oraculo que ja falhou:$falhou" >&2
  exit 2
fi

echo "== combinando dados de cobertura de todos os subprocessos =="
if ! coverage combine --rcfile="$TMP/coveragerc" >"$TMP/combine.out" 2>"$TMP/combine.err"; then
  echo "NAO VERIFICADO: 'coverage combine' falhou:" >&2
  cat "$TMP/combine.out" "$TMP/combine.err" >&2
  exit 2
fi
grep -q '^Combined data file' "$TMP/combine.out" || {
  echo "NAO VERIFICADO: nenhum dado de subprocesso foi combinado - o mecanismo de" >&2
  echo "auto-arranque (sitecustomize/COVERAGE_PROCESS_START) nao disparou." >&2
  cat "$TMP/combine.out" >&2
  exit 2
}

INCLUDE="$(awk -F: '{print $1}' "$TMP/alvos.txt" | paste -sd, -)"
if ! coverage json --rcfile="$TMP/coveragerc" --include="$INCLUDE" -o "$TMP/coverage.json" \
     >"$TMP/json.out" 2>"$TMP/json.err"; then
  echo "NAO VERIFICADO: 'coverage json' falhou:" >&2
  cat "$TMP/json.out" "$TMP/json.err" >&2
  exit 2
fi

echo
python3 - "$TMP/coverage.json" "$TMP/alvos.txt" "$CHECK" <<'PY'
import json
import math
import sys

cov_path, alvos_path, check = sys.argv[1], sys.argv[2], sys.argv[3] == "1"


def arredonda_baixo(x, casas=1):
    # Arredonda PARA BAIXO, nunca para o mais proximo: o piso nao pode ser satisfeito por
    # jitter de ponto flutuante entre execucoes (ex.: 78.849999... nao pode virar "78.9").
    fator = 10 ** casas
    return math.floor(x * fator) / fator


with open(alvos_path, encoding="utf-8") as f:
    alvos = []
    for linha in f:
        linha = linha.strip()
        if not linha:
            continue
        caminho, piso = linha.rsplit(":", 1)
        alvos.append((caminho, float(piso)))

with open(cov_path, encoding="utf-8") as f:
    dados = json.load(f)
arquivos = dados.get("files", {})

linhas = []
abaixo = []
for caminho, piso in alvos:
    info = arquivos.get(caminho)
    if info is None:
        # Alvo declarado mas ausente do relatorio: nenhuma suite o exercitou (ou o caminho
        # nao existe mais). Lacuna de MEDICAO, nao "0% medido em silencio" - mas o efeito
        # pratico e o mesmo do fail-closed: conta como abaixo do piso, nunca como isento.
        bruto = 0.0
    else:
        bruto = info["summary"]["percent_covered"]
    medido = arredonda_baixo(bruto)
    ok = medido >= piso
    if not ok:
        abaixo.append(caminho)
    linhas.append((caminho, medido, bruto, piso, ok))

largura = max((len(c) for c, *_ in linhas), default=0)
print(f"{'arquivo'.ljust(largura)}  medido   bruto    piso  status")
for caminho, medido, bruto, piso, ok in linhas:
    status = "OK" if ok else "ABAIXO DO PISO"
    print(f"{caminho.ljust(largura)}  {medido:5.1f}%  {bruto:6.2f}%  {piso:5.1f}%  {status}")
    print(f"COBFILE\t{caminho}\t{medido:.1f}\t{piso:.1f}\t{status}")

print()
if abaixo:
    print("cobertura de decisao ABAIXO DO PISO em: " + ", ".join(abaixo))
    if check:
        sys.exit(1)
    print("(modo relatorio - rode com --check para reprovar)")
    sys.exit(0)
print("cobertura de decisao: todos os alvos no piso ou acima")
sys.exit(0)
PY
