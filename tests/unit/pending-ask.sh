#!/usr/bin/env bash
# Suite do hook Stop evidence/hooks/pending-ask.sh (ADR 0050).
#
# INVARIANTES PROTEGIDOS (os unicos que justificam teste aqui):
#  I1  nunca bloqueia duas vezes seguidas: stop_hook_active=true sai 0 sem bloquear.
#  I2  nunca trava a sessao em erro: entrada vazia, JSON invalido, transcript ausente ou
#      corrompido, jq ausente, log nao gravavel saem 0.
#  I3  pergunta estruturada (AskUserQuestion) no turno suprime o disparo; o turno e delimitado
#      pela ultima mensagem REAL do usuario (tool_result nao conta), e pergunta de turno
#      anterior nao vale.
#  I4  corpus negativo (conclusoes normais) nao dispara; corpus positivo (frases reais de
#      pendencia em texto) dispara. DECISAO_PENDENTE vinda de subagente (Agent/Task) dispara;
#      a mesma linha em retorno de outra ferramenta nao.
#  I5  o log nunca recebe conteudo de mensagem, transcript ou retorno de subagente.
#  I6  modo aviso (padrao) registra e nao bloqueia; off nao registra; modo invalido vira aviso.
#  I7  fala citada (bloco de codigo, codigo inline, linha `>`, trecho entre aspas) e frase meta
#      sobre os padroes nao disparam; variantes fora da lista e a mesma locucao disfarcada com
#      NFD ou zero-width disparam. Falso positivo aqui bloqueia o turno em modo bloqueio.
#  I8  o hook nao julga fala de sidechain nem trata mensagem meta/sidechain como fala do usuario;
#      rotacao, truncamento de session_id e normalizacao do modo (caixa, branco na frente) valem;
#      ultima linha do transcript partida nao vira veredito sobre texto antigo; sessao headless
#      (entrypoint sdk-cli) nunca bloqueia.
#
# Fixtures SINTETICAS: transcripts montados em tempo de execucao, sem ids reais. O transcript
# real grava um bloco de conteudo por linha; o construtor abaixo faz o mesmo.
# Uso: PENDING_ASK_HOOK=<caminho> troca o hook sob teste (usado para mostrar o vermelho).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"

P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1"; echo "        got:  $2"; echo "        want: $3"; F=$((F+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "  DEPENDENCIA AUSENTE: jq. Estado: NAO VERIFICADO - a suite nao rodou."; exit 2; }

HOOK="${PENDING_ASK_HOOK:-$PWD/evidence/hooks/pending-ask.sh}"
BASH_BIN="$(command -v bash)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"; mkdir -p "$HOME/.claude/logs"
LOG="$T/pending-ask.jsonl"
POL="$T/pending-ask.mode"
export PENDING_ASK_LOG="$LOG" PENDING_ASK_POLICY="$POL"
TR="$T/transcript.jsonl"
SID="sess-sintetica-0001"

# --- construtor de transcript ---
tr_novo(){ : > "$TR"; }
tr_user(){ jq -nc --arg t "$1" '{type:"user",message:{role:"user",content:$t}}' >> "$TR"; }
tr_user_f(){ jq -nc --arg t "$1" --argjson f "$2" '{type:"user",message:{role:"user",content:$t}} + $f' >> "$TR"; }
tr_text_sc(){ jq -nc --arg t "$1" '{type:"assistant",isSidechain:true,message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$TR"; }
tr_text(){ jq -nc --arg t "$1" '{type:"assistant",message:{role:"assistant",content:[{type:"text",text:$t}]}}' >> "$TR"; }
tr_use(){ jq -nc --arg n "$1" --arg i "$2" '{type:"assistant",message:{role:"assistant",content:[{type:"tool_use",id:$i,name:$n,input:{}}]}}' >> "$TR"; }
tr_result(){ jq -nc --arg i "$1" --arg c "$2" '{type:"user",message:{role:"user",content:[{type:"tool_result",tool_use_id:$i,content:$c}]}}' >> "$TR"; }

# roda <payload-json> [stdin-bruto]: define RC, ERR, OUT. Modo vem do arquivo POL.
roda(){
  local payload="$1"
  "$BASH_BIN" "$HOOK" <<<"$payload" >/dev/null 2>"$T/err"; RC=$?
  ERR="$(cat "$T/err")"
}
payload(){ jq -nc --arg s "$SID" --arg tp "$TR" --argjson a "${1:-false}" '{session_id:$s,transcript_path:$tp,stop_hook_active:$a,hook_event_name:"Stop"}'; }
modo(){ printf '%s\n' "$1" > "$POL"; }
zera_log(){ : > "$LOG"; }

# corpus de resposta final: cada uma e UMA mensagem assistant num turno sem AskUserQuestion.
# veredito(): rc de cada frase, em modo bloqueio, concatenado.
veredito(){
  local f out=""
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    tr_novo; tr_user "faca a tarefa"; tr_text "$f"
    roda "$(payload)"; out="$out$RC "
  done
  printf '%s' "${out% }"
}

# vmsg <mensagem...>: rc de cada mensagem (cada argumento, multilinha permitida), modo bloqueio.
vmsg(){
  local f out=""
  for f in "$@"; do
    tr_novo; tr_user "faca a tarefa"; tr_text "$f"
    roda "$(payload)"; out="$out$RC "
  done
  printf '%s' "${out% }"
}

POS='Terminei a parte A. Suas pendências: 1) decidir o prazo; 2) aprovar o PR.
Resumo feito. Pendências suas: aprovar o merge.
A escolha do banco é decisão sua, não minha.
Implementei o hook. Aguardo sua confirmação para seguir.
Há duas rotas viáveis. Você decide qual seguimos.
Tudo pronto. Se preferir, posso rodar a suíte completa depois.
Apliquei a correção no módulo. Confirma?
Comparei as abordagens. Qual das opções você prefere?
Para continuar preciso da sua aprovação.
Fiz o diff. Quer que eu aplique a mudança?
Ficou parado até agora. Aguardando a sua decisão.
SUAS PENDENCIAS ABERTAS: tres itens.'

NEG='Implementei a mudança em evidence/hooks/x.sh. Testes: 15 passam, exit 0.
As pendências do backlog foram atualizadas e o item 3 segue aberto com dono definido.
A decisão do operador de 17/11 foi aplicada no arquivo de política.
O diff está em docs/x.md; a suíte confirma que o invariante vale.
Confirmado: o build passou e o lint saiu com exit 0.
Não há bloqueio. Escolhi a opção B por menor custo e executei.
O operador decide quando aplicar o deploy; nada a fazer agora no repositório.
Corrigi os três arquivos e rodei os testes afetados; todos verdes.'

echo "== I4 corpus =="
modo bloqueio
chk "I4 positivo: 12 frases de pendencia em texto bloqueiam" "$(printf '%s\n' "$POS" | veredito)" "2 2 2 2 2 2 2 2 2 2 2 2"
chk "I4 negativo: 8 conclusoes normais nao disparam" "$(printf '%s\n' "$NEG" | veredito)" "0 0 0 0 0 0 0 0"

NFD="Aguardo sua confirma$(printf '\xcc\xa7')a$(printf '\xcc\x83')o para seguir."
ZW="Voc$(printf '\xe2\x80\x8b')e decide qual rota seguimos."
echo "== I7 citacao e borda =="
modo bloqueio
chk "I7 citacao e frase meta nao disparam (aspas, bloco, inline, linha >, confirma? no meio da frase)" "$(vmsg \
  'Concluido. O hook detecta frases como "suas pendencias" e "decisao sua"; nada pendente.' \
  $'Exemplo do corpus:\n```\n# se preferir, posso rodar\n```\nFim.' \
  $'Citando o texto:\n> voce decide\nFim.' \
  'O teste confirma? Sim, 41 passam.' \
  'O padrao `aguardo sua` consta da lista fechada.' \
  'A frase “você decide” consta do corpus de teste.' \
  'O corpus traz «suas pendências» como exemplo.')" "0 0 0 0 0 0 0"
chk "I7 borda e disfarce disparam (fico no aguardo, para voce, posso prosseguir?, se quiser posso, NFD, zero-width, aspas so em volta das opcoes)" "$(vmsg \
  'Terminei. Fico no aguardo.' \
  'Pendências para você: aprovar o PR.' \
  'Implementei o hook. Posso prosseguir?' \
  'Se quiser, posso ampliar a cobertura.' \
  "$NFD" "$ZW" \
  'Você decide: "A" ou "B"?')" "2 2 2 2 2 2 2"

echo "== I1 anti-laco =="
modo bloqueio
tr_novo; tr_user "x"; tr_text "Aguardo sua confirmação."
roda "$(payload false)"; r1=$RC
roda "$(payload true)"; r2=$RC; e2="$ERR"
chk "I1 primeira parada bloqueia e a continuacao (stop_hook_active) libera sem mensagem" "$r1/$r2/[$e2]" "2/0/[]"

echo "== I2 falha aberta =="
modo bloqueio; zera_log
r=""
roda ""; r="$r $RC"
roda "isto nao e json"; r="$r $RC"
roda '[1,2]'; r="$r $RC"
roda "$(jq -nc --arg s "$SID" '{session_id:$s,stop_hook_active:false}')"; r="$r $RC"
roda "$(jq -nc --arg s "$SID" '{session_id:$s,transcript_path:"/nao/existe/t.jsonl"}')"; r="$r $RC"
head -c 4096 /dev/urandom > "$T/lixo.jsonl"
roda "$(jq -nc --arg s "$SID" --arg tp "$T/lixo.jsonl" '{session_id:$s,transcript_path:$tp}')"; r="$r $RC"
chk "I2 entrada vazia, nao-JSON, array, sem transcript, transcript ausente e corrompido: tudo exit 0" "${r# }" "0 0 0 0 0 0"
chk "I2 cada falha deixa uma linha de erro com motivo no log" "$(jq -rs '[.[]|select(.evento=="erro")|.motivo]|sort|join(",")' "$LOG")" "payload_invalido,payload_invalido,stdin_vazio,transcript_ausente,transcript_ausente,transcript_sem_linhas"
# jq ausente: PATH so com o minimo; o hook nao pode travar nem bloquear.
mkdir -p "$T/nojq"; for c in date mkdir dirname head tr cut stat mv cat timeout; do ln -sf "$(command -v $c)" "$T/nojq/$c"; done
tr_novo; tr_user "x"; tr_text "Aguardo sua confirmação."
zera_log
PATH="$T/nojq" "$BASH_BIN" "$HOOK" <<<"$(payload)" >/dev/null 2>&1; rc_nojq=$?
chk "I2 sem jq: exit 0 e linha de erro escrita a mao" "$rc_nojq/$(grep -c 'jq_ausente' "$LOG")" "0/1"
# log nao gravavel (diretorio pai e um arquivo)
: > "$T/arquivo"
PENDING_ASK_LOG="$T/arquivo/x.jsonl" "$BASH_BIN" "$HOOK" <<<"$(payload)" >/dev/null 2>&1; rc_log=$?
chk "I2 log nao gravavel: o bloqueio deliberado segue valendo e nada mais quebra (exit 2, nao 1)" "$rc_log" "2"

echo "== I3 AskUserQuestion =="
modo bloqueio; zera_log
tr_novo; tr_user "x"; tr_use AskUserQuestion tu_ask; tr_result tu_ask "resposta"; tr_text "Aguardo sua confirmação."
roda "$(payload)"
chk "I3 AskUserQuestion no turno (com tool_result no meio) suprime: exit 0 e evento suprimido" "$RC/$(jq -rs '.[0].evento' "$LOG")" "0/suprimido"
tr_novo; tr_user "turno 1"; tr_use AskUserQuestion tu_ask; tr_result tu_ask "resposta"; tr_user "turno 2"; tr_text "Aguardo sua confirmação."
roda "$(payload)"
chk "I3 AskUserQuestion de turno ANTERIOR nao vale: bloqueia" "$RC" "2"
tr_novo; tr_user "x"; tr_use Bash tu_b; tr_result tu_b "ok"; tr_text "Aguardo sua confirmação."
roda "$(payload)"
chk "I3 tool_result sem pergunta nao e fala do usuario nem suprime: bloqueia" "$RC" "2"

# Regressao medida em transcript real: turno sem NENHUM bloco de texto assistant (so tool_use)
# derrubava o filtro com "Cannot iterate over null" e o hook registrava erro em vez de julgar.
modo bloqueio; zera_log
tr_novo; tr_user "x"; tr_use Bash tu_b; tr_result tu_b "ok"
roda "$(payload)"
chk "I2 turno sem texto assistant (so tool_use): julga sem erro, exit 0, log vazio" "$RC/$(wc -c < "$LOG")" "0/0"

echo "== I4 contrato de subagente =="
modo bloqueio; zera_log
tr_novo; tr_user "x"; tr_use Agent tu_ag; tr_result tu_ag $'RESULTADO: feito\nDECISAO_PENDENTE: qual banco usar?|Postgres|SQLite, MySQL'; tr_text "Subagente concluiu."
roda "$(payload)"
chk "I4 DECISAO_PENDENTE em retorno de Agent dispara" "$RC/$(jq -rs '.[0].padrao_casado' "$LOG")" "2/decisao_pendente_subagente"
tr_novo; tr_user "x"; tr_use Bash tu_b; tr_result tu_b $'DECISAO_PENDENTE: qual banco usar?|Postgres|SQLite'; tr_text "Li o arquivo."
roda "$(payload)"
chk "I4 a mesma linha em retorno de outra ferramenta (ex.: leitura de doc) nao dispara" "$RC" "0"

echo "== I5 sem conteudo no log =="
modo aviso; zera_log
CANARY="CANARIO-XYZ-7731"
tr_novo; tr_user "$CANARY pedido"; tr_use Agent tu_ag; tr_result tu_ag "DECISAO_PENDENTE: $CANARY?|a|b"; tr_text "Suas pendências: $CANARY"
roda "$(jq -nc --arg s "$SID" --arg tp "$TR" --arg m "Suas pendências: $CANARY" '{session_id:$s,transcript_path:$tp,stop_hook_active:false,last_assistant_message:$m}')"
chk "I5 canario ausente do log; linha tem os campos minimos" \
  "$(grep -c "$CANARY" "$LOG")/$(jq -rs '.[0]|[has("ts"),has("session_id"),has("padrao_casado"),has("bloqueou")]|all' "$LOG")" "0/true"

echo "== I6 modos =="
rm -f "$POL"; zera_log
tr_novo; tr_user "x"; tr_text "Aguardo sua confirmação."
roda "$(payload)"
chk "I6 padrao (sem arquivo de politica) e aviso: exit 0, sem stderr, log com bloqueou=false" "$RC/[$ERR]/$(jq -rs '.[0]|"\(.evento) \(.modo) \(.bloqueou)"' "$LOG")" "0/[]/disparo aviso false"
modo off; zera_log; roda "$(payload)"
chk "I6 off: exit 0 e nenhum registro" "$RC/$(wc -c < "$LOG")" "0/0"
modo ligado-errado; zera_log; roda "$(payload)"
chk "I6 modo invalido vira aviso (nao bloqueia) e deixa erro no log" "$RC/$(jq -rs 'map(.evento+":"+(.motivo//"")+":"+(.modo))|join(",")' "$LOG")" "0/erro:modo_invalido:aviso,disparo::aviso"

echo "== texto no payload =="
modo bloqueio
tr_novo; tr_user "x"; tr_text "Pronto, tudo executado."
roda "$(jq -nc --arg s "$SID" --arg tp "$TR" '{session_id:$s,transcript_path:$tp,stop_hook_active:false,last_assistant_message:"Se preferir, posso seguir depois."}')"
chk "last_assistant_message do payload tem precedencia sobre o transcript (ainda nao gravado)" "$RC" "2"

echo "== I8 mutantes que sobreviveram a suite anterior =="
modo bloqueio; zera_log
tr_novo; tr_user "x"; tr_text "Pronto."; tr_text_sc "Voce decide."
roda "$(payload)"; a=$RC
tr_novo; tr_user "x"; tr_use AskUserQuestion tu_ask; tr_result tu_ask "resposta"
tr_user_f "lembrete" '{"isMeta":true}'; tr_user_f "tarefa de sidechain" '{"isSidechain":true}'; tr_text "Voce decide."
roda "$(payload)"; b=$RC
chk "I8 ultima fala de sidechain nao e julgada; usuario isMeta/sidechain nao encerra o turno do AskUserQuestion" "$a $b" "0 0"
# rotacao: log acima de 2 MiB vai para .1 e o novo comeca com 1 linha
rm -f "$LOG" "$LOG.1" "$LOG.lock"; head -c 2200000 /dev/zero | tr '\0' 'x' > "$LOG"; echo >> "$LOG"
tr_novo; tr_user "x"; tr_text "Voce decide."; roda "$(payload)"
chk "I8 rotacao: log acima do teto vai para .1 e o novo tem 1 linha" "$([ -s "$LOG.1" ] && echo 1 || echo 0)/$(wc -l < "$LOG")" "1/1"
# session_id com 100 caracteres sai com 64
SID100="$(printf 's%.0s' $(seq 1 100))"
rm -f "$LOG" "$LOG.1"; modo aviso
roda "$(jq -nc --arg s "$SID100" --arg tp "$TR" '{session_id:$s,transcript_path:$tp,stop_hook_active:false}')"
chk "I8 session_id e truncado a 64 no log" "$(jq -rs '.[0].session_id|length' "$LOG")" "64"
# modo: caixa alta e branco na frente valem
r=""; for m in 'BLOQUEIO' $'\n   Bloqueio\n'; do printf '%s' "$m" > "$POL"; tr_novo; tr_user "x"; tr_text "Voce decide."; roda "$(payload)"; r="$r$RC "; done
chk "I8 modo em maiusculas ou com branco na frente e lido como bloqueio" "${r% }" "2 2"
# ultima linha partida
modo bloqueio; zera_log
tr_novo; tr_user "x"; tr_text "Voce decide."; printf '{"type":"assistant","message":{"role":"assis' >> "$TR"
roda "$(payload)"
chk "I8 ultima linha do transcript partida: sem veredito sobre texto antigo (exit 0, erro registrado)" "$RC/$(jq -rs '.[0].motivo' "$LOG")" "0/ultima_linha_truncada"
# headless
zera_log; r=""
for ep in cli sdk-cli; do tr_novo; tr_user_f "x" "{\"entrypoint\":\"$ep\"}"; tr_text "Voce decide."; roda "$(payload)"; r="$r$RC "; done
chk "I8 sessao headless (sdk-cli) nao bloqueia e registra auq_disponivel=false; cli bloqueia" "${r% }/$(jq -rs 'map(.bloqueou|tostring)|join(",")' "$LOG")/$(jq -rs '.[1].auq_disponivel' "$LOG")" "2 0/true,false/false"

echo
echo "PASS=$P FAIL=$F"
[ "$F" -eq 0 ]
