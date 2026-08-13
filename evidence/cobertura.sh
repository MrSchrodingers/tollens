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
# vira FAIL passaria neste piso do mesmo jeito. Isto E PISO, nao TETO: torna a omissao
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
# ===========================================================================================
# TRES CAMADAS, NAO UMA - registrado depois que o portao final da onda 5 mediu a lacuna
# estrutural do desenho original (somente a camada 1 abaixo). As tres compoem; nenhuma
# substitui as outras.
#
# CAMADA 1 - PISO PERCENTUAL POR ARQUIVO (ALVOS). `percent_covered >= piso` e SATISFAZIVEL
# com um numero arbitrario de ramos nunca exercitados, desde que haja codigo coberto
# suficiente ao lado para diluir o denominador - PROVADO nesta sessao: inserir UM ramo de
# decisao nao exercitado em orchestration/schedule.py mede 87.8% (piso 88.4%, ABAIXO DO PISO,
# `--check` sai 1); o MESMO ramo, intocado, mais 30 statements cobertos no topo do modulo mede
# 88.8% (OK, `--check` sai 0) - o ramo nunca exercitado e identico nos dois casos; so o
# denominador mudou. Por isso a comparacao desta camada deixou de ser `medido >= piso` e
# passou a ser `medido == piso` (exato, na mesma casa decimal ja truncada por
# `arredonda_baixo`): TODA mudanca de cobertura - regressao OU melhoria - reprova ate alguem
# reapertar o piso explicitamente. O CUSTO disto e real e deliberado: um PR que adiciona
# codigo TOTALMENTE coberto ainda reprova este portao, pedindo que o piso seja movido a mao
# (ver "COMO REAPERTAR" abaixo) - e um portao que reprova em toda melhoria de cobertura e
# um portao que alguem aprende a desligar. A alternativa avaliada e descartada foi uma BANDA
# DE TOLERANCIA (piso <= medido <= piso+X): ela reintroduz folga por construcao (ate X
# unidades, o mesmo defeito medido nesta sessao em escala menor) e nao teria capturado a causa
# real - dois commits (734283e, ff96a5d) subiram a cobertura de dois alvos sem que o piso
# fosse reapertado, e `git diff` entre o commit que mediu os pisos e HEAD sobre este arquivo
# retornava VAZIO: o piso simplesmente nunca foi tocado. Igualdade exata torna essa omissao
# IMPOSSIVEL de passar despercebida - o portao reprova na proxima execucao, nao na proxima
# revisao que lembrar de checar.
#
# COMO REAPERTAR (depois de qualquer mudanca legitima de cobertura): rode
# `bash evidence/cobertura.sh` (modo relatorio, sem --check) e copie a coluna "medido" da
# saida para o piso correspondente em ALVOS abaixo. NAO copiar as cegas: olhar o que mudou
# (`coverage json`, coluna Missing) faz parte do reaperto - a CAMADA 2 abaixo cobre a metade
# dessa disciplina que um numero unico nao consegue forcar.
#
# CAMADA 2 - PREDICADO ABSOLUTO SOBRE RAMOS/LINHAS (ISENCOES), por arquivo, com lista de
# excecao explicita. A CAMADA 1 prova que a PORCENTAGEM nao mudou sem reaperto; nao prova que
# o ramo NOVO introduzido por um reaperto descuidado foi de fato olhado - um reaperto que so
# copia o numero novo (sem olhar o diff de cobertura) ainda deixaria passar o cenario acima.
# Esta camada fecha essa lacuna: todo `missing_lines`/`missing_branches` que `coverage json`
# reporta para um alvo precisa estar OU coberto por teste OU listado em ISENCOES com motivo
# escrito - nao ha caminho de "diluir no denominador" aqui, porque nao ha denominador: e
# associacao por item (linha ou arco de ramo), nao razao. Isto implementa, para os arquivos
# abaixo cobertos por esta camada, o predicado do ADR 0028 ("todo ramo de decisao que
# distingue PASS/FAIL/NOT_VERIFIED precisa ser executado, nas duas direcoes") na forma que a
# medicao hoje permite: TODO ramo/linha ausente precisa estar contabilizado, nao so os que
# distinguem PASS/FAIL - contabilizar de mais (exigir justificativa para plumbing irrelevante)
# e o preco de nao ter, ainda, um classificador automatico de "este ramo decide o veredito".
#
# ISENCOES sao chaveadas por NUMERO DE LINHA / ARCO DE LINHAS - fragil a qualquer edicao que
# desloque linhas ACIMA do item isento, por desenho, nao por descuido: o mesmo tradeoff que
# `_writes_conflict` de orchestration/schedule.py documenta ("o custo de [reprovar] por engano
# e baixo, o de um conflito nao detectado e alto"). Uma isencao que fica orfa (o numero de
# linha deslocou, o item real ja nao esta mais em `missing_*`) e inocua - so um item que
# nunca mais casa com nada. Um ramo NOVO que por acidente caia num numero de linha ja isento
# (mesmo motivo antigo, item diferente) e o unico jeito deste desenho falhar ABERTO; o
# mitigante e o motivo de cada isencao citar a INTENCAO ("debito herdado ao piso absoluto,
# nao investigado individualmente"), nunca o conteudo especifico da linha - um novo ramo que
# caia ali herda a mesma cobertura de intencao ("ainda nao investigado"), nao uma alegacao
# falsa sobre o que ele faz.
#
# Nem todo ALVO tem ISENCOES povoadas hoje. Populado (nesta tarefa): orchestration/schedule.py
# - unico arquivo, dos cinco, medido, estavel (nao em edicao concorrente) e ja usado como alvo
# de fixture desta propria suite de mecanismo. DEFERIDO, com razao e numero, para os outros
# quatro:
#   - evidence/probes/github-ruleset.py (60 itens: 36 linhas + 24 ramos, medido nesta sessao) e
#     evidence/validate-claims.py (108 itens: 67 linhas + 41 ramos) estao em ISENCOES via
#     ABSOLUTO_PENDENTE: outro agente corrige cada um EM PARALELO nesta mesma onda (fora do
#     escopo desta tarefa tocar); povoar a isencao agora citaria numeros de linha que a
#     integracao vai deslocar por completo, produzindo falsos positivos macicos sobre o
#     trabalho alheio em vez de sinal util. Reapertar junto com o piso percentual (ver "COMO
#     REAPERTAR").
#   - evidence/validate-literature.py (22 itens: 12 linhas + 10 ramos) e
#     evidence/runtime-probes/declared-capabilities.py (21 itens: 13 linhas + 8 ramos) estao
#     ESTAVEIS (sem edicao concorrente) mas fora do escopo desta correcao pontual do mecanismo
#     - estender a CAMADA 2 a eles e decisao de quem responde por aquele arquivo, nao desta
#     tarefa (fechar a folga de construcao do piso, nao auditar os cinco alvos ramo a ramo).
#     Tambem via ABSOLUTO_PENDENTE, com o numero acima citado no motivo.
# Arquivo em ABSOLUTO_PENDENTE continua sob a CAMADA 1 (piso percentual exato) normalmente -
# so a CAMADA 2 (por ramo/linha) fica de fora, e a saida rotula isso como PENDENTE, nunca como
# "OK" silencioso.
#
# CAMADA 3 - COMPLETUDE DE ALVOS. ALVOS e EXCLUSOES sao digitados a mao; nada impedia um probe
# novo nascer sem piso, em silencio. Esta camada varre evidence/, orchestration/ e execution/
# (RAIZES abaixo) por executaveis Python (candidato = tem `if __name__ == "__main__":` OU e
# marcado executavel - as duas formas usadas por alvos reais deste repositorio: os quatro
# validadores por `__main__` sem +x, `render.py`/`github-ruleset.py` por +x) e por outros
# executaveis marcados +x (ex.: scripts shell) - excluindo `hooks/` e `evidence/telemetry/`
# (dominio de governanca diferente: hooks de sessao e telemetria nao sao probes de evidencia)
# e o proprio evidence/cobertura.sh. Todo candidato precisa estar em ALVOS OU em EXCLUSOES com
# motivo escrito; reprovar em silencio e o defeito que esta camada fecha, ficar de fora COM
# motivo escrito e aceitavel (ver EXCLUSOES abaixo: orchestration/render.py e os quatro
# executaveis de execution/document-tools/ ficam de fora hoje, nomeados, com razao).
# ===========================================================================================
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh). Tomado UMA vez aqui
# e mantido (reentrante por TOLLENS_LOCK=held) por toda a bateria de suites abaixo -
# soltar e retomar entre cada suite abriria uma janela de corrida com outro processo.
. "$(dirname "$0")/../tests/lib/lock.sh"
export LC_ALL=C

CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1

# ALVOS, SUITES, RAIZES, EXCLUSOES, ISENCOES e ABSOLUTO_PENDENTE sao AUTOSSUFICIENTES por
# padrao - producao nunca precisa das variaveis abaixo. Os overrides COBERTURA_* existem SO
# para tests/unit/cobertura.sh (mecanismo) e tests/mutation/cobertura.sh (mutacao) validarem
# sobre um subconjunto rapido e, no caso da suite unitaria, uma COPIA descartavel. NAO USAR EM
# CI REAL - mesma doutrina de TOLLENS_LOCK_FILE em tests/lib/lock.sh: apontar a medicao
# de producao para um subconjunto arbitrario desliga a garantia, nao a configura.
ALVOS="${COBERTURA_ALVOS:-$(cat <<'EOF'
evidence/probes/github-ruleset.py:86.0
evidence/validate-claims.py:81.4
evidence/validate-literature.py:92.3
evidence/runtime-probes/declared-capabilities.py:92.6
orchestration/schedule.py:88.4
evidence/validate-adapters.py:69.3
EOF
)}"

SUITES="${COBERTURA_SUITES:-$(cat <<'EOF'
tests/unit/fronteira-viva.sh
tests/unit/claims.sh
tests/unit/literatura.sh
tests/unit/capabilities.sh
tests/unit/schedule.sh
tests/unit/runtime-ports.sh
tests/unit/document-tools.sh
EOF
)}"

RAIZES="${COBERTURA_RAIZES:-evidence orchestration execution}"

EXCLUSOES="${COBERTURA_EXCLUSOES:-$(cat <<'EOF'
orchestration/render.py|nao avaliado nesta tarefa: o piso de cobertura de decisao (ADR 0028) fechou a folga do mecanismo ja existente; promover um executavel novo a ALVO exige medir o piso alcancavel dele, investigacao propria, fora do escopo desta correcao pontual
execution/document-tools/doctool.sh|script shell - coverage.py (branch coverage, esta ferramenta) so mede Python; fora do dialeto medido aqui
execution/document-tools/probe_sheet.py|nao avaliado nesta tarefa - mesma razao de orchestration/render.py
execution/document-tools/profile_sheet.py|nao avaliado nesta tarefa - mesma razao de orchestration/render.py
execution/document-tools/query_sheet.py|nao avaliado nesta tarefa - mesma razao de orchestration/render.py
EOF
)}"

# ISENCOES: cada linha "arquivo|tipo|alvo|motivo" (tipo = linha|ramo; alvo = numero da linha
# ou "de->para" do arco de ramo, no MESMO formato que `coverage json` usa em missing_branches).
# O motivo "heranca-piso-absoluto-2026-08-11" e o mesmo nas 35 linhas de orchestration/
# schedule.py abaixo porque a razao E a mesma para todas: cada item listado ja estava em
# `missing_lines`/`missing_branches` no momento em que esta camada entrou em vigor (medido
# contra HEAD desta tarefa - ver `git log -- evidence/cobertura.sh` pela mensagem que introduz
# o piso absoluto), nenhum foi investigado individualmente aqui, e cobrir ou justificar cada um
# por si e trabalho futuro. Qualquer ramo/linha NOVO que apareca em missing_lines/
# missing_branches a partir de aqui NAO herda esta isencao (o numero de linha novo nao esta
# nesta lista) e reprova ate ganhar cobertura ou uma entrada com motivo ESPECIFICO - nunca
# "heranca-piso-absoluto-2026-08-11", que descreve so o que ja existia nesta data.
ISENCOES="${COBERTURA_ISENCOES:-$(cat <<'EOF'
orchestration/schedule.py|linha|102|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|103|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|223|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|227|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|228|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|236|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|240|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|241|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|339|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|343|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|348|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|350|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|355|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|356|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|357|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|358|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|359|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|360|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|361|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|linha|362|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|220->222|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|222->223|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|226->227|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|235->236|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|239->240|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|338->339|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|342->343|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|347->348|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|349->350|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|354->355|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|358->359|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|358->360|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|360->361|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|360->362|heranca-piso-absoluto-2026-08-11
orchestration/schedule.py|ramo|388->-1|heranca-piso-absoluto-2026-08-11
EOF
)}"

ABSOLUTO_PENDENTE="${COBERTURA_ABSOLUTO_PENDENTE:-$(cat <<'EOF'
evidence/probes/github-ruleset.py|arquivo em correcao concorrente por outro agente nesta mesma onda (fora do escopo desta tarefa tocar); 60 itens hoje (36 linhas + 24 ramos, medido nesta sessao) - povoar a isencao agora citaria linhas que a integracao vai deslocar. Reapertar junto com o piso percentual.
evidence/validate-claims.py|arquivo em correcao concorrente por outro agente nesta mesma onda (fora do escopo desta tarefa tocar); 108 itens hoje (67 linhas + 41 ramos, medido nesta sessao) - mesma razao de evidence/probes/github-ruleset.py.
evidence/validate-literature.py|estavel (sem edicao concorrente) mas fora do escopo desta correcao pontual do mecanismo; 22 itens hoje (12 linhas + 10 ramos, medido nesta sessao) - estender a camada 2 a este arquivo e decisao de quem responde por ele.
evidence/runtime-probes/declared-capabilities.py|estavel (sem edicao concorrente) mas fora do escopo desta correcao pontual do mecanismo; 21 itens hoje (13 linhas + 8 ramos, medido nesta sessao) - mesma razao de evidence/validate-literature.py.
evidence/validate-adapters.py|arquivo NOVO da onda 10 (validador de conformidade de adaptador); 130 itens hoje (66 linhas + 64 ramos, medido nesta sessao), quase todos as mensagens de violacao de cada regra do schema. A CAMADA 1 vale integralmente com piso 69.3 medido; estender a CAMADA 2 exigiria uma fixture por regra de schema, o que e trabalho proprio e nao correcao pontual. O piso percentual ja impede regressao silenciosa. tests/mutation/adaptadores.sh mede se o validador DISCRIMINA - mas so em QUATRO regras: revisao independente contou 54 chamadas de erro() no validador contra 4 mutantes MA (MA5 e controle de direcao, nao regra). A frase anterior aqui dizia que o arnes respondia pela pergunta que a cobertura nao responde, e isso era overclaim: ele responde por 4/54. O piso continua defensavel; a JUSTIFICATIVA encolheu para o que de fato mede.
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
printf '%s\n' "$RAIZES" > "$TMP/raizes.txt"
printf '%s\n' "$EXCLUSOES" | sed '/^$/d' > "$TMP/exclusoes.txt"
printf '%s\n' "$ISENCOES" | sed '/^$/d' > "$TMP/isencoes.txt"
printf '%s\n' "$ABSOLUTO_PENDENTE" | sed '/^$/d' > "$TMP/pendente.txt"

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
python3 - "$TMP/coverage.json" "$TMP/alvos.txt" "$TMP/raizes.txt" "$TMP/exclusoes.txt" \
  "$TMP/isencoes.txt" "$TMP/pendente.txt" "$CHECK" <<'PY'
import json
import math
import os
import pathlib
import re
import sys

(cov_path, alvos_path, raizes_path, exclusoes_path, isencoes_path, pendente_path,
 check) = sys.argv[1:8]
check = check == "1"


def arredonda_baixo(x, casas=1):
    # Arredonda PARA BAIXO, nunca para o mais proximo: o piso nao pode ser satisfeito por
    # jitter de ponto flutuante entre execucoes (ex.: 78.849999... nao pode virar "78.9").
    fator = 10 ** casas
    return math.floor(x * fator) / fator


def le_linhas(path):
    with open(path, encoding="utf-8") as f:
        return [ln.strip() for ln in f if ln.strip()]


with open(alvos_path, encoding="utf-8") as f:
    alvos = []
    for linha in f:
        linha = linha.strip()
        if not linha:
            continue
        caminho, piso = linha.rsplit(":", 1)
        alvos.append((caminho, float(piso)))

exclusoes = {}
for linha in le_linhas(exclusoes_path):
    caminho, motivo = linha.split("|", 1)
    exclusoes[caminho] = motivo

pendente = {}
for linha in le_linhas(pendente_path):
    caminho, motivo = linha.split("|", 1)
    pendente[caminho] = motivo

isencoes = {}
for linha in le_linhas(isencoes_path):
    caminho, tipo, alvo_item, motivo = linha.split("|", 3)
    isencoes.setdefault(caminho, {})[(tipo, alvo_item)] = motivo

with open(cov_path, encoding="utf-8") as f:
    dados = json.load(f)
arquivos = dados.get("files", {})

problema = False

# ---------------------------------------------------------------------------------------
# CAMADA 1 + CAMADA 2: por alvo, piso percentual EXATO e (quando nao pendente) predicado
# absoluto sobre ramos/linhas ausentes.
# ---------------------------------------------------------------------------------------
linhas_saida = []
for caminho, piso in alvos:
    info = arquivos.get(caminho)
    if info is None:
        # Alvo declarado mas ausente do relatorio: nenhuma suite o exercitou (ou o caminho
        # nao existe mais). Lacuna de MEDICAO, nao "0% medido em silencio" - mas o efeito
        # pratico e o mesmo do fail-closed: conta como divergente do piso, nunca como isento.
        bruto = 0.0
        missing_lines, missing_branches = [], []
    else:
        bruto = info["summary"]["percent_covered"]
        missing_lines = info["missing_lines"]
        missing_branches = info["missing_branches"]
    medido = arredonda_baixo(bruto)

    if medido == piso:
        status_piso = "OK"
    elif medido < piso:
        status_piso = "ABAIXO DO PISO"
        problema = True
    else:
        status_piso = f"CATRACA FROUXA (reapertar para {medido:.1f})"
        problema = True

    if caminho in pendente:
        status_abs = f"PENDENTE ({pendente[caminho]})"
    else:
        isentas = isencoes.get(caminho, {})
        faltas = []
        for l in missing_lines:
            chave = ("linha", str(l))
            if chave not in isentas:
                faltas.append(f"linha {l}")
        for a, b in missing_branches:
            chave = ("ramo", f"{a}->{b}")
            if chave not in isentas:
                faltas.append(f"ramo {a}->{b}")
        if faltas:
            status_abs = "NAO JUSTIFICADO: " + ", ".join(faltas)
            problema = True
        else:
            status_abs = "OK"

    linhas_saida.append((caminho, medido, bruto, piso, status_piso, status_abs))

largura = max((len(c) for c, *_ in linhas_saida), default=0)
print(f"{'arquivo'.ljust(largura)}  medido   bruto    piso  status-piso")
for caminho, medido, bruto, piso, status_piso, status_abs in linhas_saida:
    print(f"{caminho.ljust(largura)}  {medido:5.1f}%  {bruto:6.2f}%  {piso:5.1f}%  {status_piso}")
    print(f"COBFILE\t{caminho}\t{medido:.1f}\t{piso:.1f}\t{status_piso}")
    print(f"  ramos/linhas: {status_abs}")
    print(f"COBABS\t{caminho}\t{status_abs}")

# ---------------------------------------------------------------------------------------
# CAMADA 3: completude de ALVOS - todo candidato varrido esta em ALVOS ou em EXCLUSOES.
# ---------------------------------------------------------------------------------------
MAIN_RE = re.compile(r'^if\s+__name__\s*==\s*[\'"]__main__[\'"]\s*:', re.M)
IGNORA_DIRNAME = {"hooks", "telemetry"}


def candidatos(raizes):
    achados = set()
    for raiz in raizes:
        base = pathlib.Path(raiz)
        if not base.is_dir():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [d for d in dirnames if d not in IGNORA_DIRNAME]
            for fn in filenames:
                full = pathlib.Path(dirpath) / fn
                rel = full.as_posix()
                if rel == "evidence/cobertura.sh":
                    continue
                is_exec = os.access(full, os.X_OK)
                if fn.endswith(".py"):
                    try:
                        conteudo = full.read_text(encoding="utf-8", errors="replace")
                    except OSError:
                        conteudo = ""
                    if is_exec or MAIN_RE.search(conteudo):
                        achados.add(rel)
                elif is_exec:
                    achados.add(rel)
    return achados


raizes = le_linhas(raizes_path)[0].split() if le_linhas(raizes_path) else []
alvo_caminhos = {c for c, _ in alvos}
nao_contabilizado = sorted(candidatos(raizes) - alvo_caminhos - set(exclusoes))

print()
if nao_contabilizado:
    problema = True
    print("completude de ALVOS: candidato(s) sem piso e sem exclusao (aparece em silencio):")
    for c in nao_contabilizado:
        print(f"  COBCOMPL\t{c}")
else:
    print("completude de ALVOS: todo candidato varrido esta em ALVOS ou em EXCLUSOES")

print()
if problema:
    print("cobertura de decisao: ha item(ns) divergente(s) (piso, ramo/linha nao justificado, "
          "ou alvo nao contabilizado) - ver acima")
    if check:
        sys.exit(1)
    print("(modo relatorio - rode com --check para reprovar)")
    sys.exit(0)
print("cobertura de decisao: todos os alvos no piso exato, ramos/linhas contabilizados, "
      "ALVOS completo")
sys.exit(0)
PY
