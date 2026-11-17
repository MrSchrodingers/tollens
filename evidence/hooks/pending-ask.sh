#!/usr/bin/env bash
# Hook Stop - DECISAO PENDENTE SEM PERGUNTA ESTRUTURADA. ADR 0049.
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

PADROES_V=1
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
confirma_pergunta	\bconfirma ?\?
qual_das_opcoes	\bqual das (opcoes|alternativas|abordagens)\b
qual_prefere	\bqual (opcao|alternativa|abordagem) (voce )?prefere\b
precisa_da_sua	\bprecis(o|a|amos) da sua (decisao|confirmacao|aprovacao|autorizacao|resposta)\b
quer_que_eu	\bquer que eu (siga|prossiga|continue|faca|execute|aplique|implemente|rode|corrija)\b'

agora(){ date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown; }

# Grava uma linha no log. Argumentos: evento padrao bloqueou motivo. Qualquer falha e engolida:
# o log e instrumento, nunca motivo para travar a parada.
grava(){
  local ev="$1" pad="$2" blq="$3" mot="${4:-}" linha
  command -v jq >/dev/null 2>&1 || return 0
  linha="$(jq -cn --arg ts "$(agora)" --arg s "${SESSAO:-}" --arg ev "$ev" --arg m "${MODO:-aviso}" \
    --arg p "$pad" --argjson b "$blq" --argjson v "$PADROES_V" --arg mot "$mot" \
    '{ts:$ts,session_id:($s|.[0:64]),evento:$ev,modo:$m,padrao_casado:(if $p=="" then null else $p end),bloqueou:$b,padroes_v:$v}
     + (if $mot=="" then {} else {motivo:($mot|.[0:128])} end)' 2>/dev/null)" || return 0
  [ -n "$linha" ] || return 0
  ( umask 077
    mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0
    if [ -f "$LOG" ] && [ "$(stat -c %s "$LOG" 2>/dev/null || echo 0)" -gt 2097152 ]; then
      mv -f "$LOG" "$LOG.1" 2>/dev/null
    fi
    printf '%s\n' "$linha" >> "$LOG" 2>/dev/null ) 2>/dev/null
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
  _m="$(head -c 64 "$POLICY" 2>/dev/null | tr -s '[:space:]' ' ' | cut -d' ' -f1 | tr 'A-Z' 'a-z')"
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
  def norm: gsub("[ÁÀÂÃÄáàâãä]";"a") | gsub("[ÉÈÊËéèêë]";"e") | gsub("[ÍÌÎÏíìîï]";"i")
          | gsub("[ÓÒÔÕÖóòôõö]";"o") | gsub("[ÚÙÛÜúùûü]";"u") | gsub("[Çç]";"c") | gsub("[Ññ]";"n")
          | ascii_downcase | gsub("\\s+";" ");
  def realuser: .type=="user" and (.isSidechain != true) and (.isMeta != true)
    and ((.message.content|type)=="string"
         or ((.message.content|type)=="array" and ([.message.content[]? | .type] | (length>0 and all(. != "tool_result")))));
  [inputs | fromjson? | select(type=="object")] as $L
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
     else ($A | map(select([.message.content[]? | select(type=="object" and .type=="text")] | length > 0)) | last
           | (.message.content | map(select(type=="object" and .type=="text") | .text) | join("\n"))) // "" end | norm) as $txt
  | ([$pats | split("\n")[] | split("\t") | select(length==2) | select(. as $p | $txt | test($p[1]))] | first | .[0]) as $pad
  | {ask:$ask, padrao:($pad // (if $dp then "decisao_pendente_subagente" else null end))}
' 2>/dev/null)"
[ -n "$RES" ] || erro transcript_ilegivel
PADRAO="$(printf '%s' "$RES" | jq -r '.padrao // empty' 2>/dev/null)" || erro veredito_ilegivel
ASK="$(printf '%s' "$RES" | jq -r '.ask' 2>/dev/null)" || erro veredito_ilegivel

[ -n "$PADRAO" ] || exit 0

# I3: pergunta estruturada no turno suprime o disparo.
if [ "$ASK" = true ]; then grava suprimido "$PADRAO" false; exit 0; fi

if [ "$MODO" = bloqueio ]; then
  grava disparo "$PADRAO" true
  printf '%s\n' "$MOTIVO_BLOQUEIO" >&2
  BLOQUEIA=1
  exit 2
fi
grava disparo "$PADRAO" false
exit 0
