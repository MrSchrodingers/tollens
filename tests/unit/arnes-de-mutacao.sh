#!/usr/bin/env bash
# O ARNES DE MUTACAO NAO PODE DEIXAR O MUTANTE INSTALADO.
#
# Defeito medido em 2026-08-10. O trap de `tests/mutation/run.sh` era:
#     trap 'rm -rf "$TMP"; cp -f "$TMP/orig.sh" "$ORIG" 2>/dev/null || true' EXIT
# isto e, apagava o diretorio e SO ENTAO tentava restaurar de dentro dele. A restauracao nunca
# podia funcionar; o `2>/dev/null || true` engolia o erro. Em saida normal ninguem via, porque o
# corpo do script restaura explicitamente antes do sumario. Em interrupcao - `timeout`, SIGTERM,
# Ctrl-C - o mutante ficava no disco.
#
# O que aconteceu de fato: um `timeout` matou a suite e `evidence/hooks/verify-gate.sh` ficou
# com o mutante do digest truncado em 16 hex, pronto para ser commitado. Um arnes que falha
# ABERTO nao e neutro: ele PRODUZ na arvore de trabalho exatamente a fraqueza que alega medir.
#
# Duas checagens, de forcas diferentes e de proposito:
#   AM1-AM2  estatica  - ordem do trap em todo arquivo que restaura. Deterministica, roda sempre.
#   AM3      dinamica  - SIGTERM real e a arvore volta ao estado original. E a que prova o
#                        comportamento; se a corrida nao puder ser observada, o resultado e
#                        NOT_VERIFIED (exit 2), nunca um verde vazio (README secao 6.1).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

echo "== AM1. todo trap que restaura o faz ANTES de remover o diretorio =="
ruins=""
for f in tests/mutation/*.sh; do
  # FILTRA COMENTARIO ANTES DE PROCURAR. Achado da revisao independente: `grep -m1` casava a
  # PRIMEIRA ocorrencia do idioma no arquivo - e estes arquivos DOCUMENTAM o trap correto (e
  # citam o errado) em prosa, logo acima do trap real. Um arquivo com comentario certo e trap
  # destrutivo passava verde. O oraculo media a documentacao, nao o codigo.
  linha="$(grep -v "^[[:space:]]*#" "$f" | grep -m1 "trap '" 2>/dev/null)" || continue
  # so interessa o trap que restaura um original; fronteira.sh muta COPIAS em temp e nao restaura.
  printf '%s' "$linha" | grep -q 'cp -f "\$TMP/orig' || continue
  pos_cp="$(printf '%s' "$linha" | grep -bo 'cp -f "\$TMP/orig' | head -1 | cut -d: -f1)"
  pos_rm="$(printf '%s' "$linha" | grep -bo 'rm -rf "\$TMP"' | head -1 | cut -d: -f1)"
  if [ -n "$pos_rm" ] && [ -n "$pos_cp" ] && [ "$pos_rm" -lt "$pos_cp" ]; then
    ruins="$ruins $(basename "$f")"
  fi
done
[ -z "$ruins" ]; chk "nenhum trap remove \$TMP antes de restaurar${ruins:+ (ruins:$ruins)}" $? 0

echo "== AM2. o arquivo restaurado e nomeado antes de ser apagado (leitura direta) =="
# Checagem redundante e proposital: AM1 compara posicoes, AM2 exige o idioma correto literal.
# Se alguem reescrever o trap de outra forma, AM1 continua valendo e AM2 avisa que mudou.
bad=0
# A LISTA E DERIVADA, NAO LITERAL. A lista fixa cobria 3 dos 4 arquivos que restauram original
# (`install.sh` restaura DOIS e ficava de fora em silencio). Arquivo novo com trap ruim entrava
# pela mesma porta. Agora o conjunto e descoberto e a checagem ignora comentario, como AM1.
while IFS= read -r f; do
  grep -v "^[[:space:]]*#" "$f" | grep -q "trap 'cp -f \"\$TMP/orig" \
    || { echo "    idioma inesperado: $f"; bad=1; }
done < <(grep -l 'cp -f "\$TMP/orig' tests/mutation/*.sh)
chk "run/contrato/conformidade usam o idioma restaura-entao-remove" "$bad" 0

echo "== AM3. SIGTERM no meio da mutacao NAO deixa mutante no disco =="
ALVO="evidence/hooks/verify-gate.sh"
ORIG_SHA="$(sha256sum "$ALVO" | cut -d' ' -f1)"
if ! git diff --quiet -- "$ALVO"; then
  echo "  NOT_VERIFIED: $ALVO ja esta sujo antes do teste; o oraculo nao distinguiria."
  exit 2
fi
# Nao ha deadlock aqui: `tests/lib/lock.sh` e re-entrante por variavel EXPORTADA
# (EVIDENCE_GATE_LOCK=held), justamente porque os runners de mutacao invocam as suites de
# regressao. O filho herda a marca e nao tenta tomar o lock de novo.
#
# DUAS PRECAUCOES, ambas pagas por uma CI vermelha (run 31397403110):
#
# `9>&-` FECHA O FD DO LOCK NO FILHO. `tests/lib/lock.sh` segura a exclusao com
# `exec 9>arquivo; flock -n 9`. O flock vive na descricao de arquivo ABERTA, nao no processo:
# qualquer filho que herde o fd mantem o lock vivo depois que este script sair. O filho aqui
# nem usa o lock (herda EVIDENCE_GATE_LOCK=held e pula a secao), mas herdava o fd - e um neto
# orfao segurava o lock para sempre. Medido: o passo seguinte da CI, `regressao do gate`,
# abortou com exit 3 "ja ha uma suite em execucao".
#
# `setsid` + `kill -TERM -PGID` MATA O GRUPO. `tests/mutation/run.sh` invoca as suites de
# regressao como filhos proprios; SIGTERM so no processo direto deixava os netos vivos.
setsid bash tests/mutation/run.sh >/dev/null 2>&1 9>&- &
CHILD=$!
MUTOU=nao
for _ in $(seq 1 400); do   # ate ~20s
  sleep 0.05
  [ "$(sha256sum "$ALVO" 2>/dev/null | cut -d' ' -f1)" != "$ORIG_SHA" ] && { MUTOU=sim; break; }
  kill -0 "$CHILD" 2>/dev/null || break
done
if [ "$MUTOU" != "sim" ]; then
  kill -TERM -"$CHILD" 2>/dev/null || kill -TERM "$CHILD" 2>/dev/null; wait "$CHILD" 2>/dev/null
  git checkout -- "$ALVO" 2>/dev/null || true
  echo "  NOT_VERIFIED: nao foi possivel observar o arquivo em estado mutado (corrida rapida"
  echo "                demais ou suite abortou cedo). O caso NAO foi realizado."
  exit 2
fi
kill -TERM -"$CHILD" 2>/dev/null || kill -TERM "$CHILD" 2>/dev/null
wait "$CHILD" 2>/dev/null
DEPOIS_SHA="$(sha256sum "$ALVO" 2>/dev/null | cut -d' ' -f1)"
[ "$DEPOIS_SHA" = "$ORIG_SHA" ]; chk "apos SIGTERM, $ALVO voltou ao conteudo original" $? 0
# Rede de seguranca: se o trap falhou, este teste NAO pode deixar o mutante para o proximo.
[ "$DEPOIS_SHA" = "$ORIG_SHA" ] || git checkout -- "$ALVO" 2>/dev/null || true

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=3
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "arnes de mutacao verde" || echo "arnes de mutacao VERMELHO"
exit "$F"
