#!/usr/bin/env bash
# Hook SubagentStop - VERIFICADOR DE HONRA de modelo de subagente. ADR 0048.
#
# Detecta quando o modelo PEDIDO para um subagente (ex.: `opus`) nao e o modelo que RODOU
# (ex.: `claude-sonnet-5-5`). A allowlist managed pode substituir o pedido em silencio e nada
# na cadeia de hooks comparava os dois.
#
# FONTES, e por que sao estas (fatos medidos no payload real de SubagentStop):
#  - o payload NAO tem campo `model`; `effort` e o objeto {"level":..} da SESSAO, nao do
#    subagente; `agent_type` vem vazio em parte dos eventos e parte dos transcripts ja nao
#    existe no disco. Por isso nada do que se compara vem do payload.
#  - PEDIDO: `${agent_transcript_path%.jsonl}.meta.json`, campos `.model` e `.effort`. Tambem
#    se registra `.pickedEffortModel`, so como informacao: NAO entra no julgamento (semantica
#    nao verificada, ADR 0048).
#  - EFETIVO: `.message.model` da primeira linha `assistant` do transcript DO SUBAGENTE
#    (`agent_transcript_path`), ignorando `<synthetic>`. NUNCA `transcript_path`, que e o do
#    pai (ADR 0014). Teto de leitura: 1 MiB e 400 linhas do transcript, 64 KiB do meta.
#
# COMPARACAO. Alias (`opus|sonnet|haiku|fable`) casa pela FAMILIA do ID efetivo, derivada por
# TOKEN (primeiro token `opus|sonnet|haiku|fable` do ID normalizado, que tambem cobre a
# nomenclatura antiga `claude-3-5-sonnet-20241022`). Trocar a versao dentro da familia nao e
# divergencia (o ID efetivo vai no log). ID completo (`claude-*`) exige igualdade exata APOS a
# normalizacao: minusculas, sem sufixo `[...]` (ex.: `[1m]`), sem prefixo `anthropic.` (nem
# `<regiao>.anthropic.`), sem sufixo `@<data>`. `inherit`, vazio, null ou ausente: `sem_pedido`.
# Valor de tipo errado (numero, array, objeto, booleano) ou fora do vocabulario:
# `pedido_desconhecido`. `indeterminado`: meta ou transcript ausente, ilegivel, ou sem linha
# assistant, ou caminho fora da raiz.
#
# SAIDA. Uma linha JSONL por evento em ${MODEL_HONOR_LOG:-$HOME/.claude/logs/model-honor.jsonl},
# modo 0600, ASCII puro (U+2028/U+2029 saem escapados). Campos: ts, session_id, agent_id,
# agent_type, pedido_model, pedido_effort, pedido_origem (`meta` ou `ausente`),
# picked_effort_model, efetivo_model, status, motivo. Todo campo textual do payload e truncado
# a 256 caracteres ANTES de montar o JSON (campo grande por `--arg` derruba o exec e apagaria o
# DIVERGE). Nunca prompt, mensagem ou `last_assistant_message` (invariante I5).
# Rotacao a 2 MB e append sob `flock` num arquivo de trava ao lado do log; sem `flock`, ou sem
# obter a trava em 5 s, grava SEM rotacionar (nunca perde historico).
#
# STDOUT (systemMessage, um unico JSON, no maximo 300 caracteres): DIVERGE; falha ao gravar o
# log; jq ausente (texto fixo, sem jq). Nos demais casos, nada.
#
# FALHA ABERTA (I1/I6): modo hook sai sempre 0 e nunca bloqueia. Entrada que nao e JSON objeto
# ou sem nenhuma identificacao: sai 0 em silencio. Com identificacao minima, registra
# `indeterminado` com o motivo.
#
# CAMINHO HOSTIL: `agent_transcript_path` vem do payload. O caminho resolvido (realpath) precisa
# casar `*/subagents/agent-*.jsonl`, e estar sob ~/.claude/projects/ ou
# ~/.local/share/ai-central/accounts/*/projects/; o meta resolvido passa pela mesma raiz. Fora
# disso nada e lido. Nada vindo do payload e executado.
#
# MODO --scan <projects_dir> [--since <ISO8601>]: aplica a MESMA funcao `julga` a todo
# `*/*/subagents/agent-*.meta.json` sob o diretorio (a raiz permitida passa a ser o proprio
# diretorio) e imprime um resumo TSV (campos separados por TAB; TAB e quebra de linha em
# caminhos viram espaco). Filtro --since pela data de modificacao do meta (o limite entra).
# Exit 0 sem DIVERGE, 1 com DIVERGE, 2 erro de uso ou de instrumento: jq que nao funciona,
# diretorio inexistente, ou nenhum meta encontrado sob o diretorio (um --since que exclui tudo
# nao e erro: o total sai 0).
#
# LIMITES: so a PRIMEIRA mensagem assistant e julgada; linha de transcript maior que o teto de
# leitura antes da primeira assistant resulta em `indeterminado`; entre o realpath e a leitura
# existe uma janela (TOCTOU) que exige escrita do mesmo usuario em ~/.claude/projects; a
# entrega do `systemMessage` ao operador depende do runtime.
set -uo pipefail

MODO=hook
[ "${1:-}" = "--scan" ] && MODO=scan

if ! command -v jq >/dev/null 2>&1; then
  if [ "$MODO" = scan ]; then echo "model-honor: jq ausente" >&2; exit 2; fi
  # Sem jq nao ha como julgar; o aviso e literal, escrito sem jq, para o desligamento deixar rastro.
  printf '%s\n' '{"systemMessage":"model-honor: verificacao de modelo desligada, jq ausente"}'
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

# ID normalizado para comparacao (stdout).
norm_id() {
  local v="${1,,}" re_br='^(.*)\[[^]]*\]$' re_pf='^([a-z]{2}\.)?anthropic\.(.*)$'
  [[ "$v" =~ $re_br ]] && v="${BASH_REMATCH[1]}"
  [[ "$v" =~ $re_pf ]] && v="${BASH_REMATCH[2]}"
  v="${v%%@*}"
  printf '%s' "$v"
}

# Familia (primeiro token opus|sonnet|haiku|fable) de um ID normalizado (stdout).
familia_de() {
  local tk=() t IFS=-
  read -ra tk <<<"$1"
  for t in ${tk[@]+"${tk[@]}"}; do
    case "$t" in opus|sonnet|haiku|fable) printf '%s' "$t"; return 0 ;; esac
  done
  return 0
}

# Julga um transcript de subagente. Entrada: caminho do transcript como veio. Saida, em globais:
# PEDIDO PEDIDO_EFFORT PICKED ORIGEM EFETIVO META_TYPE STATUS MOTIVO.
julga() {
  PEDIDO=""; PEDIDO_EFFORT=""; PICKED=""; ORIGEM=ausente; EFETIVO=""; META_TYPE=""; STATUS=""; MOTIVO=""
  local tp="$1" rp mp mrp META_OK=0 MF=() pl EN FAM PN
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
        def tipo: if . == null then ""
                  elif type == "string" then gsub("[[:cntrl:]]"; "") | .[0:128]
                  else "<tipo_invalido:" + type + ">" end;
        if type == "object" then
          (.model | tipo),
          ((.effort | if type == "object" then (.level | s) else s end) // ""),
          ((.agentType | s) // ""),
          ((.pickedEffortModel | s) // "")
        else empty end' 2>/dev/null)
      if [ "${#MF[@]}" -eq 4 ]; then
        META_OK=1; PEDIDO="${MF[0]}"; PEDIDO_EFFORT="${MF[1]}"; META_TYPE="${MF[2]}"; PICKED="${MF[3]}"
      fi
    fi
  fi
  if [ "$META_OK" -eq 1 ] && [ -n "$PEDIDO" ]; then ORIGEM=meta; fi

  if [ ! -f "$rp" ]; then STATUS=indeterminado; MOTIVO=transcript_ausente; return 0; fi
  if [ ! -e "$mp" ] && [ ! -L "$mp" ]; then STATUS=indeterminado; MOTIVO=meta_ausente; return 0; fi
  if [ "$META_OK" -ne 1 ]; then STATUS=indeterminado; MOTIVO=meta_ilegivel; return 0; fi

  EFETIVO="$(head -c 1048576 "$rp" 2>/dev/null | head -n 400 | jq -Rr '
    fromjson? | objects | select(.type == "assistant")
    | (.message | objects | .model | strings)
    | select(. != "<synthetic>" and . != "")
    | gsub("[[:cntrl:]]"; "") | .[0:128]' 2>/dev/null | head -n 1)"
  if [ -z "$EFETIVO" ]; then STATUS=indeterminado; MOTIVO=sem_linha_assistant; return 0; fi

  pl="${PEDIDO,,}"
  case "$pl" in
    ""|inherit) STATUS=sem_pedido; MOTIVO=pedido_ausente_ou_inherit ;;
    opus|sonnet|haiku|fable)
      EN="$(norm_id "$EFETIVO")"
      FAM="$(familia_de "$EN")"
      if [[ "$EN" == claude-* && "$FAM" == "$pl" ]]; then STATUS=honrado; MOTIVO=familia_igual
      else STATUS=DIVERGE; MOTIVO=familia_diferente; fi ;;
    *)
      PN="$(norm_id "$PEDIDO")"
      case "$PN" in
        claude-*)
          if [ "$PN" = "$(norm_id "$EFETIVO")" ]; then STATUS=honrado; MOTIVO=id_igual
          else STATUS=DIVERGE; MOTIVO=id_diferente; fi ;;
        *) STATUS=pedido_desconhecido; MOTIVO=valor_fora_do_vocabulario ;;
      esac ;;
  esac
  return 0
}

# Grava a linha do evento. Em falha, LOGERR recebe o motivo curto; nunca aborta o hook.
LOGERR=""
registra() {  # $1 session_id  $2 agent_id  $3 agent_type
  local linha err rc reason
  LOGERR=""
  linha="$(jq -nac --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$1" --arg aid "$2" --arg at "$3" \
    --arg pm "$PEDIDO" --arg pe "$PEDIDO_EFFORT" --arg po "$ORIGEM" --arg pk "$PICKED" \
    --arg em "$EFETIVO" --arg st "$STATUS" --arg mo "$MOTIVO" '
    {ts: $ts, session_id: $sid, agent_id: $aid, agent_type: $at, pedido_model: $pm,
     pedido_effort: $pe, pedido_origem: $po, picked_effort_model: $pk, efetivo_model: $em,
     status: $st, motivo: $mo}' 2>/dev/null)" || { LOGERR=jq_falhou; return 0; }
  err="$(
    ( umask 077
      mkdir -p "$(dirname "$LOG")" || exit 1
      if command -v flock >/dev/null 2>&1; then
        exec 9>>"$LOG.lock" || exit 1
        if flock -w 5 9; then
          SZ=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
          [ "$SZ" -gt 2097152 ] && mv -f "$LOG" "$LOG.1"
        fi
      fi
      printf '%s\n' "$linha" >> "$LOG" ) 2>&1
  )"; rc=$?
  if [ "$rc" -ne 0 ]; then
    reason="${err##*: }"; reason="${reason//[$'\n\r\t']/ }"
    LOGERR="${reason:0:80}"; [ -n "$LOGERR" ] || LOGERR=erro_desconhecido
  fi
  return 0
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
  [ -n "$DIR" ] && [ -d "$DIR" ] || { echo "uso: model-honor.sh --scan <projects_dir> [--since <ISO8601>] (diretorio inexistente ou ausente)" >&2; exit 2; }
  [ "$(jq -n '1 + 1' 2>/dev/null)" = 2 ] || { echo "model-honor: jq nao funciona neste ambiente" >&2; exit 2; }
  SINCE_EP=""
  if [ -n "$SINCE" ]; then
    SINCE_EP="$(date -d "$SINCE" +%s 2>/dev/null)" || { echo "model-honor: --since invalido: $SINCE" >&2; exit 2; }
  fi
  add_root "$DIR"
  declare -A CNT PAR
  DIVS=""; TOTAL=0; ACHADOS=0
  while IFS= read -r -d '' M; do
    ACHADOS=$((ACHADOS + 1))
    if [ -n "$SINCE_EP" ]; then
      MT="$(stat -c %Y "$M" 2>/dev/null || echo 0)"
      [ "$MT" -lt "$SINCE_EP" ] && continue
    fi
    julga "${M%.meta.json}.jsonl"
    TOTAL=$((TOTAL + 1))
    CNT[$STATUS]=$(( ${CNT[$STATUS]:-0} + 1 ))
    K="${PEDIDO:-?}->${EFETIVO:-?}"
    PAR[$K]=$(( ${PAR[$K]:-0} + 1 ))
    MP="${M//[$'\t\n\r']/ }"
    [ "$STATUS" = DIVERGE ] && DIVS="$DIVS$(printf 'diverge\t%s\t%s\t%s' "$MP" "$PEDIDO" "$EFETIVO")"$'\n'
  done < <(find "$DIR" -mindepth 4 -maxdepth 4 \( -type f -o -type l \) -path '*/subagents/agent-*.meta.json' -print0 2>/dev/null)
  if [ "$ACHADOS" -eq 0 ]; then
    echo "model-honor: nenhum agent-*.meta.json sob $DIR (esperado */*/subagents/); varredura sem objeto" >&2
    exit 2
  fi
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
  def c($n): strings | gsub("[[:cntrl:]]"; "") | .[0:$n];
  ((.session_id | c(256)) // ""), ((.agent_id | c(256)) // ""),
  ((.agent_type | c(256)) // ""), ((.agent_transcript_path | c(4096)) // "")' 2>/dev/null)
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

if [ "$STATUS" = DIVERGE ] || [ -n "$LOGERR" ]; then
  jq -nac --arg st "$STATUS" --arg p "$PEDIDO" --arg e "$EFETIVO" --arg t "${AT:-desconhecido}" \
    --arg i "$AID" --arg le "$LOGERR" '
    [ (if $st == "DIVERGE"
       then "model-honor: pedido \($p[0:40]), rodou \($e[0:40]) (agente \($t[0:40]) \($i[0:40]))"
       else empty end),
      (if $le != "" then "model-honor: nao consegui gravar o log (\($le[0:80]))" else empty end) ]
    | join(" | ") | {systemMessage: .[0:300]}' 2>/dev/null
fi
exit 0
