#!/usr/bin/env bash
# Suite do VERIFICADOR DE HONRA de modelo de subagente (evidence/hooks/model-honor.sh, ADR 0048).
#
# INVARIANTES PROTEGIDOS (os unicos que justificam teste aqui):
#  I-DETECCAO  pedido `opus` que rodou em Sonnet e DIVERGE e e anunciado. Medido: 48 subagentes
#              pediram `opus` e rodaram em Sonnet sem erro; nada detectava. O caso 1 e o controle
#              positivo - sem o hook, ele tem de ficar vermelho.
#  I-ABERTO    o hook nunca bloqueia (exit 0) e, com identificacao minima, registra
#              `indeterminado` em vez de sumir.
#  I-CAMINHO   caminho vindo do payload e hostil: nada e lido fora de
#              $HOME/.claude/projects e de ~/.local/share/ai-central/accounts/*/projects.
#  I5          nenhum conteudo (prompt, mensagem, transcript) chega ao log.
#
# Fixtures SINTETICAS e SEM conteudo: o transcript traz so {"type":"assistant","message":{"model":..}}.
# Cada caso e UM chk; os corpora parametrizados concatenam os resultados numa unica comparacao.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"

P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1"; echo "        got:  $2"; echo "        want: $3"; F=$((F+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "  DEPENDENCIA AUSENTE: jq. Estado: NAO VERIFICADO - a suite nao rodou."; exit 2; }

HOOK="$PWD/evidence/hooks/model-honor.sh"
BASH_BIN="$(command -v bash)"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home"
PROJ="$HOME/.claude/projects/proj/sess/subagents"
mkdir -p "$PROJ" "$HOME/.claude/logs"
LOG="$T/model-honor.jsonl"
export MODEL_HONOR_LOG="$LOG"

# mk <dir> <nome> <meta_json|NONE> <modelo_efetivo...>: cria agent-<nome>.{jsonl,meta.json}.
# Cada argumento de modelo vira uma linha assistant; "<none>" cria uma linha que nao e assistant.
mk(){
  local d="$1" n="$2" meta="$3"; shift 3
  mkdir -p "$d"
  : > "$d/agent-$n.jsonl"
  local m
  for m in "$@"; do
    if [ "$m" = "<none>" ]; then printf '{"type":"user","message":{"content":"x"}}\n' >> "$d/agent-$n.jsonl"; continue; fi
    jq -nc --arg m "$m" '{type:"assistant",message:{model:$m}}' >> "$d/agent-$n.jsonl"
  done
  if [ "$meta" != "NONE" ]; then printf '%s\n' "$meta" > "$d/agent-$n.meta.json"; fi
}
payload(){ jq -nc --arg p "$1" '{hook_event_name:"SubagentStop",session_id:"s1",agent_id:"a1",agent_type:"general-purpose",agent_transcript_path:$p,last_assistant_message:"texto qualquer"}'; }
# roda o hook; preenche OUT (stdout) e RC; ULT = status da ultima linha do log.
run(){
  : > "$LOG"
  OUT="$(printf '%s' "$1" | "$BASH_BIN" "$HOOK" 2>/dev/null)"; RC=$?
  ULT="$(tail -n1 "$LOG" 2>/dev/null | jq -r '.status // empty' 2>/dev/null)"
  [ -n "$ULT" ] || ULT=sem_linha
}
# resumo de um fixture pronto: "<rc>/<status>/<stdout vazio?>"
resumo(){ run "$(payload "$1")"; printf '%s/%s/%s' "$RC" "$ULT" "$([ -z "$OUT" ] && echo vazio || echo saida)"; }
meta(){ jq -nc --arg m "$1" '{agentType:"general-purpose",model:$m,effort:"high"}'; }

echo "== 1. controle positivo: opus pedido, Sonnet efetivo =="
mk "$PROJ" c1 "$(meta opus)" claude-sonnet-5-5
run "$(payload "$PROJ/agent-c1.jsonl")"
LINHA="$(tail -n1 "$LOG" 2>/dev/null)"
chk "1 DIVERGE: exit 0, systemMessage com pedido e efetivo, linha no log" \
  "$RC|$(printf '%s' "$OUT" | jq -r '.systemMessage // "sem"' 2>/dev/null | grep -c 'opus.*claude-sonnet-5-5')|$(printf '%s' "$LINHA" | jq -r '[.status,.pedido_model,.efetivo_model]|join(",")' 2>/dev/null)" \
  "0|1|DIVERGE,opus,claude-sonnet-5-5"

echo "== 2. alias honrado: mesma familia =="
mk "$PROJ" c2 "$(meta opus)" claude-opus-5-5
chk "2 opus -> claude-opus-5-5: honrado, stdout vazio" "$(resumo "$PROJ/agent-c2.jsonl")" "0/honrado/vazio"

echo "== 3. alias por familia, outra versao =="
mk "$PROJ" c3 "$(meta opus)" claude-opus-4-6
run "$(payload "$PROJ/agent-c3.jsonl")"
chk "3 opus -> claude-opus-4-6: honrado e registra o ID efetivo" \
  "$RC/$ULT/$(tail -n1 "$LOG" | jq -r .efetivo_model)" "0/honrado/claude-opus-4-6"

echo "== 4. fable: honrado e DIVERGE =="
mk "$PROJ" c4a "$(meta fable)" claude-fable-5-2
mk "$PROJ" c4b "$(meta fable)" claude-sonnet-5-5
chk "4 fable->fable honrado; fable->sonnet DIVERGE" \
  "$(resumo "$PROJ/agent-c4a.jsonl") $(resumo "$PROJ/agent-c4b.jsonl")" "0/honrado/vazio 0/DIVERGE/saida"

echo "== 5. ID completo exige igualdade exata =="
mk "$PROJ" c5a "$(meta claude-opus-5-5)" claude-opus-4-6
mk "$PROJ" c5b "$(meta claude-opus-5-5)" claude-opus-5-5
chk "5 ID diferente DIVERGE; ID igual honrado" \
  "$(resumo "$PROJ/agent-c5a.jsonl") $(resumo "$PROJ/agent-c5b.jsonl")" "0/DIVERGE/saida 0/honrado/vazio"

echo "== 6. pedido ausente, vazio, inherit, desconhecido, meta ausente =="
mk "$PROJ" c6a NONE claude-sonnet-5-5
mk "$PROJ" c6b "$(meta '')" claude-sonnet-5-5
mk "$PROJ" c6c "$(meta inherit)" claude-sonnet-5-5
mk "$PROJ" c6d '{"agentType":"general-purpose"}' claude-sonnet-5-5
mk "$PROJ" c6e "$(meta gpt-9)" claude-sonnet-5-5
R6=""; for n in c6a c6b c6c c6d c6e; do R6="$R6 $(resumo "$PROJ/agent-$n.jsonl")"; done
chk "6 meta ausente=indeterminado; vazio/inherit/sem campo=sem_pedido; desconhecido=pedido_desconhecido" \
  "$R6" " 0/indeterminado/vazio 0/sem_pedido/vazio 0/sem_pedido/vazio 0/sem_pedido/vazio 0/pedido_desconhecido/vazio"

echo "== 7. transcript inexistente; transcript do PAI nunca e lido =="
meta opus > "$PROJ/agent-c7.meta.json"
run "$(payload "$PROJ/agent-c7.jsonl")"; R7A="$RC/$ULT"
mk "$HOME/.claude/projects/proj/sess" pai "$(meta opus)" claude-sonnet-5-5
SO_PAI="$(jq -nc --arg p "$HOME/.claude/projects/proj/sess/agent-pai.jsonl" '{session_id:"s1",agent_id:"a1",agent_type:"x",transcript_path:$p}')"
run "$SO_PAI"; R7B="$RC/$ULT"
chk "7 transcript ausente e payload so com transcript_path: indeterminado, exit 0, linha registrada" \
  "$R7A $R7B" "0/indeterminado 0/indeterminado"

echo "== 8. caminho hostil: nada lido fora da raiz =="
# Cada alvo tem conteudo que daria DIVERGE se fosse lido; indeterminado prova que nao foi.
FORA="$T/fora/subagents"
mk "$FORA" abs "$(meta opus)" claude-sonnet-5-5
mk "$FORA" real "$(meta opus)" claude-sonnet-5-5
mk "$HOME/.claude/outside/subagents" dd "$(meta opus)" claude-sonnet-5-5
ln -sfn "$FORA/agent-real.jsonl" "$PROJ/agent-lnk.jsonl"
ln -sfn "$FORA/agent-real.meta.json" "$PROJ/agent-lnk.meta.json"
mk "$PROJ" metalnk NONE claude-sonnet-5-5
ln -sfn "$FORA/agent-abs.meta.json" "$PROJ/agent-metalnk.meta.json"
mk "$PROJ" sufixo "$(meta opus)" claude-sonnet-5-5
cp "$PROJ/agent-sufixo.jsonl" "$PROJ/notas.jsonl"; cp "$PROJ/agent-sufixo.meta.json" "$PROJ/notas.meta.json"
R8=""
for cam in "$FORA/agent-abs.jsonl" \
           "$PROJ/../../../../outside/subagents/agent-dd.jsonl" \
           "$PROJ/agent-lnk.jsonl" \
           "$PROJ/agent-metalnk.jsonl" \
           "$PROJ/notas.jsonl"; do
  R8="$R8 $(resumo "$cam")"
done
chk "8 absoluto, ../, symlink do transcript, symlink do meta, sem sufixo agent-*: indeterminado" \
  "$R8" " 0/indeterminado/vazio 0/indeterminado/vazio 0/indeterminado/vazio 0/indeterminado/vazio 0/indeterminado/vazio"

echo "== 9. entrada que nao e JSON e entrada vazia =="
R9=""
for entrada in 'isto nao e json {' '' '[1,2' 'null'; do
  : > "$LOG"; OUT9="$(printf '%s' "$entrada" | "$BASH_BIN" "$HOOK" 2>&1)"; RC9=$?
  R9="$R9 $RC9/${#OUT9}/$(wc -l < "$LOG" | tr -d ' ')"
done
chk "9 exit 0, sem saida e sem linha de log" "$R9" " 0/0/0 0/0/0 0/0/0 0/0/0"

echo "== 10. primeira linha assistant <synthetic> e ignorada =="
mk "$PROJ" c10 "$(meta opus)" "<none>" "<synthetic>" claude-opus-5-5 claude-sonnet-5-5
chk "10 usa a primeira real (claude-opus-5-5), nao a synthetic nem a ultima" "$(resumo "$PROJ/agent-c10.jsonl")" "0/honrado/vazio"

echo "== 11. sem jq no PATH =="
# stdin por here-string: com pipe, o printf recebe SIGPIPE quando o hook sai sem ler (rc 141 do
# pipeline, artefato da bancada e nao do hook).
R11="$(env PATH=/nonexistent "$BASH_BIN" "$HOOK" 2>&1 <<<"$(payload "$PROJ/agent-c1.jsonl")"; echo "rc=$?")"
chk "11 exit 0 sem saida" "$R11" "rc=0"

echo "== 12. I5: nenhum conteudo chega ao log =="
SEGREDO="SEGREDO-FAKE-$$-zzTOKEN"
{ jq -nc --arg s "$SEGREDO" '{type:"user",message:{content:$s}}'
  jq -nc --arg s "$SEGREDO" '{type:"assistant",message:{model:"claude-sonnet-5-5",content:[{type:"text",text:$s}]}}'; } > "$PROJ/agent-c12.jsonl"
meta opus > "$PROJ/agent-c12.meta.json"
PL12="$(jq -nc --arg p "$PROJ/agent-c12.jsonl" --arg s "$SEGREDO" '{session_id:"s1",agent_id:"a1",agent_type:"x",agent_transcript_path:$p,last_assistant_message:$s}')"
run "$PL12"
chk "12 DIVERGE registrado e segredo ausente do log e do stdout" \
  "$ULT/$(grep -c "$SEGREDO" "$LOG")/$(printf '%s' "$OUT" | grep -c "$SEGREDO")" "DIVERGE/0/0"

echo "== 13. --scan =="
S1="$T/scan1"; SD="$S1/pa/sa/subagents"
mk "$SD" d1 "$(meta opus)" claude-sonnet-5-5
mk "$SD" d2 "$(meta opus)" claude-sonnet-5-5
mk "$SD" h1 "$(meta sonnet)" claude-sonnet-5-5
SCAN="$("$BASH_BIN" "$HOOK" --scan "$S1")"; RS1=$?
CONT="$(printf '%s\n' "$SCAN" | awk -F'\t' '$1=="status"{printf "%s=%s ",$2,$3} $1=="par"&&$2=="opus->claude-sonnet-5-5"{printf "par=%s ",$3}')"
S2="$T/scan2"; mk "$S2/pa/sa/subagents" ok1 "$(meta opus)" claude-opus-5-5
"$BASH_BIN" "$HOOK" --scan "$S2" >/dev/null; RS2=$?
touch -d '2020-01-01' "$SD/agent-d1.meta.json"
SINCE="$("$BASH_BIN" "$HOOK" --scan "$S1" --since 2024-01-01T00:00:00Z | awk -F'\t' '$1=="status"&&$2=="DIVERGE"{print $3}')"
"$BASH_BIN" "$HOOK" --scan "$T/nao-existe" >/dev/null 2>&1; RS3=$?
chk "13 2 DIVERGE+1 honrado: contagens e exit 1; sem DIVERGE exit 0; --since filtra; uso errado exit 2" \
  "$RS1 $CONT$RS2 since=$SINCE $RS3" "1 DIVERGE=2 honrado=1 par=2 0 since=1 2"

echo "== 14. log nao legivel por outros usuarios =="
rm -f "$LOG"; printf '%s' "$(payload "$PROJ/agent-c1.jsonl")" | "$BASH_BIN" "$HOOK" >/dev/null 2>&1
chk "14 permissao do log apos DIVERGE" "$(stat -c %a "$LOG" 2>/dev/null)" "600"

echo
echo "TOTAL=$((P+F)) PASS=$P FAIL=$F"
# Pino da propria contagem (convencao de scripts/status.sh): caso removido em silencio e vermelho.
EXPECTED=14
[ "$((P+F))" -eq "$EXPECTED" ] || { echo "CONTAGEM INESPERADA: executados=$((P+F)) esperado=$EXPECTED"; exit 1; }
[ "$F" -eq 0 ]
