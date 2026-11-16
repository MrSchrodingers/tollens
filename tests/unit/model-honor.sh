#!/usr/bin/env bash
# Suite do VERIFICADOR DE HONRA de modelo de subagente (evidence/hooks/model-honor.sh, ADR 0048).
#
# INVARIANTES PROTEGIDOS (os unicos que justificam teste aqui):
#  I-DETECCAO  pedido `opus` que rodou em Sonnet e DIVERGE e e anunciado. O caso 1 e o controle
#              positivo.
#  I-ABERTO    o hook nunca bloqueia (exit 0) e, com identificacao minima, registra
#              `indeterminado` em vez de sumir.
#  I-NAO-SILENCIO  perder o instrumento (sem jq, log nao gravavel, campo gigante) nao pode apagar
#              um DIVERGE nem passar sem sinal.
#  I-HISTORICO rotacao e append concorrentes nao perdem evento nem historico.
#  I-CAMINHO   caminho vindo do payload e hostil: nada e lido fora de
#              $HOME/.claude/projects e de ~/.local/share/ai-central/accounts/*/projects, e o
#              transcript do PAI nunca substitui o do subagente.
#  I-REGRA     a comparacao nao produz falso DIVERGE por forma do ID nem falso honrado por
#              casamento frouxo; pedido malformado nao vira `sem_pedido`.
#  I-TETO      leitura de transcript e meta tem teto; campo textual do log e da saida tem teto.
#  I5          nenhum conteudo (prompt, mensagem, transcript) chega ao log.
#  I-ROBUSTEZ  payload que o jq rejeita (surrogate solitario) e jq que falha so no filtro nao
#              apagam o evento nem o scan; o scan nunca le stdin e nunca sai 0 com instrumento
#              quebrado.
#  I-REAL      o hook aceita a forma REAL do evento (chaves e `effort` objeto, ADR 0015 regra 1).
#
# Fixtures SINTETICAS e SEM conteudo: o transcript traz so {"type":"assistant","message":{"model":..}}.
# Cada caso e UM chk; os corpora parametrizados concatenam os resultados numa unica comparacao.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"

P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1"; echo "        got:  $2"; echo "        want: $3"; F=$((F+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "  DEPENDENCIA AUSENTE: jq. Estado: NAO VERIFICADO - a suite nao rodou."; exit 2; }

HOOK="${MODEL_HONOR_HOOK:-$PWD/evidence/hooks/model-honor.sh}"
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
mkdir -p "$T/fakebin"
printf '#!/bin/sh\nexit 3\n' > "$T/fakebin/jq"; chmod +x "$T/fakebin/jq"
meta(){ jq -nc --arg m "$1" '{agentType:"general-purpose",model:$m,effort:"high"}'; }
campo(){ tail -n1 "$LOG" 2>/dev/null | jq -r "$1" 2>/dev/null; }

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
  "$RC/$ULT/$(campo .efetivo_model)" "0/honrado/claude-opus-4-6"

echo "== 4. fable: honrado e DIVERGE =="
mk "$PROJ" c4a "$(meta fable)" claude-fable-5-2
mk "$PROJ" c4b "$(meta fable)" claude-sonnet-5-5
chk "4 fable->fable honrado; fable->sonnet DIVERGE" \
  "$(resumo "$PROJ/agent-c4a.jsonl") $(resumo "$PROJ/agent-c4b.jsonl")" "0/honrado/vazio 0/DIVERGE/saida"

echo "== 5. ID completo exige igualdade exata =="
mk "$PROJ" c5a "$(meta claude-opus-5-5)" claude-opus-4-6
mk "$PROJ" c5b "$(meta claude-opus-5-5)" claude-opus-5-5
mk "$PROJ" c5c "$(meta claude-opus-5-5)" claude-opus-5-55
chk "5 ID diferente DIVERGE; ID igual honrado; ID com sufixo a mais DIVERGE (nao e prefixo)" \
  "$(resumo "$PROJ/agent-c5a.jsonl") $(resumo "$PROJ/agent-c5b.jsonl") $(resumo "$PROJ/agent-c5c.jsonl")" \
  "0/DIVERGE/saida 0/honrado/vazio 0/DIVERGE/saida"

echo "== 6. pedido ausente, vazio, inherit, desconhecido, meta ausente =="
mk "$PROJ" c6a NONE claude-sonnet-5-5
mk "$PROJ" c6b "$(meta '')" claude-sonnet-5-5
mk "$PROJ" c6c "$(meta inherit)" claude-sonnet-5-5
mk "$PROJ" c6d '{"agentType":"general-purpose"}' claude-sonnet-5-5
mk "$PROJ" c6e "$(meta gpt-9)" claude-sonnet-5-5
mk "$PROJ" c6f "$(meta INHERIT)" claude-sonnet-5-5
R6=""; for n in c6a c6b c6c c6d c6e c6f; do R6="$R6 $(resumo "$PROJ/agent-$n.jsonl")"; done
chk "6 meta ausente=indeterminado; vazio/inherit/sem campo=sem_pedido; desconhecido=pedido_desconhecido" \
  "$R6" " 0/indeterminado/vazio 0/sem_pedido/vazio 0/sem_pedido/vazio 0/sem_pedido/vazio 0/pedido_desconhecido/vazio 0/sem_pedido/vazio"

# Alvos hostis usados nos casos 7 e 8. Cada um tem conteudo que daria DIVERGE se fosse lido;
# indeterminado prova que nao foi.
FORA="$T/fora/subagents"
mk "$FORA" abs "$(meta opus)" claude-sonnet-5-5
mk "$FORA" real "$(meta opus)" claude-sonnet-5-5
mk "$HOME/.claude/outside/subagents" dd "$(meta opus)" claude-sonnet-5-5

echo "== 7. o transcript do PAI nunca substitui o do subagente =="
meta opus > "$PROJ/agent-c7.meta.json"
run "$(payload "$PROJ/agent-c7.jsonl")"; R7A="$RC/$ULT"
# pai com nome que CASA o padrao agent-*.jsonl, meta e conteudo divergentes: so `transcript_path`.
mk "$PROJ" pai "$(meta opus)" claude-sonnet-5-5
run "$(jq -nc --arg p "$PROJ/agent-pai.jsonl" '{session_id:"s1",agent_id:"a1",agent_type:"x",transcript_path:$p}')"
R7B="$RC/$ULT/$(campo .efetivo_model)"
# agent_transcript_path hostil (symlink agent-x7.jsonl para fora) com o pai valido ao lado.
ln -sfn "$FORA/agent-real.jsonl" "$PROJ/agent-x7.jsonl"
run "$(jq -nc --arg a "$PROJ/agent-x7.jsonl" --arg p "$PROJ/agent-pai.jsonl" '{session_id:"s1",agent_id:"a1",agent_type:"x",agent_transcript_path:$a,transcript_path:$p}')"
R7C="$RC/$ULT/$(campo .efetivo_model)"
chk "7 transcript ausente, so transcript_path do pai, e agent path hostil com pai ao lado: indeterminado e nada lido" \
  "$R7A $R7B $R7C" "0/indeterminado 0/indeterminado/ 0/indeterminado/"

echo "== 8. caminho hostil: nada lido fora da raiz =="
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

echo "== 9. entrada vazia ou JSON nao objeto: mudo; entrada ilegivel: registrada =="
R9=""
for entrada in 'isto nao e json {' '' '[1,2' 'null'; do
  : > "$LOG"; OUT9="$(printf '%s' "$entrada" | "$BASH_BIN" "$HOOK" 2>&1)"; RC9=$?
  R9="$R9 $RC9/$([ -n "$OUT9" ] && echo msg || echo mudo)/$(wc -l < "$LOG" | tr -d ' ')/$(campo .motivo)"
done
chk "9 exit 0; vazio e null: mudo; nao-JSON: 1 linha payload_ilegivel e aviso" "$R9" \
  " 0/msg/1/payload_ilegivel 0/mudo/0/ 0/msg/1/payload_ilegivel 0/mudo/0/"

echo "== 10. primeira linha assistant <synthetic> e ignorada =="
mk "$PROJ" c10 "$(meta opus)" "<none>" "<synthetic>" claude-opus-5-5 claude-sonnet-5-5
chk "10 usa a primeira real (claude-opus-5-5), nao a synthetic nem a ultima" "$(resumo "$PROJ/agent-c10.jsonl")" "0/honrado/vazio"

echo "== 11. sem jq no PATH: o instrumento nao desliga sem sinal =="
# stdin por here-string: com pipe, o printf recebe SIGPIPE quando o hook sai sem ler (rc 141 do
# pipeline, artefato da bancada e nao do hook).
OUT11="$(env PATH=/nonexistent "$BASH_BIN" "$HOOK" 2>&1 <<<"$(payload "$PROJ/agent-c1.jsonl")")"; RC11=$?
chk "11 exit 0 e systemMessage (JSON valido) que menciona jq" \
  "$RC11/$(printf '%s' "$OUT11" | jq -r '.systemMessage // "sem" | test("jq")' 2>/dev/null)" "0/true"

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
# meta fora do esquema */*/subagents/ (um nivel mais fundo): nao pertence ao escopo do scan.
mk "$S1/pa/sa/extra/subagents" deep "$(meta opus)" claude-sonnet-5-5
SCAN="$("$BASH_BIN" "$HOOK" --scan "$S1")"; RS1=$?
CONT="$(printf '%s\n' "$SCAN" | awk -F'\t' '$1=="total"{printf "total=%s ",$2} $1=="status"{printf "%s=%s ",$2,$3} $1=="par"&&$2=="opus->claude-sonnet-5-5"{printf "par=%s ",$3}')"
S2="$T/scan2"; mk "$S2/pa/sa/subagents" ok1 "$(meta opus)" claude-opus-5-5
"$BASH_BIN" "$HOOK" --scan "$S2" >/dev/null; RS2=$?
touch -d '2020-01-01' "$SD/agent-d1.meta.json"
# fronteira do --since: meta com mtime IGUAL ao limite entra.
mk "$SD" b1 "$(meta opus)" claude-sonnet-5-5
touch -d @1704067200 "$SD/agent-b1.meta.json"
SINCE="$("$BASH_BIN" "$HOOK" --scan "$S1" --since 2024-01-01T00:00:00Z | awk -F'\t' '$1=="status"&&$2=="DIVERGE"{print $3}')"
"$BASH_BIN" "$HOOK" --scan "$T/nao-existe" >/dev/null 2>&1; RS3=$?
chk "13 2 DIVERGE+1 honrado: contagens e exit 1; sem DIVERGE exit 0; --since filtra e inclui a fronteira; uso errado exit 2" \
  "$RS1 $CONT$RS2 since=$SINCE $RS3" "1 total=3 DIVERGE=2 honrado=1 par=2 0 since=2 2"

echo "== 14. log nao legivel por outros usuarios =="
rm -f "$LOG"; printf '%s' "$(payload "$PROJ/agent-c1.jsonl")" | "$BASH_BIN" "$HOOK" >/dev/null 2>&1
chk "14 permissao do log apos DIVERGE" "$(stat -c %a "$LOG" 2>/dev/null)" "600"

echo "== 15. campo gigante no payload nao apaga o DIVERGE =="
GIGA="$(head -c 140000 /dev/zero | tr '\0' T)"
PL15="$(printf '{"session_id":"s1","agent_id":"a1","agent_type":"%s","agent_transcript_path":"%s"}' "$GIGA" "$PROJ/agent-c1.jsonl")"
run "$PL15"
chk "15 DIVERGE registrado, agent_type no teto, systemMessage JSON valido no teto" \
  "$RC/$ULT/$([ "$(campo '.agent_type|length')" -le 256 ] && echo teto)/$(printf '%s' "$OUT" | jq -r '.systemMessage|length<=300' 2>/dev/null)" \
  "0/DIVERGE/teto/true"

echo "== 16. 60 hooks concorrentes no limite de rotacao: nenhum evento nem historico perdido =="
# historico 1 KB abaixo do limite: a rotacao ocorre no meio da rajada, quando varios hooks ja estao vivos.
head -c 2097100 /dev/zero | tr '\0' H > "$LOG"; printf '\n' >> "$LOG"; rm -f "$LOG.1"
for i in $(seq 1 60); do
  printf '{"session_id":"s1","agent_id":"par%s","agent_type":"x","agent_transcript_path":"%s"}' "$i" "$PROJ/agent-c1.jsonl" | "$BASH_BIN" "$HOOK" >/dev/null 2>&1 &
done
wait
N16="$(cat "$LOG" "$LOG.1" 2>/dev/null | jq -Rr 'fromjson? | .agent_id // empty' 2>/dev/null | sort -u | wc -l | tr -d ' ')"
# A corrida acima e probabilistica; a trava e verificada de forma deterministica: com a trava
# retida por outro processo por ~1,0 s, o hook espera em vez de rotacionar/gravar por cima.
rm -f "$T/lk-ok"
( exec 9>>"$LOG.lock"; flock 9; : > "$T/lk-ok"; sleep 1.0 ) &
LKPID=$!
until [ -e "$T/lk-ok" ]; do sleep 0.05; done
T0="$(date +%s%N)"
printf '%s' "$(payload "$PROJ/agent-c1.jsonl")" | "$BASH_BIN" "$HOOK" >/dev/null 2>&1
T1="$(date +%s%N)"
wait "$LKPID"
R16L="$([ $((T1 - T0)) -ge 500000000 ] && echo esperou || echo nao_esperou)"
chk "16 60 eventos distintos e historico de ~2 MB intactos em .1; hook espera a trava retida" \
  "$N16/$([ "$(stat -c %s "$LOG.1" 2>/dev/null || echo 0)" -ge 2097100 ] && echo historico)/$R16L" "60/historico/esperou"

echo "== 17. limiar de rotacao: no limite nao rotaciona, acima rotaciona =="
head -c 2097151 /dev/zero | tr '\0' H > "$LOG"; printf '\n' >> "$LOG"; rm -f "$LOG.1"
printf '%s' "$(payload "$PROJ/agent-c1.jsonl")" | "$BASH_BIN" "$HOOK" >/dev/null 2>&1
R17A="$([ -e "$LOG.1" ] && echo rotou || echo manteve)"
head -c 2097152 /dev/zero | tr '\0' H > "$LOG"; printf '\n' >> "$LOG"; rm -f "$LOG.1"
printf '%s' "$(payload "$PROJ/agent-c1.jsonl")" | "$BASH_BIN" "$HOOK" >/dev/null 2>&1
R17B="$([ "$(stat -c %s "$LOG.1" 2>/dev/null || echo 0)" -eq 2097153 ] && echo rotou || echo manteve)"
chk "17 exatamente 2097152 B: mantem; 2097153 B: rotaciona preservando o antigo" "$R17A $R17B" "manteve rotou"
rm -f "$LOG.1"

echo "== 18. log nao gravavel: exit 0 e systemMessage, DIVERGE nao se perde =="
: > "$T/arquivo-regular"
R18=""
for cam in "$PROJ/agent-c1.jsonl" "$PROJ/agent-c2.jsonl"; do
  O18="$(printf '%s' "$(payload "$cam")" | MODEL_HONOR_LOG="$T/arquivo-regular/sub/log.jsonl" "$BASH_BIN" "$HOOK" 2>/dev/null)"; RC18=$?
  R18="$R18 $RC18/$(printf '%s' "$O18" | jq -r '.systemMessage|test("nao consegui gravar o log \\(.+\\)")' 2>/dev/null)/$(printf '%s' "$O18" | jq -r '.systemMessage|test("opus")' 2>/dev/null)"
done
chk "18 DIVERGE e honrado com log inviavel: avisa a falha; DIVERGE mantem o aviso de divergencia" \
  "$R18" " 0/true/true 0/true/false"

echo "== 19. --scan: erro de instrumento sai 2 com mensagem em stderr =="
mkdir -p "$T/fakebin" "$T/scanvazio"
printf '#!/bin/sh\nexit 3\n' > "$T/fakebin/jq"; chmod +x "$T/fakebin/jq"
R19=""
for caso in "jqquebrado:$S1" "inexistente:$T/nao-existe" "total0:$T/scanvazio"; do
  if [ "${caso%%:*}" = jqquebrado ]; then
    E19="$(env PATH="$T/fakebin:$PATH" "$BASH_BIN" "$HOOK" --scan "${caso#*:}" 2>&1 >/dev/null)"; RC19=$?
  else
    E19="$("$BASH_BIN" "$HOOK" --scan "${caso#*:}" 2>&1 >/dev/null)"; RC19=$?
  fi
  R19="$R19 $RC19/$([ -n "$E19" ] && echo stderr || echo mudo)"
done
chk "19 jq que falha, diretorio inexistente e total 0: exit 2 com stderr" "$R19" " 2/stderr 2/stderr 2/stderr"

echo "== 20. model do meta com tipo errado nao vira sem_pedido =="
R20=""
for mj in '{"model":1}' '{"model":[]}' '{"model":{}}' '{"model":true}' '{"model":false}' '{"model":null}' '{"model":""}'; do
  mk "$PROJ" c20 "$mj" claude-sonnet-5-5
  run "$(payload "$PROJ/agent-c20.jsonl")"; R20="$R20 $ULT"
done
chk "20 numero/array/objeto/booleano=pedido_desconhecido; null e vazio=sem_pedido" \
  "$R20" " pedido_desconhecido pedido_desconhecido pedido_desconhecido pedido_desconhecido pedido_desconhecido sem_pedido sem_pedido"

echo "== 21. normalizacao do ID e familia por token =="
R21=""
par21(){ mk "$PROJ" c21 "$(meta "$1")" "$2"; run "$(payload "$PROJ/agent-c21.jsonl")"; R21="$R21 $ULT"; }
par21 'Claude-Opus-5-5' claude-opus-5-5
par21 'claude-opus-5-5[1m]' claude-opus-5-5
par21 'anthropic.claude-opus-5-5' claude-opus-5-5
par21 'claude-opus-5-5@20261101' claude-opus-5-5
par21 'OPUS' claude-opus-5-5
par21 sonnet claude-3-5-sonnet-20241022
par21 haiku anthropic.claude-haiku-5-5
par21 sonnet claude-opus-5-5-sonnet-x
par21 opus claude-3-5-sonnet-20241022
chk "21 normalizacao e familia por token honram; casamento frouxo e familia errada DIVERGEM" \
  "$R21" " honrado honrado honrado honrado honrado honrado honrado DIVERGE DIVERGE"

echo "== 22. sanitizacao: log em uma linha sem U+2028 cru; TSV do --scan sem TAB ou quebra de linha =="
SID22="$(printf 's\xe2\x80\xa8x\001y\nz')"
run "$(jq -nc --arg s "$SID22" --arg p "$PROJ/agent-c1.jsonl" '{session_id:$s,agent_id:"a1",agent_type:"x",agent_transcript_path:$p}')"
R22A="$(wc -l < "$LOG" | tr -d ' ')/$(LC_ALL=C grep -c "$(printf '\xe2\x80\xa8')" "$LOG")/$(campo '.session_id|test("[[:cntrl:]]")')"
S3="$T/scan3"
mk "$S3/p"$'\t'"x/sa/subagents" t1 "$(meta opus)" claude-sonnet-5-5
mk "$S3/p"$'\n'"y/sa/subagents" n1 "$(meta opus)" claude-sonnet-5-5
R22B="$("$BASH_BIN" "$HOOK" --scan "$S3" | awk -F'\t' '$1=="diverge"{printf "%s ",NF}')"
chk "22 log: 1 linha, 0 U+2028 crus, sem controle; scan: linhas diverge com 4 campos" \
  "$R22A $R22B" "1/0/false 4 4 "

echo "== 23. tetos de leitura: transcript 1 MiB e 400 linhas, meta 64 KiB =="
R23=""
# (a) primeira linha de 1,1 MiB antes da primeira assistant
{ head -c 1153434 /dev/zero | tr '\0' x; printf '\n'; jq -nc '{type:"assistant",message:{model:"claude-sonnet-5-5"}}'; } > "$PROJ/agent-c23a.jsonl"
meta opus > "$PROJ/agent-c23a.meta.json"
run "$(payload "$PROJ/agent-c23a.jsonl")"; R23="$R23 $ULT"
# (b) assistant na linha 400 (le) e na 401 (nao le)
for alvo in 400 401; do
  { for _ in $(seq 1 $((alvo-1))); do printf '{"type":"user","message":{"content":"x"}}\n'; done
    jq -nc '{type:"assistant",message:{model:"claude-sonnet-5-5"}}'; } > "$PROJ/agent-c23b.jsonl"
  meta opus > "$PROJ/agent-c23b.meta.json"
  run "$(payload "$PROJ/agent-c23b.jsonl")"; R23="$R23 $ULT"
done
# (c) meta valido com 70000 B: acima do teto, nao e lido
mk "$PROJ" c23c NONE claude-sonnet-5-5
jq -nc --arg pad "$(head -c 70000 /dev/zero | tr '\0' p)" '{model:"opus",pad:$pad}' > "$PROJ/agent-c23c.meta.json"
run "$(payload "$PROJ/agent-c23c.jsonl")"; R23="$R23 $ULT/$(campo .motivo)"
chk "23 1a linha de 1,1 MiB e linha 401: indeterminado; linha 400: DIVERGE; meta > 64 KiB: meta_ilegivel" \
  "$R23" " indeterminado DIVERGE indeterminado indeterminado/meta_ilegivel"

echo "== 24. campos informativos do registro: pedido_origem e picked_effort_model =="
jq -nc '{agentType:"general-purpose",model:"opus",effort:"high",pickedEffortModel:"claude-fable-5-2"}' > "$PROJ/agent-c24a.meta.json"
mk "$PROJ" c24a "$(cat "$PROJ/agent-c24a.meta.json")" claude-opus-5-5
run "$(payload "$PROJ/agent-c24a.jsonl")"
R24A="$ULT/$(campo '[.pedido_origem,.picked_effort_model]|join(",")')"
mk "$PROJ" c24b '{"agentType":"general-purpose","pickedEffortModel":"claude-sonnet-5-5"}' claude-opus-5-5
run "$(payload "$PROJ/agent-c24b.jsonl")"
R24B="$ULT/$(campo '[.pedido_origem,.picked_effort_model]|join(",")')"
chk "24 picked nao julga (opus->opus-5-5 honrado com picked fable); origem meta ou ausente" \
  "$R24A $R24B" "honrado/meta,claude-fable-5-2 sem_pedido/ausente,claude-sonnet-5-5"


echo "== 25. payload que o jq rejeita nao apaga o evento; jq quebrado no hook avisa =="
R25=""
for sg in '\ud83d' '\udc00' '\\ud83d'; do
  run "$(printf '{"session_id":"s%s","agent_id":"a1","agent_type":"t","agent_transcript_path":"%s"}' "$sg" "$PROJ/agent-c1.jsonl")"; R25="$R25 $ULT"
done
run "$(printf '{"session_id":"s%s","agent_id":"a1","agent_type":"t%s","agent_transcript_path":"%s"}' '\\ud83d' '\ud83d' "$PROJ/agent-c1.jsonl")"
R25="$R25 $ULT/$(campo .session_id)"
SEG25="SEGREDO-ILEGIVEL-$$"
run "$(printf 'lixo %s {"x":"\\ud83d' "$SEG25")"
R25="$R25 $(campo '[.status,.motivo,(.payload_bytes|type),(.payload_sha12|test("^[0-9a-f]{12}$"))]|join(",")')/$(grep -c "$SEG25" "$LOG")/$([ -n "$OUT" ] && echo msg)"
J25="$(env PATH="$T/fakebin:$PATH" "$BASH_BIN" "$HOOK" 2>&1 <<<"$(payload "$PROJ/agent-c1.jsonl")")"; RJ25=$?
R25="$R25 $RJ25/$(printf '%s' "$J25" | jq -r '.systemMessage|test("jq")' 2>/dev/null)"
chk "25 surrogate solitario (alto, baixo) recuperado; barra escapada e texto; ilegivel registrado sem conteudo; jq quebrado avisa" \
  "$R25" " DIVERGE DIVERGE DIVERGE DIVERGE/s\\ud83d indeterminado,payload_ilegivel,number,true/0/msg 0/true"

echo "== 26. --scan com --since que exclui tudo: total 0, exit 0, mudo, nunca le stdin =="
S26="$(timeout 3 "$BASH_BIN" "$HOOK" --scan "$S1" --since 2099-01-01T00:00:00Z 2>"$T/e26" < <(sleep 4))"; RC26=$?
chk "26 exit 0, total 0, stderr vazio (nao pendura com stdin aberto)" \
  "$RC26/$(printf '%s\n' "$S26" | awk -F'\t' '$1=="total"{print $2}')/$([ -s "$T/e26" ] && echo stderr || echo mudo)" "0/0/mudo"

echo "== 27. --scan: jq que falha so no filtro e diretorio ilegivel saem 2 =="
printf '#!/bin/sh\n[ "$1" = "-n" ] && { echo 2; exit 0; }\nexit 3\n' > "$T/fakebin/jq"
E27="$(env PATH="$T/fakebin:$PATH" "$BASH_BIN" "$HOOK" --scan "$S1" 2>"$T/e27")"; RC27A=$?
R27="$RC27A/$(printf '%s\n' "$E27" | awk -F'\t' '$1=="status"&&$2=="jq_erro"{print $2}')/$([ -s "$T/e27" ] && echo stderr || echo mudo)"
printf '#!/bin/sh\nexit 3\n' > "$T/fakebin/jq"
S27="$T/scan27"; mk "$S27/pa/sa/subagents" ok "$(meta opus)" claude-sonnet-5-5; mk "$S27/pb/sb/subagents" x "$(meta opus)" claude-sonnet-5-5
chmod 000 "$S27/pb/sb/subagents"
S27M="$T/scan27m"; mk "$S27M/pa/sa/subagents" m1 "$(meta opus)" claude-sonnet-5-5
chmod 000 "$S27M/pa/sa/subagents/agent-m1.meta.json"
WANT27="2/jq_erro/stderr 2/ilegivel/stderr 2/ilegivel/stderr"
if [ "$(id -u)" -eq 0 ]; then R27="$R27 root_sem_chmod"; WANT27="2/jq_erro/stderr root_sem_chmod"
else
  E27B="$("$BASH_BIN" "$HOOK" --scan "$S27" 2>"$T/e27b")"; RC27B=$?
  R27="$R27 $RC27B/$(printf '%s\n' "$E27B" | awk -F'\t' '$1=="status"&&$2=="ilegivel"{print $2}')/$([ -s "$T/e27b" ] && echo stderr || echo mudo)"
  E27C="$("$BASH_BIN" "$HOOK" --scan "$S27M" 2>"$T/e27c")"; RC27C=$?
  R27="$R27 $RC27C/$(printf '%s\n' "$E27C" | awk -F'\t' '$1=="status"&&$2=="ilegivel"{print $2}')/$([ -s "$T/e27c" ] && echo stderr || echo mudo)"
fi
chmod 755 "$S27/pb/sb/subagents"; chmod 644 "$S27M/pa/sa/subagents/agent-m1.meta.json"
chk "27 jq so no filtro: exit 2 e jq_erro; subagents/ ilegivel e meta.json regular ilegivel: exit 2, ilegivel contado, stderr" \
  "$R27" "$WANT27"

echo "== 28. normalizacao nos dois lados: tabela pedido x efetivo =="
R28=""
t28(){ mk "$PROJ" c28 "$(meta "$1")" "$2"; run "$(payload "$PROJ/agent-c28.jsonl")"; R28="$R28 $ULT"; }
t28 'opus[1m]' claude-opus-5-5
t28 'sonnet[1m]' claude-opus-5-5
t28 claude-opus-4-6-20251101 claude-opus-4-6
t28 claude-opus-4-6 us.anthropic.claude-opus-4-6-v1:0
t28 claude-opus-4-6 global.anthropic.claude-opus-4-6-v1
t28 claude-opus-4-6 apac.anthropic.claude-opus-4-6-v1
t28 'claude-opus-4-6@20260101' 'claude-opus-4-6@20250101'
t28 claude-opus-4 claude-opus-4-6
t28 claude-opus-5-5 'claude-opus-5-5[1m]'
t28 claude-opus-5-5 Claude-Opus-5-5
t28 opus 'claude-opus-5-5[1m]'
t28 claude-opus-5-5 'claude-opus-5-5[1m][x]'
chk "28 sufixos [..], data, -vN:M e prefixos de regiao sao normalizados nos dois lados; versao diferente DIVERGE" \
  "$R28" " honrado DIVERGE honrado honrado honrado honrado honrado DIVERGE honrado honrado honrado honrado"

echo "== 29. ID longo: compara o valor completo; acima de 256 e indeterminado =="
LA="claude-opus-$(head -c 130 /dev/zero | tr '\0' a)"
LONG300="claude-opus-$(head -c 300 /dev/zero | tr '\0' b)"
R29=""
mk "$PROJ" c29a "$(meta "${LA}X")" "${LA}Y"; run "$(payload "$PROJ/agent-c29a.jsonl")"; R29="$R29 $ULT"
mk "$PROJ" c29b "$(meta "${LA}X")" "${LA}X"; run "$(payload "$PROJ/agent-c29b.jsonl")"; R29="$R29 $ULT"
mk "$PROJ" c29c "$(meta "$LONG300")" "$LONG300"; run "$(payload "$PROJ/agent-c29c.jsonl")"; R29="$R29 $ULT/$(campo .motivo)"
mk "$PROJ" c29d "$(meta "$LONG300")" claude-opus-5-5; run "$(payload "$PROJ/agent-c29d.jsonl")"; R29="$R29 $ULT/$(campo .motivo)"
mk "$PROJ" c29e "$(meta claude-opus-5-5)" "$LONG300"; run "$(payload "$PROJ/agent-c29e.jsonl")"; R29="$R29 $ULT/$(campo .motivo)"
chk "29 IDs longos que diferem so no fim DIVERGEM; iguais honram; acima de 256 em qualquer lado: indeterminado/id_longo" \
  "$R29" " DIVERGE honrado indeterminado/id_longo indeterminado/id_longo indeterminado/id_longo"

echo "== 30. sem flock registra rotacao; scan sem controle cru =="
mkdir -p "$T/noflock-bin"
for c in cat jq realpath head tail mkdir stat date dirname sort find mv tr wc sha256sum cut perl sleep rm env sed awk grep readlink touch; do
  p="$(command -v "$c" 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$T/noflock-bin/$c"
done
: > "$LOG"; env PATH="$T/noflock-bin" "$BASH_BIN" "$HOOK" <<<"$(payload "$PROJ/agent-c1.jsonl")" >/dev/null 2>&1
R30="$(campo .rotacao)"
: > "$LOG"; "$BASH_BIN" "$HOOK" <<<"$(payload "$PROJ/agent-c1.jsonl")" >/dev/null 2>&1
R30="$R30,$(campo .rotacao)"
S4="$T/scan4"
mk "$S4/p"$'\x1b'"[31mx/sa/subagents" e1 "$(meta opus)" "claude-"$'\xe2\x80\xa8'"sonnet"
# locale C: sem a troca explicita de U+2028, o [[:cntrl:]] do locale UTF-8 mascara a ausencia dela.
SC4="$(LC_ALL=C "$BASH_BIN" "$HOOK" --scan "$S4")"
R30="$R30/$(printf '%s' "$SC4" | LC_ALL=C grep -c "$(printf '\033')")/$(printf '%s' "$SC4" | LC_ALL=C grep -c "$(printf '\xe2\x80\xa8')")"
chk "30 rotacao=sem_flock sem flock e flock com flock; scan sem ESC nem U+2028 crus" "$R30" "sem_flock,flock/0/0"

echo "== 31. rotacao preserva tres geracoes =="
rm -f "$LOG" "$LOG".1 "$LOG".2 "$LOG".3
for m in A B C; do
  { printf 'MARCA-%s' "$m"; head -c 2100000 /dev/zero | tr '\0' H; printf '\n'; } > "$LOG"
  printf '%s' "$(payload "$PROJ/agent-c1.jsonl")" | "$BASH_BIN" "$HOOK" >/dev/null 2>&1
done
chk "31 tres rotacoes: .1=C .2=B .3=A" \
  "$(head -c 7 "$LOG.1" 2>/dev/null)/$(head -c 7 "$LOG.2" 2>/dev/null)/$(head -c 7 "$LOG.3" 2>/dev/null)" "MARCA-C/MARCA-B/MARCA-A"
rm -f "$LOG".1 "$LOG".2 "$LOG".3

echo "== 32. fronteiras: raiz irma, tipo do meta, transcript symlink com meta real, controle no modelo, log padrao, guarda claude-* =="
R32=""
EV="$HOME/.claude/projects-evil/proj/sess/subagents"; mk "$EV" ev "$(meta opus)" claude-sonnet-5-5
R32="$R32 $(resumo "$EV/agent-ev.jsonl" | cut -d/ -f2)"
run "$(jq -nc --arg p "$PROJ/agent-c1.jsonl" '{session_id:"s1",agent_id:"a1",agent_transcript_path:$p}')"; R32="$R32 $(campo .agent_type)"
mk "$PROJ" sl NONE claude-sonnet-5-5; rm -f "$PROJ/agent-sl.jsonl"; ln -sfn "$FORA/agent-real.jsonl" "$PROJ/agent-sl.jsonl"; meta opus > "$PROJ/agent-sl.meta.json"
R32="$R32 $(resumo "$PROJ/agent-sl.jsonl" | cut -d/ -f2)"
mk "$PROJ" ctl "$(meta opus)" "claude-sonnet-5-5"$'\001'
run "$(payload "$PROJ/agent-ctl.jsonl")"; R32="$R32 $(campo '.efetivo_model|test("[[:cntrl:]]")')"
H2="$T/h2"; mkdir -p "$H2/.claude/projects/p/s/subagents"; mk "$H2/.claude/projects/p/s/subagents" d "$(meta opus)" claude-sonnet-5-5
printf '%s' "$(payload "$H2/.claude/projects/p/s/subagents/agent-d.jsonl")" | env -u MODEL_HONOR_LOG HOME="$H2" "$BASH_BIN" "$HOOK" >/dev/null 2>&1
R32="$R32 $(wc -l < "$H2/.claude/logs/model-honor.jsonl" 2>/dev/null | tr -d ' ')"
mk "$PROJ" g32 "$(meta sonnet)" gpt-sonnet-9; run "$(payload "$PROJ/agent-g32.jsonl")"; R32="$R32 $ULT"
chk "32 raiz irma indeterminado; agent_type vem do meta; symlink do transcript indeterminado; modelo sem controle; log padrao criado; sonnet x gpt-sonnet DIVERGE" \
  "$R32" " indeterminado general-purpose indeterminado false 1 DIVERGE"

echo "== 33. eventos REAIS sanitizados (ADR 0015, regra 1) =="
FX=tests/fixtures/model-honor
R33=""
for fx in evento-tipo-preenchido evento-outra-conta evento-tipo-vazio; do
  case "$fx" in evento-outra-conta) RAIZ="$HOME/.local/share/ai-central/accounts/acc1/projects" ;; *) RAIZ="$HOME/.claude/projects" ;; esac
  PL="$(sed "s#@RAIZ@#$RAIZ#g" "$FX/$fx.json")"
  AP="$(printf '%s' "$PL" | jq -r .agent_transcript_path)"; AGID="$(printf '%s' "$PL" | jq -r .agent_id)"
  if [ "$fx" != evento-tipo-vazio ]; then mk "$(dirname "$AP")" "$AGID" "$(meta opus)" claude-sonnet-5-5; fi
  run "$PL"
  R33="$R33 $ULT/$([ "$(campo .agent_type)" = "$(jq -r .agent_type "$FX/$fx.json")" ] && echo tipo_ok)"
done
chk "33 as tres formas reais (tipo preenchido, outra conta, tipo vazio sem transcript) sao julgadas" \
  "$R33" " DIVERGE/tipo_ok DIVERGE/tipo_ok indeterminado/tipo_ok"

echo
echo "TOTAL=$((P+F)) PASS=$P FAIL=$F"
# Pino da propria contagem (convencao de scripts/status.sh): caso removido em silencio e vermelho.
EXPECTED=33
[ "$((P+F))" -eq "$EXPECTED" ] || { echo "CONTAGEM INESPERADA: executados=$((P+F)) esperado=$EXPECTED"; exit 1; }
[ "$F" -eq 0 ]
