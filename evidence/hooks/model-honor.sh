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
# COMPARACAO. Pedido e efetivo passam pela MESMA normalizacao (`norm_id`): minusculas; sem
# sufixos `[...]` (ex.: `[1m]`); sem prefixo `anthropic.` nem `<regiao>.anthropic.` (us, eu, apac,
# global); sem sufixo `@AAAAMMDD`, `-vN`, `-vN:M` (Bedrock), `-latest` e `-AAAAMMDD`. Alias
# (`opus|sonnet|haiku|fable`, ja normalizado, entao `opus[1m]` vale `opus`) casa pela FAMILIA do ID
# efetivo, derivada por TOKEN (primeiro token de familia do ID normalizado, o que cobre tambem
# `claude-3-5-sonnet-20241022`). ID completo (`claude-*`) exige igualdade exata dos IDs
# normalizados, comparados por inteiro (so o log e truncado); ID acima de 256 caracteres:
# `indeterminado/id_longo`. DECISAO: snapshots de datas diferentes da MESMA versao e familia nao
# sao divergencia, porque a substituicao que este hook procura troca familia ou versao, nao a data
# de snapshot de uma mesma versao. `inherit`, vazio, null ou ausente: `sem_pedido`. Valor de tipo
# errado (numero, array, objeto, booleano) ou fora do vocabulario: `pedido_desconhecido`.
# `indeterminado`: meta ou transcript ausente, ilegivel, ou sem linha assistant, ou caminho fora
# da raiz, ou ID longo, ou payload ilegivel, ou efetivo sem prefixo `claude-` depois da
# normalizacao (`efetivo_nao_reconhecido`). A normalizacao tambem toma o ULTIMO segmento depois de
# `/` (`anthropic/claude-...`, ARN de inference-profile ou foundation-model, `vertex/...`) e troca
# `.` por `-` (`claude-opus-4.5` vale `claude-opus-4-5`). Sem prefixo `claude-`, a FAMILIA ainda e
# derivada quando o ID tem um token `claude` e um token de familia: se difere da pedida,
# `DIVERGE/familia_diferente`; se coincide, ou se nao ha familia derivavel (ARN opaco, `opus-4-6`,
# `gpt-sonnet-9`), `indeterminado/efetivo_nao_reconhecido`. Caminho
# relativo no payload e resolvido contra o cwd do hook (limite, ADR 0048).
#
# SAIDA. Uma linha JSONL por evento em ${MODEL_HONOR_LOG:-$HOME/.claude/logs/model-honor.jsonl},
# modo 0600, ASCII puro (U+2028/U+2029 saem escapados). Campos: ts, session_id, agent_id,
# agent_type, pedido_model, pedido_effort, pedido_origem (`meta` ou `ausente`),
# picked_effort_model, efetivo_model, status, motivo, rotacao (`flock` ou `sem_flock`). Todo campo
# textual do payload e truncado a 256 caracteres (caminho: 4096) ANTES de montar o JSON (campo
# grande por `--arg` derruba o exec e apagaria o DIVERGE). Nunca prompt, mensagem ou
# `last_assistant_message` (invariante I5). Payload que o jq rejeita mesmo apos o saneamento de
# surrogates solitarios (camada com perl, quando existe): linha `indeterminado/payload_ilegivel`
# com so `payload_bytes` e `payload_sha12`, nunca conteudo.
# Rotacao a 2 MB e append sob `flock` num arquivo de trava ao lado do log; sao mantidas TRES
# geracoes (.1, .2, .3, deslocadas sob a trava); a quarta rotacao descarta a mais antiga. Sem
# `flock`, ou sem obter a trava em 5 s, grava SEM rotacionar: nada e descartado, mas o log cresce
# sem teto enquanto a rotacao nao ocorre.
#
# STDOUT (systemMessage, um unico JSON, no maximo 300 caracteres), nestes casos: DIVERGE; falha
# ao gravar o log; payload ilegivel; payload com varios valores (`payload_multiplo`); payload sem
# objeto com caminho (`payload_sem_caminho`); jq que falha nos filtros (`jq_filtro_falhou`) ou na
# extracao (`jq_extracao_falhou`); caminho fora da raiz (`caminho_fora_da_raiz`, tentativa de
# escape); jq ausente ou quebrado (texto fixo, escrito sem jq). Nos demais casos, nada: os outros
# `indeterminado` (meta ou transcript ausente ou ilegivel, sem linha assistant, ID longo, efetivo
# nao reconhecido) so vao ao log.
#
# MULTIPLOS VALORES no stdin: julga o primeiro objeto com `agent_transcript_path`, registra
# `payload_multiplo`; sem nenhum, `indeterminado/payload_sem_caminho`.
#
# FALHA ABERTA (I1/I6): modo hook sai sempre 0 e nunca bloqueia. Entrada vazia ou JSON que nao e
# objeto, ou sem nenhuma identificacao: sai 0 em silencio. Com identificacao minima, registra
# `indeterminado` com o motivo.
#
# CAMINHO HOSTIL: `agent_transcript_path` vem do payload. O caminho resolvido (realpath) precisa
# casar `*/subagents/agent-*.jsonl`, e estar sob ~/.claude/projects/ ou
# ~/.local/share/ai-central/accounts/*/projects/; o meta resolvido passa pela mesma raiz. Fora
# disso nada e lido. Nada vindo do payload e executado.
#
# MODO --scan <projects_dir> [--since <ISO8601>]: aplica a MESMA funcao `julga` a todo
# `*/*/subagents/agent-*.meta.json` sob o diretorio (a raiz permitida passa a ser o proprio
# diretorio) e imprime um resumo TSV (campos separados por TAB; controles, TAB, quebra de linha e
# U+2028/U+2029 em caminhos e nomes viram espaco). Filtro --since pela data de modificacao do meta
# (o limite entra).
# Exit 0 quando nada divergiu e nada ficou nao julgado; 1 com DIVERGE; 3 quando NADA divergiu mas
# houve `indeterminado` ou `pedido_desconhecido` (o resumo `NAO JULGADOS n de total` e a contagem
# por motivo vao ao stderr), ou quando NENHUM evento foi julgado (honrado + DIVERGE == 0 com
# total > 0, so `sem_pedido`: mensagem `NENHUM JULGADO`). `sem_pedido` com pelo menos um julgado
# nao conta como incompletude, so aparece no resumo;
# 2 erro de uso ou de instrumento (precedencia 2 > 1 > 3 > 0): jq que nao funciona ou que
# falha nos filtros (contado como `jq_erro`), diretorio inexistente, nenhum meta encontrado, ou
# arquivo/diretorio ilegivel (contado como `ilegivel`). Um --since que exclui tudo nao e erro: o
# total sai 0. O bloco --scan termina com `exit` explicito e nunca le stdin.
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

# jq presente mas quebrado: a sonda precisa de um caso positivo conhecido.
if [ "$(jq -n '1 + 1' 2>/dev/null)" != 2 ]; then
  if [ "$MODO" = scan ]; then echo "model-honor: jq nao funciona neste ambiente" >&2; exit 2; fi
  printf '%s\n' '{"systemMessage":"model-honor: verificacao de modelo desligada, jq nao funciona"}'
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

# ID normalizado para comparacao (stdout). Ver COMPARACAO no cabecalho.
norm_id() {
  local v="${1,,}" re_br='^(.*)\[[^]]*\]$' re_pf='^([a-z]+\.)?anthropic\.(.*)$'
  local re_at='^(.*)@[0-9]{8}$' re_v='^(.*)-v[0-9]+(:[0-9]+)?$' re_d='^(.*)-[0-9]{8}$' re_l='^(.*)-latest$'
  while [[ "$v" =~ $re_br ]]; do v="${BASH_REMATCH[1]}"; done
  v="${v##*/}"
  [[ "$v" =~ $re_pf ]] && v="${BASH_REMATCH[2]}"
  [[ "$v" =~ $re_at ]] && v="${BASH_REMATCH[1]}"
  [[ "$v" =~ $re_v ]] && v="${BASH_REMATCH[1]}"
  [[ "$v" =~ $re_l ]] && v="${BASH_REMATCH[1]}"
  [[ "$v" =~ $re_d ]] && v="${BASH_REMATCH[1]}"
  printf '%s' "${v//./-}"
}

# Familia (primeiro token opus|sonnet|haiku|fable) de um ID normalizado (stdout).
familia_de() {
  local tk=() t IFS=- tem_claude=0
  read -ra tk <<<"$1"
  for t in ${tk[@]+"${tk[@]}"}; do [ "$t" = claude ] && tem_claude=1; done
  [ "$tem_claude" -eq 1 ] || return 0
  for t in ${tk[@]+"${tk[@]}"}; do
    case "$t" in opus|sonnet|haiku|fable) printf '%s' "$t"; return 0 ;; esac
  done
  return 0
}

# Filtros jq do meta e do transcript. Sao funcoes para que o --scan rode o MESMO filtro sobre uma
# entrada de controle e distinga "arquivo ilegivel" de "jq que falha".
jq_meta() {
  jq -r '
    def s: strings | gsub("[[:cntrl:]]"; "") | .[0:128];
    def tipo: if . == null then ""
              elif type == "string" then gsub("[[:cntrl:]]"; "") | .[0:257]
              else "<tipo_invalido:" + type + ">" end;
    if type == "object" then
      (.model | tipo),
      ((.effort | if type == "object" then (.level | s) else s end) // ""),
      ((.agentType | s) // ""),
      ((.pickedEffortModel | s) // "")
    else empty end' 2>/dev/null
}
jq_efet() {
  jq -Rr '
    fromjson? | objects | select(.type == "assistant")
    | (.message | objects | .model | strings)
    | select(. != "<synthetic>" and . != "")
    | gsub("[[:cntrl:]]"; "") | .[0:257]' 2>/dev/null | head -n 1
}
controle_filtros() {
  [ "$(printf '%s' '{"model":"opus"}' | jq_meta | head -n 1)" = opus ] \
    && [ "$(printf '%s\n' '{"type":"assistant","message":{"model":"claude-x"}}' | jq_efet)" = claude-x ]
}

# Troca controles ASCII e U+2028/U+2029 por espaco (saida do scan).
limpa() {
  local v="$1"
  v="${v//[[:cntrl:]]/ }"; v="${v//$'\xe2\x80\xa8'/ }"; v="${v//$'\xe2\x80\xa9'/ }"
  printf '%s' "$v"
}

# Julga um transcript de subagente. Entrada: caminho do transcript como veio. Saida, em globais:
# PEDIDO PEDIDO_EFFORT PICKED ORIGEM EFETIVO META_TYPE STATUS MOTIVO.
julga() {
  PEDIDO=""; PEDIDO_EFFORT=""; PICKED=""; ORIGEM=ausente; EFETIVO=""; META_TYPE=""; STATUS=""; MOTIVO=""
  local tp="$1" rp mp mrp META_OK=0 MF=() pl PN EN FAM
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
      if [ ! -r "$mrp" ]; then STATUS=indeterminado; MOTIVO=arquivo_ilegivel; return 0; fi
      mapfile -t MF < <(head -c 65536 "$mrp" 2>/dev/null | jq_meta)
      if [ "${#MF[@]}" -eq 4 ]; then
        META_OK=1; PEDIDO="${MF[0]}"; PEDIDO_EFFORT="${MF[1]}"; META_TYPE="${MF[2]}"; PICKED="${MF[3]}"
      fi
    fi
  fi
  if [ "$META_OK" -eq 1 ] && [ -n "$PEDIDO" ]; then ORIGEM=meta; fi

  if [ ! -f "$rp" ]; then STATUS=indeterminado; MOTIVO=transcript_ausente; return 0; fi
  if [ ! -e "$mp" ] && [ ! -L "$mp" ]; then STATUS=indeterminado; MOTIVO=meta_ausente; return 0; fi
  if [ "$META_OK" -ne 1 ]; then STATUS=indeterminado; MOTIVO=meta_ilegivel; return 0; fi

  if [ ! -r "$rp" ]; then STATUS=indeterminado; MOTIVO=arquivo_ilegivel; return 0; fi
  EFETIVO="$(head -c 1048576 "$rp" 2>/dev/null | head -n 400 | jq_efet)"
  if [ -z "$EFETIVO" ]; then STATUS=indeterminado; MOTIVO=sem_linha_assistant; return 0; fi

  pl="${PEDIDO,,}"
  if [ -z "$pl" ] || [ "$pl" = inherit ]; then STATUS=sem_pedido; MOTIVO=pedido_ausente_ou_inherit; return 0; fi
  # Pedido com `/`: so o prefixo `anthropic/` e aceito (a normalizacao toma o ultimo segmento, e um
  # prefixo arbitrario como `x/opus` afrouxaria o vocabulario do pedido).
  if [[ "$pl" == */* && "$pl" != anthropic/* ]]; then STATUS=pedido_desconhecido; MOTIVO=prefixo_do_pedido_desconhecido; return 0; fi
  if [ "${#PEDIDO}" -gt 256 ] || [ "${#EFETIVO}" -gt 256 ]; then STATUS=indeterminado; MOTIVO=id_longo; return 0; fi
  PN="$(norm_id "$PEDIDO")"
  EN="$(norm_id "$EFETIVO")"
  case "$PN" in
    opus|sonnet|haiku|fable)
      FAM="$(familia_de "$EN")"
      if [[ "$EN" == claude-* ]]; then
        if [ "$FAM" = "$PN" ]; then STATUS=honrado; MOTIVO=familia_igual
        else STATUS=DIVERGE; MOTIVO=familia_diferente; fi
      elif [ -n "$FAM" ] && [ "$FAM" != "$PN" ]; then
        # sem prefixo claude- mas com token claude e familia derivavel diferente da pedida
        STATUS=DIVERGE; MOTIVO=familia_diferente
      else STATUS=indeterminado; MOTIVO=efetivo_nao_reconhecido; fi ;;
    claude-*)
      if [ "$PN" = "$EN" ]; then STATUS=honrado; MOTIVO=id_igual
      elif [[ "$EN" == claude-* ]]; then STATUS=DIVERGE; MOTIVO=id_diferente
      else
        FAM="$(familia_de "$PN")"; FE="$(familia_de "$EN")"
        if [ -n "$FAM" ] && [ -n "$FE" ] && [ "$FAM" != "$FE" ]; then STATUS=DIVERGE; MOTIVO=familia_diferente
        else STATUS=indeterminado; MOTIVO=efetivo_nao_reconhecido; fi
      fi ;;
    *) STATUS=pedido_desconhecido; MOTIVO=valor_fora_do_vocabulario ;;
  esac
  return 0
}

# Grava a linha do evento. Em falha, LOGERR recebe o motivo curto; nunca aborta o hook.
LOGERR=""; PBYTES=""; PSHA=""; ILL=""; MULT=""
registra() {  # $1 session_id  $2 agent_id  $3 agent_type
  local linha err rc reason rot=flock
  LOGERR=""
  command -v flock >/dev/null 2>&1 || rot=sem_flock
  linha="$(jq -nac --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --arg sid "$1" --arg aid "$2" --arg at "$3" \
    --arg pm "$PEDIDO" --arg pe "$PEDIDO_EFFORT" --arg po "$ORIGEM" --arg pk "$PICKED" \
    --arg em "$EFETIVO" --arg st "$STATUS" --arg mo "$MOTIVO" --arg rot "$rot" \
    --arg pb "$PBYTES" --arg ph "$PSHA" --arg mu "$MULT" '
    {ts: $ts, session_id: $sid, agent_id: $aid, agent_type: $at, pedido_model: $pm[0:128],
     pedido_effort: $pe, pedido_origem: $po, picked_effort_model: $pk, efetivo_model: $em[0:128],
     status: $st, motivo: $mo, rotacao: $rot}
    + (if $pb == "" then {} else {payload_bytes: ($pb | tonumber), payload_sha12: $ph} end)
    + (if $mu == "1" then {payload_multiplo: true} else {} end)' 2>/dev/null)" \
    || { LOGERR=jq_falhou; return 0; }
  err="$(
    ( umask 077
      mkdir -p "$(dirname "$LOG")" || exit 1
      if command -v flock >/dev/null 2>&1; then
        exec 9>>"$LOG.lock" || exit 1
        if flock -w 5 9; then
          SZ=$(stat -c%s "$LOG" 2>/dev/null || echo 0)
          if [ "$SZ" -gt 2097152 ]; then
            [ -e "$LOG.2" ] && mv -f "$LOG.2" "$LOG.3"
            [ -e "$LOG.1" ] && mv -f "$LOG.1" "$LOG.2"
            mv -f "$LOG" "$LOG.1"
          fi
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

emite() {
  if [ "$STATUS" = DIVERGE ] || [ -n "$LOGERR" ] || [ -n "$ILL" ] || [ -n "$MULT" ] || [ "$MOTIVO" = caminho_fora_da_raiz ]; then
    jq -nac --arg st "$STATUS" --arg p "$PEDIDO" --arg e "$EFETIVO" --arg t "${AT:-desconhecido}" \
      --arg i "$AID" --arg le "$LOGERR" --arg ill "$ILL" --arg mu "$MULT" --arg mo "$MOTIVO" '
      [ (if $st == "DIVERGE"
         then "model-honor: pedido \($p[0:40]), rodou \($e[0:40]) (agente \($t[0:40]) \($i[0:40]))"
         else empty end),
        (if $mu == "1" then "model-honor: payload com varios objetos JSON; julgado so o primeiro" else empty end),
        (if $mo == "caminho_fora_da_raiz" then "model-honor: caminho do subagente fora da raiz permitida (tentativa de escape?); evento nao julgado" else empty end),
        (if $ill != "" then "model-honor: \($ill); evento nao julgado" else empty end),
        (if $le != "" then "model-honor: nao consegui gravar o log (\($le[0:80]))" else empty end) ]
      | join(" | ") | {systemMessage: .[0:300]}' 2>/dev/null
  fi
}

scan_main() {
  local NJ=0 DIR="" SINCE="" HAS_SINCE=0 SINCE_EP="" QUEBRADOS=0 d r ACHADOS=0 TOTAL=0 DIVS="" FERR ST M MT MP K S N
  declare -A CNT=() PAR=() MOT=()
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --since) [ "$#" -ge 2 ] || { echo "model-honor: --since exige valor" >&2; return 2; }; SINCE="$2"; HAS_SINCE=1; shift 2 ;;
      -*) echo "model-honor: opcao desconhecida: $1" >&2; return 2 ;;
      *) [ -z "$DIR" ] || { echo "model-honor: diretorio repetido" >&2; return 2; }; DIR="$1"; shift ;;
    esac
  done
  [ -n "$DIR" ] && [ -d "$DIR" ] || { echo "uso: model-honor.sh --scan <projects_dir> [--since <ISO8601>] (diretorio inexistente ou ausente)" >&2; return 2; }
  if [ "$HAS_SINCE" = 1 ] && [ -z "$SINCE" ]; then
    echo "model-honor: --since vazio (erro de uso; omita a opcao para varrer tudo)" >&2; return 2
  fi
  if [ -n "$SINCE" ]; then
    SINCE_EP="$(date -d "$SINCE" +%s 2>/dev/null)" || { echo "model-honor: --since invalido: $SINCE" >&2; return 2; }
  fi
  add_root "$DIR"
  # Symlinks de diretorio de projeto e de sessao: o alvo resolvido vira raiz permitida. Symlink
  # quebrado ou em laco (que `realpath -e` nao resolve) e contado em `ilegivel`.
  for d in "$DIR"/* "$DIR"/*/*; do
    [ -L "$d" ] || continue
    if r="$(realpath -e -- "$d" 2>/dev/null)" && [ -d "$r" ]; then add_root "$r"
    else QUEBRADOS=$((QUEBRADOS + 1)); fi
  done
  FERR="$(mktemp 2>/dev/null)" || FERR=/dev/null
  while IFS= read -r -d '' M; do
    ACHADOS=$((ACHADOS + 1))
    if [ -n "$SINCE_EP" ]; then
      MT="$(stat -c %Y "$M" 2>/dev/null || echo 0)"
      [ "$MT" -lt "$SINCE_EP" ] && continue
    fi
    julga "${M%.meta.json}.jsonl"
    TOTAL=$((TOTAL + 1))
    ST="$STATUS"
    if [ "$STATUS" = indeterminado ]; then
      case "$MOTIVO" in
        meta_ilegivel|sem_linha_assistant) controle_filtros || ST=jq_erro ;;
        arquivo_ilegivel|caminho_fora_da_raiz) ST=ilegivel ;;
      esac
    fi
    CNT[$ST]=$(( ${CNT[$ST]:-0} + 1 ))
    if [ "$ST" = indeterminado ] || [ "$ST" = pedido_desconhecido ]; then MOT[$MOTIVO]=$(( ${MOT[$MOTIVO]:-0} + 1 )); fi
    K="$(limpa "${PEDIDO:-?}")->$(limpa "${EFETIVO:-?}")"
    PAR[$K]=$(( ${PAR[$K]:-0} + 1 ))
    MP="$(limpa "$M")"
    [ "$STATUS" = DIVERGE ] && DIVS="$DIVS$(printf 'diverge\t%s\t%s\t%s' "$MP" "$(limpa "$PEDIDO")" "$(limpa "$EFETIVO")")"$'\n'
  done < <(find -L "$DIR" -mindepth 4 -maxdepth 4 \( -type f -o -type l \) -path '*/subagents/agent-*.meta.json' -print0 2>"$FERR")
  if [ -s "$FERR" ]; then
    N="$(wc -l < "$FERR" | tr -d ' ')"
    CNT[ilegivel]=$(( ${CNT[ilegivel]:-0} + N ))
  fi
  CNT[ilegivel]=$(( ${CNT[ilegivel]:-0} + QUEBRADOS ))
  [ "$FERR" = /dev/null ] || rm -f "$FERR"
  if [ "$ACHADOS" -eq 0 ] && [ "${CNT[ilegivel]:-0}" -eq 0 ]; then
    echo "model-honor: nenhum agent-*.meta.json sob $DIR (esperado */*/subagents/); varredura sem objeto" >&2
    return 2
  fi
  printf 'total\t%s\n' "$TOTAL"
  for S in DIVERGE honrado sem_pedido pedido_desconhecido indeterminado jq_erro ilegivel; do
    [ "${CNT[$S]:-0}" -gt 0 ] && printf 'status\t%s\t%s\n' "$S" "${CNT[$S]}"
  done
  if [ "$TOTAL" -gt 0 ]; then
    while IFS= read -r K; do printf 'par\t%s\t%s\n' "$K" "${PAR[$K]}"; done < <(printf '%s\n' "${!PAR[@]}" | LC_ALL=C sort)
  fi
  [ -n "$DIVS" ] && printf '%s' "$DIVS"
  # Nao julgados: indeterminado e pedido_desconhecido. `sem_pedido` nao conta (limite documentado
  # no ADR 0048), mas aparece no resumo.
  NJ=$(( ${CNT[indeterminado]:-0} + ${CNT[pedido_desconhecido]:-0} ))
  if [ "$NJ" -gt 0 ]; then
    {
      echo "model-honor: NAO JULGADOS $NJ de $TOTAL (sem_pedido ${CNT[sem_pedido]:-0}, fora da conta)"
      [ $(( ${CNT[honrado]:-0} + ${CNT[DIVERGE]:-0} )) -gt 0 ] || echo "model-honor: NENHUM JULGADO em $TOTAL"
      for K in "${!MOT[@]}"; do printf '  motivo %s: %s\n' "$K" "${MOT[$K]}"; done | LC_ALL=C sort
    } >&2
    for K in "${!MOT[@]}"; do printf 'motivo\t%s\t%s\n' "$K" "${MOT[$K]}"; done | LC_ALL=C sort
  fi
  if [ "${CNT[jq_erro]:-0}" -gt 0 ] || [ "${CNT[ilegivel]:-0}" -gt 0 ]; then
    echo "model-honor: varredura incompleta (jq_erro=${CNT[jq_erro]:-0}, ilegivel=${CNT[ilegivel]:-0}); o resultado nao vale" >&2
    return 2
  fi
  [ "${CNT[DIVERGE]:-0}" -gt 0 ] && return 1
  [ "$NJ" -gt 0 ] && return 3
  if [ "$TOTAL" -gt 0 ] && [ $(( ${CNT[honrado]:-0} + ${CNT[DIVERGE]:-0} )) -eq 0 ]; then
    echo "model-honor: NENHUM JULGADO em $TOTAL (so sem_pedido); a varredura nao verificou nenhum modelo" >&2
    return 3
  fi
  return 0
}

if [ "$MODO" = scan ]; then
  shift
  scan_main "$@"
  exit $?
fi

# ---- modo hook: nunca bloqueia ----
trap 'exit 0' EXIT
IN="$(cat 2>/dev/null || true)"
TIPO="$(printf '%s' "$IN" | jq -r 'type' 2>/dev/null)"; RCJ=$?
if [ "$RCJ" -ne 0 ] && command -v perl >/dev/null 2>&1; then
  # Surrogate solitario (`\ud83d` sem par) e rejeitado pelo jq. Troca por U+FFFD, tratando `\\`
  # (barra escapada) como texto: `\\ud83d` nao e escape.
  IN2="$(printf '%s' "$IN" | perl -0pe 's{(\\\\)|\\u([dD][89abAB][0-9a-fA-F]{2})\\u([dD][c-fC-F][0-9a-fA-F]{2})|\\u([dD][89a-fA-F][0-9a-fA-F]{2})}{ defined $1 ? $1 : defined $2 ? "\\u$2\\u$3" : "\\ufffd" }ge' 2>/dev/null)"
  TIPO="$(printf '%s' "$IN2" | jq -r 'type' 2>/dev/null)"; RCJ=$?
  [ "$RCJ" -eq 0 ] && IN="$IN2"
fi
if [ "$RCJ" -ne 0 ]; then
  # Payload nao vazio que nenhuma camada consegue ler: registra so tamanho e hash, nunca conteudo.
  PBYTES="$(printf '%s' "$IN" | wc -c | tr -d ' ')"
  PSHA="$(printf '%s' "$IN" | sha256sum 2>/dev/null | cut -c1-12)"
  PEDIDO=""; PEDIDO_EFFORT=""; PICKED=""; ORIGEM=ausente; EFETIVO=""; STATUS=indeterminado
  MOTIVO=payload_ilegivel; AT=""; AID=""
  registra "" "" ""
  ILL="payload ilegivel (${PBYTES} bytes, sha256 ${PSHA})"
  emite
  exit 0
fi
if [[ "$TIPO" == *$'\n'* ]]; then
  # Mais de um valor JSON no stdin: julga o primeiro OBJETO com `agent_transcript_path` (pula `{}`,
  # numeros, arrays e strings) e registra `payload_multiplo`; sem nenhum, `payload_sem_caminho`.
  MULT=1
  SEL="$(printf '%s' "$IN" | jq -c -n 'first(inputs | objects | select((.agent_transcript_path | type) == "string"))' 2>/dev/null)"
  if [ -z "$SEL" ]; then
    PEDIDO=""; PEDIDO_EFFORT=""; PICKED=""; ORIGEM=ausente; EFETIVO=""; STATUS=indeterminado
    MOTIVO=payload_sem_caminho; AT=""; AID=""
    registra "" "" ""
    ILL="stdin com varios valores e nenhum objeto com agent_transcript_path"
    emite
    exit 0
  fi
  IN="$SEL"; TIPO=object
fi
[ "$TIPO" = object ] || exit 0
if ! controle_filtros; then
  # jq passa a sonda e o `type`, mas falha nos filtros de extracao: sem isto o evento sumia mudo.
  PEDIDO=""; PEDIDO_EFFORT=""; PICKED=""; ORIGEM=ausente; EFETIVO=""; STATUS=indeterminado
  MOTIVO=jq_filtro_falhou; AT=""; AID=""
  registra "" "" ""
  ILL="jq falha nos filtros de extracao"
  emite
  exit 0
fi
mapfile -t PF < <(printf '%s' "$IN" | jq -r '
  def c($n): strings | gsub("[[:cntrl:]]"; "") | .[0:$n];
  ((.session_id | c(256)) // ""), ((.agent_id | c(256)) // ""),
  ((.agent_type | c(256)) // ""), ((.agent_transcript_path | c(4096)) // "")' 2>/dev/null)
if [ "${#PF[@]}" -ne 4 ]; then
  # O programa de extracao devolve sempre 4 linhas; menos que isso e jq que falha na extracao.
  PEDIDO=""; PEDIDO_EFFORT=""; PICKED=""; ORIGEM=ausente; EFETIVO=""; STATUS=indeterminado
  MOTIVO=jq_extracao_falhou; AT=""; AID=""
  registra "" "" ""
  ILL="jq falha na extracao dos campos do payload"
  emite
  exit 0
fi
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
emite
exit 0
