#!/usr/bin/env bash
# Hook SubagentStop - VERIFICADOR DE HONRA de modelo de subagente. ADR 0048.
#
# Detecta quando o modelo PEDIDO para um subagente (ex.: `opus`) nao e o modelo que RODOU
# (ex.: `claude-sonnet-5-5`). Medido: 48 subagentes pediram `opus` e rodaram em Sonnet sem erro,
# porque a allowlist managed substitui o modelo em silencio. Nada detectava.
#
# FONTES, e por que sao estas (fatos medidos no payload real de SubagentStop):
#  - o payload NAO tem campo `model`; `effort` e o objeto {"level":..} da SESSAO, nao do
#    subagente; `agent_type` vem vazio em 29 de 63 eventos; 32 de 63 apontam para transcript que
#    nao existe mais. Por isso nada do que se compara vem do payload.
#  - PEDIDO: `${agent_transcript_path%.jsonl}.meta.json`, campos `.model` e `.effort`.
#  - EFETIVO: `.message.model` da primeira linha `assistant` do transcript DO SUBAGENTE
#    (`agent_transcript_path`), ignorando `<synthetic>`. NUNCA `transcript_path`, que e o do pai
#    (ADR 0014). A leitura e limitada a 1 MiB e 400 linhas.
#
# COMPARACAO. Alias (`opus|sonnet|haiku|fable`) casa por FAMILIA: `claude-<alias>-*`. Trocar a
# versao dentro da familia nao e divergencia (o ID efetivo vai no log). ID completo (`claude-*`)
# exige igualdade exata. `inherit`, vazio ou ausente: `sem_pedido`, nao se julga. Outro valor:
# `pedido_desconhecido`. `indeterminado`: meta ou transcript ausente, ilegivel ou sem linha
# assistant, ou caminho fora da raiz.
#
# SAIDA. Uma linha JSONL por evento em ${MODEL_HONOR_LOG:-$HOME/.claude/logs/model-honor.jsonl},
# rotacionada a 2 MB, modo 0600. So identificadores e nomes de modelo: nunca prompt, mensagem ou
# `last_assistant_message` (invariante I5). Em DIVERGE, um `systemMessage` em stdout.
#
# FALHA ABERTA (I1/I6): modo hook sempre sai 0 e nunca bloqueia. Sem jq, entrada que nao e JSON
# objeto ou sem nenhuma identificacao: sai 0 em silencio. Com identificacao minima, registra
# `indeterminado` com o motivo.
#
# CAMINHO HOSTIL: `agent_transcript_path` vem do payload. O caminho resolvido (realpath) precisa
# casar `*/subagents/agent-*.jsonl`, ser arquivo regular e estar sob ~/.claude/projects/ ou
# ~/.local/share/ai-central/accounts/*/projects/; o meta resolvido passa pela mesma raiz. Fora
# disso nada e lido. Nada vindo do payload e executado.
#
# MODO --scan <projects_dir> [--since <ISO8601>]: aplica a MESMA funcao `julga` a todo
# `*/*/subagents/agent-*.meta.json` sob o diretorio (a raiz permitida passa a ser o proprio
# diretorio) e imprime um resumo TSV. Filtro --since pela data de modificacao do meta.
# Exit 0 sem DIVERGE, 1 com DIVERGE, 2 erro de uso ou de instrumento.
#
# LIMITES: so a PRIMEIRA mensagem assistant e julgada (troca de modelo no meio da execucao nao e
# vista); linha de transcript maior que o teto de leitura antes da primeira assistant resulta em
# `indeterminado`; a entrega do `systemMessage` ao operador depende do runtime.
set -uo pipefail

MODO=hook
[ "${1:-}" = "--scan" ] && MODO=scan

if ! command -v jq >/dev/null 2>&1; then
  [ "$MODO" = scan ] && { echo "model-honor: jq ausente" >&2; exit 2; }
  exit 0
fi

LOG="${MODEL_HONOR_LOG:-${HOME:-/nonexistent}/.claude/logs/model-honor.jsonl}"
ROOTS=()

add_root() {
  local r
  r="$(realpath -m -- "$1" 2>/dev/null)" || return 0
  [ -n "$r" ] && ROOTS+=("$r")
  return 0
}

sob_raiz() {
  local p="$1" r
  for r in ${ROOTS[@]+"${ROOTS[@]}"}; do
    case "$p" in "$r"/*) return 0 ;; esac
  done
  return 1
}

# Julga um transcript de subagente. Entrada: caminho do transcript como veio. Saida, em globais:
# PEDIDO PEDIDO_EFFORT EFETIVO META_TYPE STATUS MOTIVO.
julga() {
  PEDIDO=""; PEDIDO_EFFORT=""; EFETIVO=""; META_TYPE=""; STATUS=""; MOTIVO=""
  local tp="$1" rp mp mrp META_OK=0 MF=() pl
  if [ -z "$tp" ]; then STATUS=indeterminado; MOTIVO=sem_agent_transcript_path; return 0; fi
  rp="$(realpath -m -- "$tp" 2>/dev/null)"
  case "$rp" in
    */subagents/agent-*.jsonl) ;;
    *) STATUS=indeterminado; MOTIVO=caminho_fora_da_raiz; return 0 ;;
  esac
  if ! sob_raiz "$rp"; then STATUS=indeterminado; MOTIVO=caminho_fora_da_raiz; return 0; fi

  mp="${rp%.jsonl}.meta.json"
  if [ -e "$mp" ] || [ -L "$mp" ]; then
    mrp="$(realpath -m -- "$mp" 2>/dev/null)"
    if ! sob_raiz "$mrp"; then STATUS=indeterminado; MOTIVO=caminho_fora_da_raiz; return 0; fi
    if [ -f "$mrp" ]; then
      mapfile -t MF < <(head -c 65536 "$mrp" 2>/dev/null | jq -r '
        def s: strings | gsub("[[:cntrl:]]"; "") | .[0:128];
        if type == "object" then
          ((.model | s) // ""),
          ((.effort | if type == "object" then (.level | s) else s end) // ""),
          ((.agentType | s) // "")
        else empty end' 2>/dev/null)
      if [ "${#MF[@]}" -eq 3 ]; then
        META_OK=1; PEDIDO="${MF[0]}"; PEDIDO_EFFORT="${MF[1]}"; META_TYPE="${MF[2]}"
      fi
    fi
  fi

  if [ ! -f "$rp" ]; then STATUS=indeterminado; MOTIVO=transcript_ausente; return 0; fi
  if [ ! -e "$mp" ] && [ ! -L "$mp" ]; then STATUS=indeterminado; MOTIVO=meta_ausente; return 0; fi
  if [ "$META_OK" -ne 1 ]; then STATUS=indeterminado; MOTIVO=meta_ilegivel; return 0; fi

  EFETIVO="$(head -c 1048576 "$rp" 2>/dev/null | head -n 400 | jq -Rr '
    fromjson? | objects | select(.type == "assistant")
    | (.message | objects | .model | strings)
    | select(. != "<synthetic>" and . != "")
    | gsub("[[:cntrl:]]"; "") | .[0:128]' 2>/dev/null | head -n 1)"
  if [ -z "$EFETIVO" ]; then STATUS=indeterminado; MOTIVO=sem_linha_assistant; return 0; fi

  pl="$(printf '%s' "$PEDIDO" | tr 'A-Z' 'a-z')"
  case "$pl" in
    ""|inherit) STATUS=sem_pedido; MOTIVO=pedido_ausente_ou_inherit ;;
    opus|sonnet|haiku|fable)
      case "$EFETIVO" in
        claude-"$pl"-*) STATUS=honrado; MOTIVO=familia_igual ;;
        *) STATUS=DIVERGE; MOTIVO=familia_diferente ;;
      esac ;;
    claude-*)
      if [ "$EFETIVO" = "$PEDIDO" ]; then STATUS=honrado; MOTIVO=id_igual
      else STATUS=DIVERGE; MOTIVO=id_diferente; fi ;;
    *) STATUS=pedido_desconhecido; MOTIVO=valor_fora_do_vocabulario ;;
  esac
  return 0
}

registra() {  # $1 session_id  $2 agent_id  $3 agent_type
  {
    ( umask 077
      mkdir -p "$(dirname "$LOG")"
      SZ=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
      [ "$SZ" -gt 2097152 ] && mv -f "$LOG" "$LOG.1"
      jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$1" --arg aid "$2" --arg at "$3" \
        --arg pm "$PEDIDO" --arg pe "$PEDIDO_EFFORT" --arg em "$EFETIVO" --arg st "$STATUS" --arg mo "$MOTIVO" '
        {ts: $ts, session_id: $sid, agent_id: $aid, agent_type: $at, pedido_model: $pm,
         pedido_effort: $pe, efetivo_model: $em, status: $st, motivo: $mo}
        | map_values(gsub("[[:cntrl:]]"; "") | .[0:128])' >> "$LOG" )
  } 2>/dev/null || true
}

if [ "$MODO" = scan ]; then
  shift
  DIR=""; SINCE=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --since) [ "$#" -ge 2 ] || { echo "model-honor: --since exige valor" >&2; exit 2; }; SINCE="$2"; shift 2 ;;
      -*) echo "model-honor: opcao desconhecida: $1" >&2; exit 2 ;;
      *) [ -z "$DIR" ] || { echo "model-honor: diretorio repetido" >&2; exit 2; }; DIR="$1"; shift ;;
    esac
  done
  [ -n "$DIR" ] && [ -d "$DIR" ] || { echo "uso: model-honor.sh --scan <projects_dir> [--since <ISO8601>]" >&2; exit 2; }
  SINCE_EP=""
  if [ -n "$SINCE" ]; then
    SINCE_EP="$(date -d "$SINCE" +%s 2>/dev/null)" || { echo "model-honor: --since invalido: $SINCE" >&2; exit 2; }
  fi
  add_root "$DIR"
  declare -A CNT PAR
  DIVS=""; TOTAL=0
  while IFS= read -r -d '' M; do
    if [ -n "$SINCE_EP" ]; then
      MT="$(stat -c %Y "$M" 2>/dev/null || echo 0)"
      [ "$MT" -lt "$SINCE_EP" ] && continue
    fi
    julga "${M%.meta.json}.jsonl"
    TOTAL=$((TOTAL + 1))
    CNT[$STATUS]=$(( ${CNT[$STATUS]:-0} + 1 ))
    K="${PEDIDO:-?}->${EFETIVO:-?}"
    PAR[$K]=$(( ${PAR[$K]:-0} + 1 ))
    [ "$STATUS" = DIVERGE ] && DIVS="$DIVS$(printf 'diverge\t%s\t%s\t%s' "$M" "$PEDIDO" "$EFETIVO")"$'\n'
  done < <(find "$DIR" -mindepth 4 -maxdepth 4 \( -type f -o -type l \) -path '*/subagents/agent-*.meta.json' -print0 2>/dev/null)
  printf 'total\t%s\n' "$TOTAL"
  for S in DIVERGE honrado sem_pedido pedido_desconhecido indeterminado; do
    [ "${CNT[$S]:-0}" -gt 0 ] && printf 'status\t%s\t%s\n' "$S" "${CNT[$S]}"
  done
  if [ "${#PAR[@]}" -gt 0 ]; then
    while IFS= read -r K; do printf 'par\t%s\t%s\n' "$K" "${PAR[$K]}"; done < <(printf '%s\n' "${!PAR[@]}" | LC_ALL=C sort)
  fi
  [ -n "$DIVS" ] && printf '%s' "$DIVS"
  [ "${CNT[DIVERGE]:-0}" -gt 0 ] && exit 1
  exit 0
fi

# ---- modo hook: nunca bloqueia ----
trap 'exit 0' EXIT
IN="$(cat 2>/dev/null || true)"
printf '%s' "$IN" | jq -e 'type == "object"' >/dev/null 2>&1 || exit 0
mapfile -t PF < <(printf '%s' "$IN" | jq -r '
  (.session_id, .agent_id, .agent_type, .agent_transcript_path)
  | (strings | gsub("[[:cntrl:]]"; "")) // ""' 2>/dev/null)
SID="${PF[0]:-}"; AID="${PF[1]:-}"; AT="${PF[2]:-}"; ATP="${PF[3]:-}"
[ -n "$SID$AID$ATP" ] || exit 0

if [ -n "${HOME:-}" ]; then
  add_root "$HOME/.claude/projects"
  for D in "$HOME"/.local/share/ai-central/accounts/*/projects; do
    [ -d "$D" ] && add_root "$D"
  done
fi

julga "$ATP"
AT="${AT:-$META_TYPE}"
registra "$SID" "$AID" "$AT"

if [ "$STATUS" = DIVERGE ]; then
  jq -nc --arg p "$PEDIDO" --arg e "$EFETIVO" --arg t "${AT:-desconhecido}" --arg i "$AID" \
    '{systemMessage: ("model-honor: pedido " + $p + ", rodou " + $e + " (agente " + $t + " " + $i + ")")}' 2>/dev/null
fi
exit 0
