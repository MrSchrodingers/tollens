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

# C3: TRAP DE RECUPERACAO. Esta suite roda `TOLLENS_ARENA=off` em DOIS pontos (AM3 e o controle
# de direcao de AM4), o que reintroduz deliberadamente a mutacao da arvore REAL - e ate
# 2026-08-17 ela nao tinha trap nenhum: a recuperacao era so `git checkout --` no fim do fluxo
# feliz. Ctrl-C, `timeout`, `pkill` ou o Stop-hook entre a mutacao e o checkout deixavam
# `evidence/hooks/verify-gate.sh` mutado no disco. E o INCIDENTE 3 do cabecalho de
# tests/lib/arena.sh, dentro da propria suite que certifica que ele acabou - e pior que nos 13
# arneses, que ao menos tinham trap.
# Nao e caminho de excecao: scripts/status.sh e os dois workflows executam esta suite.
_ALVO_REC="evidence/hooks/verify-gate.sh"
# SHA DE PARTIDA. A primeira versao deste trap fazia `git checkout --` incondicional, e isso
# APAGAVA TRABALHO NAO COMMITADO: o guarda de sujeira que recusa medir sobre arvore suja esta
# mais abaixo, entao a suite detectava a edicao do operador, saia 2 por causa dela, e no caminho
# de saida destruia exatamente essa edicao. Reproduzido: marca nao commitada some sem aviso ao
# rodar `scripts/status.sh`, que executa esta suite. Perda de dado silenciosa e irreversivel.
#
# Agora o trap restaura APENAS se o conteudo divergir do que havia quando a suite comecou - isto
# e, apenas o que ELA mutou. Edicao do operador tem o mesmo sha no inicio e no fim e nao e tocada.
_SHA_REC="$(sha256sum "$_ALVO_REC" 2>/dev/null | cut -d' ' -f1)"
_restaura_rec(){
  [ -n "${_SHA_REC:-}" ] || return 0
  [ "$(sha256sum "$_ALVO_REC" 2>/dev/null | cut -d' ' -f1)" = "$_SHA_REC" ] && return 0
  git checkout -- "$_ALVO_REC" 2>/dev/null || true
}
# RE-EMITIR O SINAL. Um `trap` sem `exit` executa o handler e RETOMA o script - medido: a suite
# sobreviveu ao SIGTERM e completou os sete casos. Logo `pkill` (SIGTERM por default) nao a
# parava e ela voltava a mutar, e `timeout N` PENDURAVA em vez de matar. Trocar "morre deixando
# mutante" por "ignora o sinal e continua mutando" e piorar. Aqui o handler restaura e MORRE com
# o codigo convencional (128+sinal), deixando o pai ver que houve sinal.
# LIMITE DECLARADO: SIGKILL nao e interceptavel e continua deixando o mutante quando a suite roda
# com TOLLENS_ARENA=off. Nos 13 arneses isso ja nao ocorre - eles usam a arena.
trap '_restaura_rec' EXIT
trap '_restaura_rec; exit 130' INT
trap '_restaura_rec; exit 143' TERM

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
  # SEM PIPE. `grep -q` sai no primeiro casamento e fecha o pipe; sob `set -o pipefail` o
  # `grep -v` a montante leva SIGPIPE (141) e o pipefail propaga isso como falha do PIPELINE,
  # mesmo tendo o casamento ocorrido. Medido em 2026-08-12: 7 de 8 execucoes do pipeline
  # devolveram 141 sobre este mesmo arquivo, e a suite reprovava de forma intermitente
  # (exit 1 / 0 / 1 em tres execucoes seguidas, arvore limpa) citando SEMPRE
  # tests/mutation/fronteira-viva.sh - o maior dos arnesses, e por isso o mais provavel de
  # ainda estar sendo escrito quando o consumidor ja terminou.
  # Era o ORACULO reprovando por corrida propria, nao o objeto medido estando errado - a
  # forma mais cara de falso vermelho, porque acusa o arquivo certo pelo motivo errado.
  # Substituicao de processo em vez de pipe: nao ha upstream para receber SIGPIPE.
  if ! grep -q "trap 'cp -f \"\$TMP/orig" < <(grep -v "^[[:space:]]*#" "$f"); then
    echo "    idioma inesperado: $f"; bad=1
  fi
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
# (TOLLENS_LOCK=held), justamente porque os runners de mutacao invocam as suites de
# regressao. O filho herda a marca e nao tenta tomar o lock de novo.
#
# DUAS PRECAUCOES, ambas pagas por uma CI vermelha (run 31397403110):
#
# `9>&-` FECHA O FD DO LOCK NO FILHO. `tests/lib/lock.sh` segura a exclusao com
# `exec 9>arquivo; flock -n 9`. O flock vive na descricao de arquivo ABERTA, nao no processo:
# qualquer filho que herde o fd mantem o lock vivo depois que este script sair. O filho aqui
# nem usa o lock (herda TOLLENS_LOCK=held e pula a secao), mas herdava o fd - e um neto
# orfao segurava o lock para sempre. Medido: o passo seguinte da CI, `regressao do gate`,
# abortou com exit 3 "ja ha uma suite em execucao".
#
# `setsid` + `kill -TERM -PGID` MATA O GRUPO. `tests/mutation/run.sh` invoca as suites de
# regressao como filhos proprios; SIGTERM so no processo direto deixava os netos vivos.
# TOLLENS_ARENA=off DE PROPOSITO. A partir de 2026-08-17 os arneses mutam uma COPIA da arvore
# (tests/lib/arena.sh), entao o arquivo de producao NUNCA entra em estado mutado - e este caso,
# que mede "o trap restaura o que foi mutado", perdeu a premissa: passou a reportar
# NOT_VERIFIED por nao conseguir observar a mutacao, o que e honesto e inutil.
#
# O trap continua sendo garantia REAL: vale quando alguem roda com a arena desligada, e vale se a
# arena falhar ao montar. Para medi-lo e preciso deixar a mutacao acontecer - por isso o `off`
# aqui e deliberado, e por isso este caso restaura a arvore a mao ao final.
# Quem mede o mundo COM arena e o AM4, que usa SIGKILL - sinal que o trap nao pode interceptar.
setsid env TOLLENS_ARENA=off bash tests/mutation/run.sh >/dev/null 2>&1 9>&- &
CHILD=$!
MUTOU=nao
# ORCAMENTO RECALIBRADO EM 2026-08-12, com medicao. O valor anterior era 400 x 0.05s (~20s) e
# produzia moeda: 0/2/0/2 em execucoes seguidas, com a arvore limpa. Medi o instante em que
# a PRIMEIRA mutacao se torna observavel neste HEAD: 16663 ms. A margem era de ~3s, e a
# suite cresceu ao longo do dia (o arnes roda mais verificacao antes de mutar), entao o
# orcamento fora dimensionado contra uma versao anterior de si mesma.
# 1800 x 0.05s = ~90s da folga de ~5x sobre o medido. O NOT_VERIFIED continua existindo e
# continua sendo exit 2 - o que muda e que ele passa a significar 'a corrida realmente nao
# aconteceu', e nao 'o orcamento acabou antes de a corrida comecar'.
for _ in $(seq 1 1800); do   # ate ~90s (medido: 1a mutacao aos ~16.7s neste HEAD)
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

echo "== AM4. a arena isola a arvore candidata do experimento =="
# AM3 mede SIGTERM, que o `trap` INTERCEPTA, e por isso roda com a arena DESLIGADA. Este caso
# mede SIGKILL, que nao e interceptavel por construcao: nenhum trap executa. Antes da arena o
# mutante ficava no disco - aconteceu tres vezes em 2026-08-12/14 (validate-claims.py,
# cobertura.sh, github-ruleset.py), sempre por `pkill` ou `timeout` num arnes em curso.
#
# A EVIDENCIA E DIRETA, nao por ausencia: em vez de esperar um tempo e torcer, este caso enquete
# a ARENA ate observar o mutante LA DENTRO. Isso prova que a janela de mutacao foi alcancada -
# sem essa prova, "arvore candidata intacta" nao distinguiria isolamento de arnes que nem chegou
# a mutar. Foi exatamente esse o defeito da primeira versao deste caso: `sleep 6` contra uma
# janela que so abre aos ~16.7s (medido em AM3), e o controle de direcao acusou.
ALVO4="evidence/hooks/verify-gate.sh"
SHA4="$(sha256sum "$ALVO4" | cut -d' ' -f1)"
setsid bash tests/mutation/run.sh >/dev/null 2>&1 9>&- &
C4=$!
ARENA_MUTOU=nao
for _ in $(seq 1 1800); do   # ate ~90s, mesmo orcamento medido de AM3
  sleep 0.05
  # A ARENA VEM DA ATRIBUICAO DO FILHO, nao de `ls -dt | head -1`. A versao anterior adivinhava
  # pela mais recente, e revisao independente reproduziu dois modos de falha: observar arena
  # ALHEIA ja mutada (falso positivo - as duas assercoes seguintes passariam por vacuidade, com o
  # filho morto antes de mutar) e travar em arena alheia ILEGIVEL de outro usuario (inanicao).
  # Agravado porque o `tar` restaurava o mtime da fonte em todas as arenas, entao elas empatavam
  # e o `ls -dt` degenerava para ordem alfabetica.
  # `tests/lib/arena.sh` publica `$TMPDIR/tollens-arena-of.<pid>`; aqui lemos pelo pid do NOSSO
  # filho, que e a unica atribuicao que nao depende de relogio nem de ordem.
  A4="$(cat "${TMPDIR:-/tmp}/tollens-arena-of.$C4" 2>/dev/null)"
  [ -n "$A4" ] && [ -f "$A4/$ALVO4" ] \
    && [ "$(sha256sum "$A4/$ALVO4" 2>/dev/null | cut -d' ' -f1)" != "$SHA4" ] \
    && { ARENA_MUTOU=sim; break; }
  # S10: filho morto (lock, baseline vermelho) nao deve custar 90s de espera.
  kill -0 "$C4" 2>/dev/null || break
done
kill -KILL -"$C4" 2>/dev/null; wait "$C4" 2>/dev/null
if [ "$ARENA_MUTOU" = nao ]; then
  echo "  NOT_VERIFIED: nao observei mutacao DENTRO da arena em ~90s - o caso nao foi realizado."
  echo "                Sem isso, 'arvore intacta' nao prova isolamento."
  exit 2
fi
# A antiga `chk "a mutacao ocorreu DENTRO da arena"` foi REMOVIDA: ela vinha depois do
# `exit 2` do ramo contrario, entao nunca podia falhar - inflava PASS sem discriminar nada.
# A observacao continua sendo pre-condicao dura (o exit 2 acima), so deixou de contar como caso.
chk "  e SIGKILL nao deixou mutante na arvore candidata" \
    "$([ "$SHA4" = "$(sha256sum "$ALVO4" | cut -d' ' -f1)" ] && echo intacto || echo MUTADO)" "intacto"

# CONTROLE DE DIRECAO. Sem arena, o MESMO SIGKILL tem de deixar o mutante. Se disser "intacto",
# o experimento nao discrimina - e o PASS acima seria compativel com um arnes que nao muta nada.
setsid env TOLLENS_ARENA=off bash tests/mutation/run.sh >/dev/null 2>&1 9>&- &
C5=$!
SEM_MUTOU=nao
for _ in $(seq 1 1800); do
  sleep 0.05
  [ "$(sha256sum "$ALVO4" 2>/dev/null | cut -d' ' -f1)" != "$SHA4" ] && { SEM_MUTOU=sim; break; }
  kill -0 "$C5" 2>/dev/null || break
done
kill -KILL -"$C5" 2>/dev/null; wait "$C5" 2>/dev/null
chk "  SEM arena o mesmo SIGKILL DEIXA o mutante (o experimento discrimina)" "$SEM_MUTOU" "sim"
# Nenhum trap rodou: restauracao a mao, e conferida.
git checkout -- "$ALVO4" 2>/dev/null || true
chk "  arvore restaurada apos o controle" \
    "$([ "$SHA4" = "$(sha256sum "$ALVO4" | cut -d' ' -f1)" ] && echo intacto || echo SUJO)" "intacto"

# CASA A DIRETIVA DE SOURCE, NAO A MENCAO. A versao anterior usava `grep -L 'lib/arena.sh'`, e
# o MESMO commit que a escreveu adicionou aos 13 arneses um comentario contendo essa string
# ("Ver tests/lib/arena.sh para os seis incidentes..."). Resultado medido: removi a diretiva de
# `run.sh`, mantive o comentario, e a assercao CONTINUOU PASSANDO. Um arnes que perdesse o source
# seguiria mutando a arvore real com a suite verde.
# E a regra 2 de §6.3 - remova a garantia e exija que o teste REPROVE - reprovada pelo teste que
# ela governa. O ancoramento agora exige `.` ou `source` no inicio da linha util.
FORA4="$(grep -LE '^[[:space:]]*(\.|source)[[:space:]].*lib/arena\.sh' tests/mutation/*.sh \
         | xargs -r -n1 basename | tr '\n' ' ')"
chk "  todo arnes de mutacao carrega a arena" "${FORA4:-nenhum}" "nenhum"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=7
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "arnes de mutacao verde" || echo "arnes de mutacao VERMELHO"
exit "$F"
