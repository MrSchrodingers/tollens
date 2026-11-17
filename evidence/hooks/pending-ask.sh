#!/usr/bin/env bash
# Hook Stop - DECISAO PENDENTE SEM PERGUNTA ESTRUTURADA. ADR 0050.
#
# DEFEITO MEDIDO: sessoes e agentes encerram o turno com texto do tipo "suas pendencias",
# "decisao sua", "aguardo sua confirmacao" em vez de chamar AskUserQuestion. O operador fica sem
# pergunta estruturada (opcoes, recomendacao marcada) e o turno acaba com pendencia que ninguem
# executa. A regra textual vive em docs/proposals/pending-ask-regra.md; este hook e o instrumento
# que mede e, se o operador ligar, barra.
#
# O QUE ESTE HOOK NAO E: fronteira de confianca. Mesmas razoes do verify-gate (ADR 0022):
# `stop_hook_active` encerra a insistencia, o runtime sobrepoe hook apos N bloqueios, e o arquivo
# de modo mora em ~/.claude, espaco de escrita do proprio ator governado. E um empurrao com
# registro auditavel, nao uma garantia.
#
# FONTE DO JULGAMENTO:
#  - texto: `last_assistant_message` do payload, se presente; senao o ultimo bloco de texto
#    assistant do turno no transcript (`transcript_path`). O transcript grava um bloco por linha.
#  - turno: tudo depois da ULTIMA mensagem real do usuario. `type=user` com `tool_result` NAO e
#    mensagem do usuario (e retorno de ferramenta); `isMeta` e `isSidechain` tambem nao contam.
#  - AskUserQuestion: qualquer `tool_use` com esse nome no turno suprime o disparo.
#  - subagente: contrato `DECISAO_PENDENTE: <pergunta>|<opcao recomendada>|<alternativas>`, em
#    linha propria do retorno de uma chamada Agent/Task do turno (tool_result ligado ao tool_use
#    por id). SubagentStop nao bloqueia, entao o hook so e registrado em Stop e trata a linha
#    recebida como "precisa perguntar". Limite: retorno de subagente em background chega como
#    mensagem de usuario e nao e inspecionado.
#
# PADROES: lista FECHADA e VERSIONADA (PADROES_V) abaixo. Casam sobre o texto normalizado (sem
# acento, minusculas, espaco colapsado). Sem palavra solta: cada padrao e uma locucao. Mudar a
# lista exige subir PADROES_V, para o log separar as populacoes.
#
# ANTES DE CASAR (PADROES_V=2): o texto perde bloco de codigo, codigo inline, linhas `>` e trechos
# entre aspas (fala citada nao e fala) e passa por normalizacao tipo NFKC (zero-width, NFD, espacos
# Unicode, largura total). Sessao headless (entrypoint sdk-cli no transcript) nunca bloqueia: nao ha
# quem responda AskUserQuestion. Detalhes e limites: ADR 0050.
#
# MODO: arquivo ${PENDING_ASK_POLICY:-$HOME/.claude/pending-ask.mode}, primeira palavra
# `off|aviso|bloqueio`. Ausente: `aviso`. Valor invalido: `aviso` e linha de erro no log.
#   off      sai sem ler nada.
#   aviso    registra o disparo no log e nao bloqueia.
#   bloqueio registra e bloqueia UMA vez (exit 2 + stderr, canal que entrega: ADR 0021).
#
# LOG: ${PENDING_ASK_LOG:-$HOME/.claude/logs/pending-ask.jsonl}, 0600, uma linha JSONL por
# disparo, supressao ou erro. Campos: ts, session_id, evento (disparo|suprimido|erro), modo,
# padrao_casado, bloqueou, padroes_v, motivo (so em erro). NUNCA texto da mensagem (I5). So
# disparo/supressao/erro sao gravados; resposta sem padrao nao deixa rastro. Rotacao simples a
# 2 MiB (uma geracao: .1).
#
# FALHA ABERTA (I2): toda saida e 0, exceto o bloqueio deliberado. O `trap EXIT` impoe isso: um
# erro inesperado, jq quebrado ou variavel vazia nao trava a sessao. Falha deixa linha de erro.
# ANTI-LACO (I1): stop_hook_active=true sai 0 sem bloquear, e evento ilegivel nao bloqueia.
set -o pipefail

PADROES_V=2
LOG="${PENDING_ASK_LOG:-${HOME:-/nonexistent}/.claude/logs/pending-ask.jsonl}"
POLICY="${PENDING_ASK_POLICY:-${HOME:-/nonexistent}/.claude/pending-ask.mode}"
BLOQUEIA=0
trap 'if [ "$BLOQUEIA" = 1 ]; then exit 2; fi; exit 0' EXIT

TAIL_BYTES=4194304
MOTIVO_BLOQUEIO="Ha decisao pendente do operador sem AskUserQuestion; pergunte com opcoes e recomendacao marcada, ou, se for acao sua, execute."

# id<TAB>regex, sobre texto normalizado. Ver PADROES no cabecalho.
PADROES='suas_pendencias	\bsuas pendencias\b
pendencias_suas	\bpendencias suas\b
decisao_sua	\b(decisao|decisoes) (e |sao )?(sua|suas)\b
aguardo_sua	\baguard(o|ando|amos) (a |o )?(sua|seu)\b
aguardo_operador	\baguard(o|ando|amos) (a )?(decisao|confirmacao|aprovacao|autorizacao) do operador\b
voce_decide	\bvoce decide\b
se_preferir_posso	\bse (voce )?(preferir|quiser),? (eu )?posso\b
confirma_pergunta	(^|[.!?:;] )confirma ?\?
qual_das_opcoes	\bqual das (opcoes|alternativas|abordagens)\b
qual_prefere	\bqual (opcao|alternativa|abordagem) (voce )?prefere\b
precisa_da_sua	\bprecis(o|a|amos) da sua (decisao|confirmacao|aprovacao|autorizacao|resposta)\b
quer_que_eu	\bquer que eu (siga|prossiga|continue|faca|execute|aplique|implemente|rode|corrija)\b
fico_no_aguardo	\bfico (no aguardo|aguardando)\b
pendencias_para_voce	\bpendencias (para|pra) (voce|o operador)\b
posso_prosseguir	\bposso (prosseguir|continuar|seguir|avancar|aplicar)\?'

agora(){ date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown; }

# Grava uma linha no log. Argumentos: evento padrao bloqueou motivo. Qualquer falha e engolida:
# o log e instrumento, nunca motivo para travar a parada.
grava(){
  local ev="$1" pad="$2" blq="$3" mot="${4:-}" auq="${5:-}" linha
  command -v jq >/dev/null 2>&1 || return 0
  linha="$(jq -cn --arg ts "$(agora)" --arg s "${SESSAO:-}" --arg ev "$ev" --arg m "${MODO:-aviso}" \
    --arg p "$pad" --argjson b "$blq" --argjson v "$PADROES_V" --arg mot "$mot" --arg auq "$auq" \
    '{ts:$ts,session_id:($s|.[0:64]),evento:$ev,modo:$m,padrao_casado:(if $p=="" then null else $p end),bloqueou:$b,padroes_v:$v}
     + (if $mot=="" then {} else {motivo:($mot|.[0:128])} end)
     + (if $auq=="" then {} else {auq_disponivel:($auq=="true")} end)' 2>/dev/null)" || return 0
  [ -n "$linha" ] || return 0
  # Rotacao so sob flock (dois hooks concorrentes sem trava faziam o segundo `mv` sobrescrever
  # o .1 com o log novo e perder 2 MiB de historico). Sem flock, ou sem a trava em 5 s, grava sem
  # rotacionar: nada e descartado, o log apenas passa do teto ate a proxima rotacao.
  ( umask 077
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0
    if command -v flock >/dev/null 2>&1 && exec 9>"$LOG.lock" 2>/dev/null && flock -w 5 9 2>/dev/null; then
      if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 2097152 ]; then
        mv -f "$LOG" "$LOG.1" 2>/dev/null
      fi
      printf '%s\n' "$linha" >> "$LOG" 2>/dev/null
    else
      printf '%s\n' "$linha" >> "$LOG" 2>/dev/null
    fi ) 2>/dev/null
  return 0
}

erro(){ grava erro "" false "$1"; exit 0; }

# Leitura do evento pelo descritor 0, com teto de tempo (mesmo motivo do verify-gate: `cat` num
# descritor fechado pendura a parada).
INPUT=""
if [ ! -t 0 ]; then INPUT="$(timeout 5 cat 2>/dev/null || true)"; fi

if ! command -v jq >/dev/null 2>&1; then
  # Sem jq nao ha como ler o evento nem montar JSON; a linha de erro sai escrita a mao.
  ( umask 077; mkdir -p "$(dirname "$LOG")" 2>/dev/null
    printf '{"ts":"%s","evento":"erro","motivo":"jq_ausente","bloqueou":false,"padroes_v":%s}\n' \
      "$(agora)" "$PADROES_V" >> "$LOG" ) 2>/dev/null
  exit 0
fi

# Modo antes de qualquer outra coisa: `off` e inercia total.
MODO=aviso
if [ -f "$POLICY" ]; then
  # primeira palavra nao vazia (espaco e linhas em branco na frente sao ignorados), em minusculas
  _m="$(head -c 256 "$POLICY" 2>/dev/null | tr -s '[:space:]' '\n' | sed -n '/./{p;q}' | tr 'A-Z' 'a-z')"
  case "$_m" in
    off|aviso|bloqueio) MODO="$_m" ;;
    *) MODO=aviso; _modo_invalido=1 ;;
  esac
fi
[ "$MODO" = off ] && exit 0

[ -n "$INPUT" ] || erro stdin_vazio
printf '%s' "$INPUT" | jq -e 'type=="object"' >/dev/null 2>&1 || erro payload_invalido
SESSAO="$(printf '%s' "$INPUT" | jq -r '.session_id // empty' 2>/dev/null | head -c 128 || true)"
[ -n "${_modo_invalido:-}" ] && grava erro "" false modo_invalido

# I1: continuacao forcada nunca bloqueia de novo.
[ "$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)" = "true" ] && exit 0

TP="$(printf '%s' "$INPUT" | jq -r '.transcript_path // empty' 2>/dev/null || true)"
if [ -z "$TP" ] || [ ! -f "$TP" ] || [ ! -r "$TP" ]; then erro transcript_ausente; fi
MSG="$(printf '%s' "$INPUT" | jq -r '.last_assistant_message // empty | strings' 2>/dev/null || true)"

# Um unico jq sobre o transcript. Tail com teto: a primeira linha do corte pode vir partida, e
# `fromjson?` a descarta. O texto da mensagem nunca sai deste filtro: so o veredito.
RES="$(tail -c "$TAIL_BYTES" "$TP" 2>/dev/null | jq -Rn --arg msg "$MSG" --arg pats "$PADROES" '
  # NFKC aproximado sem dependencia: zero-width e controles de direcao somem, marcas combinantes
  # somem (cobre NFD), espacos Unicode viram espaco, ASCII de largura total volta a ASCII.
  def limpa: gsub("[\u200b-\u200f\u202a-\u202e\u2060-\u2064\u2066-\u2069\ufeff\u00ad\u180e]";"")
           | gsub("[\u0300-\u036f]";"")
           | gsub("[\u00a0\u1680\u2000-\u200a\u202f\u205f\u3000]";" ")
           | explode | map(if . >= 65281 and . <= 65374 then . - 65248 else . end) | implode;
  # Fala citada nao e fala: bloco de codigo, codigo inline, linha de citacao (>) e trecho entre
  # aspas duplas, curvas ou angulares (ate 160 caracteres, uma linha) saem antes do casamento.
  def sem_citacao: gsub("(```|~~~)[\\s\\S]*?(```|~~~)";" ") | gsub("(```|~~~)[\\s\\S]*$";" ")
           | gsub("`[^`\\n]*`";" ")
           | split("\n") | map(select(test("^\\s*>")|not)) | join("\n")
           | gsub("\"[^\"\\n]{0,160}\"";" ") | gsub("“[^”\\n]{0,160}”";" ") | gsub("«[^»\\n]{0,160}»";" ");
  def norm: gsub("[ÁÀÂÃÄáàâãä]";"a") | gsub("[ÉÈÊËéèêë]";"e") | gsub("[ÍÌÎÏíìîï]";"i")
          | gsub("[ÓÒÔÕÖóòôõö]";"o") | gsub("[ÚÙÛÜúùûü]";"u") | gsub("[Çç]";"c") | gsub("[Ññ]";"n")
          | ascii_downcase | gsub("[\\r\\n]+";" . ") | gsub("\\s+";" ");
  def realuser: .type=="user" and (.isSidechain != true) and (.isMeta != true)
    and ((.message.content|type)=="string"
         or ((.message.content|type)=="array" and ([.message.content[]? | .type] | (length>0 and all(. != "tool_result")))));
  [inputs] as $R
  | [$R[] | fromjson? | select(type=="object")] as $L
  | (($R | map(select(test("\\S"))) | last // "") | (try fromjson catch null) | type != "object") as $trunc
  | ($L | map(select(.type=="user") | .entrypoint | strings) | last) as $ep
  | (($L | to_entries | map(select(.value|realuser)) | last) // {key:-1}).key as $u
  | $L[($u+1):] as $T
  | ($T | map(select(.type=="assistant" and .isSidechain != true))) as $A
  | ($A | map(.message.content[]? | select(type=="object" and .type=="tool_use"))) as $uses
  | ($uses | map(select(.name=="AskUserQuestion")) | length > 0) as $ask
  | ($uses | map(select(.name=="Agent" or .name=="Task") | .id)) as $ids
  | ($T | map(select(.type=="user") | .message.content | arrays | .[]
              | select(type=="object" and .type=="tool_result" and (.tool_use_id as $i | $ids | index($i)))
              | (.content | if type=="string" then . else (arrays | map(.text? // "") | join("\n")) end) // "")
     | map(split("\n") | map(select(test("^\\s*DECISAO_PENDENTE:\\s*[^|\\n]+\\|[^|\\n]*\\|"))) | length > 0) | any) as $dp
  | (if $msg != "" then $msg
     else ($A | map(select([.message.content[]? | select(type=="object" and .type=="text")] | length > 0)) | (last // {})
           | ((.message.content // []) | map(select(type=="object" and .type=="text") | .text) | join("\n"))) end | limpa | sem_citacao | norm) as $txt
  | ([$pats | split("\n")[] | split("\t") | select(length==2) | select(. as $p | $txt | test($p[1]))] | first | .[0]) as $pad
  | {n:($L|length), trunc:$trunc, ep:$ep, ask:$ask, padrao:($pad // (if $dp then "decisao_pendente_subagente" else null end))}
' 2>/dev/null)"
[ -n "$RES" ] || erro transcript_ilegivel
[ "$(printf '%s' "$RES" | jq -r '.n' 2>/dev/null)" -gt 0 ] 2>/dev/null || erro transcript_sem_linhas
# Ultima linha do transcript partida (gravacao em curso): o texto avaliado seria um texto ANTIGO
# do turno. Sem `last_assistant_message` para suprir, nao ha veredito.
if [ -z "$MSG" ] && [ "$(printf '%s' "$RES" | jq -r '.trunc' 2>/dev/null)" = true ]; then erro ultima_linha_truncada; fi
PADRAO="$(printf '%s' "$RES" | jq -r '.padrao // empty' 2>/dev/null)" || erro veredito_ilegivel
# Sessao headless (`claude -p` grava entrypoint=sdk-cli): AskUserQuestion nao ha como ser
# respondida, entao bloquear forcaria um turno impossivel. Proxy medido, nao garantia: ver ADR 0050.
EP="$(printf '%s' "$RES" | jq -r '.ep // empty' 2>/dev/null)"
AUQ_DISP=true; [ "$EP" = sdk-cli ] && AUQ_DISP=false
ASK="$(printf '%s' "$RES" | jq -r '.ask' 2>/dev/null)" || erro veredito_ilegivel

[ -n "$PADRAO" ] || exit 0

# I3: pergunta estruturada no turno suprime o disparo.
if [ "$ASK" = true ]; then grava suprimido "$PADRAO" false; exit 0; fi

if [ "$MODO" = bloqueio ] && [ "$AUQ_DISP" = true ]; then
  grava disparo "$PADRAO" true "" "$AUQ_DISP"
  printf '%s\n' "$MOTIVO_BLOQUEIO" >&2
  BLOQUEIA=1
  exit 2
fi
grava disparo "$PADRAO" false "" "$AUQ_DISP"
exit 0
