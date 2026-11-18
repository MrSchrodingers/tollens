#!/usr/bin/env bash
# INSTALACAO MANAGED DO ROTEADOR E LIBERACAO DO OPUS (ADR 0049).
#
# Invariantes protegidos (cada violacao e uma falha de contrato ou de seguranca):
#  I1  instalar o roteador NAO altera availableModels, deniedModels nem o env de modelo, e nao
#      apaga hooks de outro repositorio nem rebaixa allowManagedHooksOnly (o gerador antigo
#      reescrevia o arquivo inteiro: com o settings vivo isso derrubava guardas ativas);
#  I2  a liberacao do Opus altera SO availableModels e deniedModels e mantem o Fable negado;
#  I3  o marketplace e o plugin entram no manifesto e a conformidade acusa adulteracao;
#  I4  reaplicar produz o mesmo estado (sem backup novo);
#  I5  o ensaio nao escreve nada;
#  I6  a reversao devolve o que a instalacao mudou e os backups sao o estado anterior;
#  I7  o manifesto cobre o diretorio do plugin;
#  I8  a politica instalada passa em validatePolicy e a reprovada nao altera o estado;
#  A1  --revert nao restaura .pre-tollens que nao seja do tollens sem --revert-forcar;
#  A2  em raiz real o motor so roda com node de root (ator nao injeta node via PATH/sudo -E).
# Raiz temporaria (MANAGED_PREFIX). Posse root:root so e medida na raiz real: NAO VERIFICADA aqui.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"
REPO="$PWD"
AM="$REPO/install/apply-managed.sh"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }
command -v jq >/dev/null 2>&1 || { echo "NAO VERIFICADO: jq ausente." >&2; exit 2; }
command -v node >/dev/null 2>&1 || { echo "NAO VERIFICADO: node ausente." >&2; exit 2; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export EVIDENCE_LEDGER_DIR="$T/ledger"

PFX="$T/raiz"
OPT="$PFX/opt/tollens"
ETC="$PFX/etc/claude-code"
S="$ETC/managed-settings.json"
POL="$ETC/router-policy.json"
EXT="$PFX/opt/claude-harness/hooks/secret-guard.sh"

# Estado "vivo": arquivo marcado, com modelos, env de modelo e guardas de outro repositorio. O layout
# dos grupos reproduz o managed vivo de 2026-11-18: quality-gate NO MESMO grupo de verify-gate e
# ds4-notify (Stop), budget-count no mesmo grupo de subagent-probe e activation-log (SubagentStart).
# Uma implementacao que filtrasse "por grupo" perderia essas guardas.
mkdir -p "$ETC" "$OPT/hooks" "$(dirname "$EXT")"
for h in budget-guard budget-count quality-gate; do
  printf '#!/bin/sh\n' > "$OPT/hooks/$h.sh"; chmod 0755 "$OPT/hooks/$h.sh"
done
printf '#!/bin/sh\n' > "$EXT"; chmod 0755 "$EXT"
jq -n --arg o "$OPT" --arg e "$EXT" '
  def h($n): {type:"command", command:("bash " + $o + "/hooks/" + $n + ".sh")};
  {_managed_by:"tollens", allowManagedHooksOnly:true,
   availableModels:["sonnet","haiku"], deniedModels:["opus","fable","claude-opus-5","claude-fable-5"],
   hooks:{
     PreToolUse:[{matcher:"Agent|Task|Workflow", hooks:[h("budget-guard")]},
                 {matcher:"Read|Bash", hooks:[{type:"command", command:("bash " + $e)}]}],
     Stop:[{hooks:[h("verify-gate"), h("quality-gate"), h("ds4-notify")]}],
     SubagentStart:[{hooks:[h("subagent-probe"), h("budget-count"), h("activation-log")]}]},
   env:{CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL:"haiku"}}' > "$S"
cp -p "$S" "$T/vivo.json"
modelos(){ jq -S -c '{a:.availableModels,d:.deniedModels,w:.env.CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL}' "$1"; }
estado(){ ( cd "$PFX" && find . -type f -not -name '*.pre-*' -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64 ); }
snap(){ ( cd "$PFX" && find . -printf '%p %y %s %m %T@\n' | sort | sha256sum | cut -c1-64 ); }
run(){ MANAGED_PREFIX="$PFX" bash "$AM" "$@" >"$T/out" 2>&1; echo $?; }

echo "== R1. ensaio nao escreve (I5) e mostra o diff"
a="$(snap)"; rc="$(run --dry-run)"; b="$(snap)"
chk "I5 dry-run: rc 0 e nada escrito" "$rc/$([ "$b" = "$a" ] && echo igual)" "0/igual"
chk "I5 dry-run mostra o diff do settings" "$(grep -c '^+++ novo:.*managed-settings.json' "$T/out")" 1
a="$(snap)"; rc="$(run --liberar-opus --dry-run)"; b="$(snap)"
chk "I5 liberar-opus --dry-run: rc 0 e nada escrito" "$rc/$([ "$b" = "$a" ] && echo igual)" "0/igual"

echo "== R2. instalacao em shadow preserva modelos e guardas externas (I1)"
rc="$(run)"
chk "I1 deploy rc 0 e availableModels/deniedModels/env de modelo intactos" "$rc/$(modelos "$S")" "0/$(modelos "$T/vivo.json")"
chk "I1 allowManagedHooksOnly nao rebaixado" "$(jq -r .allowManagedHooksOnly "$S")" true
chk "I1 todo comando do vivo segue registrado (inclui o externo fora de \$OPT)" \
  "$(jq -n --slurpfile a "$T/vivo.json" --slurpfile b "$S" '[$a[0]|..|.command? // empty] - [$b[0]|..|.command? // empty] | length')" 0
chk "I1 quality-gate segue no Stop, budget-count no SubagentStart, e os 3 arquivos vao para a arvore nova" \
  "$(jq -r '([.hooks.Stop[].hooks[].command]|map(select(endswith("quality-gate.sh")))|length)|tostring' "$S")/$(jq -r '([.hooks.SubagentStart[].hooks[].command]|map(select(endswith("budget-count.sh")))|length)|tostring' "$S")/$(find "$OPT/hooks" \( -name budget-guard.sh -o -name budget-count.sh -o -name quality-gate.sh \) -perm 0755 | wc -l | tr -d ' ')" "1/1/3"

echo "== R3. chaves de mod da organizacao e hooks do roteador"
chk "enabledPlugins" "$(jq -c .enabledPlugins "$S")" '{"tollens-router@tollens-tools":true}'
chk "prependPlugins mantem sec-default" "$(jq -c .prependPlugins "$S")" '["tollens-router@tollens-tools","sec-default@builtin"]'
chk "marketplace aponta o diretorio do plugin" "$(jq -r '.extraKnownMarketplaces["tollens-tools"].source|.source+":"+.path' "$S")" "directory:$OPT/claude-plugins"
MK="$OPT/claude-plugins/.claude-plugin/marketplace.json"
chk "marketplace.json: nome e fonte relativa" \
  "$(jq -r '.name+"|"+(.plugins[]|select(.name=="tollens-router")|.source)' "$MK")" "tollens-tools|./plugins/tollens-router"
chk "model-honor em SubagentStop e pending-ask em Stop" "$(jq -r '([.hooks.SubagentStop[].hooks[].command]|map(select(endswith("model-honor.sh")))|length|tostring)+"/"+([.hooks.Stop[].hooks[].command]|map(select(endswith("pending-ask.sh")))|length|tostring)' "$S")" 1/1

echo "== R4. politica instalada (I8)"
chk "politica instalada em modo shadow" "$(jq -r .mode "$POL")" shadow
V='const [, pol, eng, agora] = process.argv; const fs = await import("node:fs"); const { validatePolicy } = await import(eng);
const r = validatePolicy(JSON.parse(fs.readFileSync(pol, "utf8")), { now: Date.parse(agora) });
console.log(r.ok ? (r.degradaPara || "ok") : "invalida");'
ENG="file://$OPT/claude-plugins/plugins/tollens-router/engine.mjs"
chk "I8 validatePolicy ok com now=2026-11-18" "$(node --input-type=module -e "$V" "$POL" "$ENG" 2026-11-18T00:00:00Z 2>&1)" ok
chk "I8 politica vencida (2026-12-01) e aceita mas degradada" "$(node --input-type=module -e "$V" "$POL" "$ENG" 2026-12-01T00:00:00Z 2>&1)" shadow
jq '.mode="enforce"' "$POL" > "$T/pol.enf" && cp "$T/pol.enf" "$POL"
rc="$(run)"
chk "reaplicar preserva o mode escolhido pelo operador" "$rc/$(jq -r .mode "$POL")" "0/enforce"
jq '.mode="shadow"' "$POL" > "$T/pol.sh" && cp "$T/pol.sh" "$POL"

echo "== R5. modos de arquivo e conformidade (I3)"
chk "I3 plugin: arquivos 0644, diretorios 0755, nada gravavel por grupo/outros" "$(find "$OPT/claude-plugins" \( -perm /022 -o -type f \! -perm 0644 -o -type d \! -perm 0755 \) | wc -l | tr -d ' ')" 0
rc="$(run --verify)"
chk "verify conforme apos instalar" "$rc" 0
E="$OPT/claude-plugins/plugins/tollens-router/engine.mjs"
cp -p "$E" "$T/engine.bak"; printf '\n// adulterado\n' >> "$E"
rc="$(run --verify)"
chk "I3 verify acusa plugin adulterado" "$rc/$(grep -c 'DIVERGE.*claude-plugins' "$T/out")" "1/1"
cp -p "$T/engine.bak" "$E"
rm -f "$MK"
rc="$(run --verify)"
chk "I3 verify acusa marketplace removido" "$rc" 1
run >/dev/null

echo "== R6. idempotencia (I4)"
a="$(estado)"; sa="$(jq -S -c . "$S")"; nb="$(ls "$ETC" | grep -c 'pre-roteador')"
rc="$(run)"
chk "I4 arvore identica (rc 0)" "$rc/$(estado)" "0/$a"
chk "I4 settings identico" "$(jq -S -c . "$S")" "$sa"
chk "I4 sem backup novo" "$(ls "$ETC" | grep -c 'pre-roteador')" "$nb"

echo "== R7. liberacao do Opus (I2)"
cp -p "$S" "$T/antes-opus.json"
rc="$(run --liberar-opus)"
chk "B liberar-opus rc" "$rc" 0
chk "I2 so availableModels/deniedModels mudaram" "$(jq -S -c 'del(.availableModels,.deniedModels)' "$S")" "$(jq -S -c 'del(.availableModels,.deniedModels)' "$T/antes-opus.json")"
chk "I2 Opus 5.5 permitido e opus fora de deniedModels" "$(jq -r '((.availableModels|index("claude-opus-5-5")!=null)|tostring)+"/"+((.deniedModels|map(test("opus"))|any)|tostring)' "$S")" "true/false"
chk "I2 Fable segue negado e fora de availableModels" "$(jq -r '((.deniedModels|index("fable")!=null) and (.deniedModels|index("claude-fable-5")!=null) and ((.availableModels|map(test("fable"))|any)|not))|tostring' "$S")" true
chk "I2 backup e o estado anterior" "$(cmp -s "$T/antes-opus.json" "$(ls "$ETC"/managed-settings.json.pre-liberar-opus.* | head -1)" && echo igual)" igual
a="$(snap)"; rc="$(run --liberar-opus)"
chk "I2 liberar de novo e no-op" "$rc/$([ "$(snap)" = "$a" ] && echo igual)" "0/igual"
printf '{"availableModels":["sonnet"]}\n' > "$T/terceiro.json"; cp -p "$S" "$T/marcado.json"; cp "$T/terceiro.json" "$S"
rc="$(run --liberar-opus)"
chk "I2 recusa settings sem a marca tollens (inalterado)" "$rc/$(cmp -s "$T/terceiro.json" "$S" && echo igual)" "1/igual"
cp -p "$T/marcado.json" "$S"

echo "== R8. reversao do roteador (I6)"
cp -p "$S" "$T/pre-rr.json"
rc="$(run --revert-router)"
chk "I6 revert-router: rc 0, plugin e politica removidos" "$rc/$([ -e "$OPT/claude-plugins" ] || [ -e "$POL" ] && echo resta || echo removidos)" "0/removidos"
chk "I6 chaves de plugin removidas" "$(jq -r '[has("enabledPlugins"),has("extraKnownMarketplaces"),has("prependPlugins")]|any|tostring' "$S")" false
chk "I6 tudo fora das 3 chaves de plugin permanece identico (conteudo, nao so chaves)" "$(jq -S -c 'del(.enabledPlugins,.extraKnownMarketplaces,.prependPlugins)' "$S")" "$(jq -S -c 'del(.enabledPlugins,.extraKnownMarketplaces,.prependPlugins)' "$T/pre-rr.json")"
BK="$(ls "$ETC"/managed-settings.json.pre-roteador.* | head -1)"
chk "I6 backup pre-roteador e o arquivo vivo original" "$(cmp -s "$T/vivo.json" "$BK" && echo igual)" igual

echo "== R9. manifesto (I7) e escopo de usuario"
L="$(awk -F'\t' '$1=="plugin"' install/manifest.lock)"
chk "I7 manifesto tem a linha plugin" "$(printf '%s' "$L" | cut -f2,3 | tr '\t' '>')" "claude-plugins>claude-plugins"
chk "I7 digest do manifesto = digest da arvore" "$(printf '%s' "$L" | cut -f4)" \
  "$(cd claude-plugins && find . -type f -exec sha256sum {} + | LC_ALL=C sort -k2 | sha256sum | cut -c1-64)"
chk "apply.sh de usuario nao planeja o plugin" "$(CLAUDE_HOME="$T/home" bash install/apply.sh --dry-run 2>&1 | grep -c 'claude-plugins')" 0
rc="$(MANAGED_PREFIX="$PFX" bash "$AM" --liberar-opus --revert >/dev/null 2>&1; echo $?)"
chk "supervisor recusa par de argumentos nao previsto" "$rc" 2

echo "== R10. --revert recusa .pre-tollens que nao e do tollens (A1)"
# O .pre-tollens vivo e de 2026-08-12 (_managed_by evidence-gate, hooks em caminho inexistente). Reverter
# para ele troca a politica atual por uma antiga, sem guardas e sem modelos negados, e apaga /opt/tollens.
cont(){ ( cd "$1" && find . -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64 ); }
runp(){ local p="$1"; shift; MANAGED_PREFIX="$p" bash "$AM" "$@" >"$T/out" 2>&1; echo $?; }
PA="$T/raizA"; runp "$PA" >/dev/null
printf '{"_managed_by":"evidence-gate","hooks":{}}\n' > "$PA/etc/claude-code/managed-settings.json.pre-tollens"
a="$(cont "$PA")"; rc="$(runp "$PA" --revert)"
chk "A1 --revert recusa .pre-tollens sem a marca tollens: rc 1 e nada removido" "$rc/$([ "$(cont "$PA")" = "$a" ] && echo igual)" "1/igual"
rc="$(runp "$PA" --revert-forcar)"
chk "A1 --revert-forcar restaura mesmo assim" "$rc/$(jq -r ._managed_by "$PA/etc/claude-code/managed-settings.json")/$([ -e "$PA/opt/tollens" ] && echo resta || echo removido)" "0/evidence-gate/removido"
PB="$T/raizB"; runp "$PB" >/dev/null
printf '{"_managed_by":"tollens","hooks":{}}\n' > "$PB/etc/claude-code/managed-settings.json.pre-tollens"
chk "A1 controle: .pre-tollens do proprio tollens segue revertendo sem flag" "$(runp "$PB" --revert)" 0

echo "== R11. o motor so roda com node de root em raiz real (A2)"
# Sob sudo o motor roda como root: um node do ator (nvm, PATH herdado) seria execucao de codigo do ator
# como root. A checagem vale em raiz real e, nos ensaios, quando MANAGED_NODE_ROOT=1 (so endurece).
mkdir -p "$T/fakebin" "$T/semnode"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$(command -v node)" > "$T/fakebin/node"; chmod 0755 "$T/fakebin/node"
PC="$T/raizC"; mkdir -p "$PC"
rc="$(PATH="$T/fakebin:$PATH" MANAGED_NODE_ROOT=1 MANAGED_PREFIX="$PC" bash "$AM" >"$T/out" 2>&1; echo $?)"
chk "A2 node que nao e de root: rc 1 e nada instalado" "$rc/$([ -e "$PC/etc/claude-code/managed-settings.json" ] || [ -e "$PC/opt/tollens" ] && echo instalou || echo nada)" "1/nada"
PD0="$T/raizC2"; mkdir -p "$PD0"
rc="$(PATH="$T/fakebin:$PATH" MANAGED_PREFIX="$PD0" bash "$AM" >"$T/out" 2>&1; echo $?)"
chk "A2 controle: o mesmo node, sem a exigencia (ensaio), instala" "$rc" 0
sed -n '/^node_raiz(){/,/^}/p' install/apply-managed-worker.sh > "$T/node_raiz.sh"
. "$T/node_raiz.sh"
chk "A2 node_raiz: executavel de root em caminho de root passa; do ator e recusado" "$(node_raiz /usr/bin/bash 2>/dev/null; echo $?)/$(node_raiz "$T/fakebin/node" 2>/dev/null; echo $?)" "0/1"
ls /usr/bin | grep -vx node | sed 's|^|/usr/bin/|' | xargs ln -s -t "$T/semnode" 2>/dev/null
PE0="$T/raizC3"; mkdir -p "$PE0"
rc="$(PATH="$T/semnode" MANAGED_PREFIX="$PE0" bash "$AM" >"$T/out" 2>&1; echo $?)"
chk "A2 node ausente do PATH: rc 1 e nada instalado" "$rc/$([ -e "$PE0/etc/claude-code/managed-settings.json" ] && echo instalou || echo nada)" "1/nada"

echo "== R12. liberacao do Opus por token, com corpus adversarial (I2)"
PD="$T/raizD"; mkdir -p "$PD/etc/claude-code"
jq -n '{_managed_by:"tollens", availableModels:["sonnet"],
        deniedModels:["opus","claude-opus-4-1","opus[1m]","claude-3-opus-20240229","opusplan","claude-fable-opus","fable","claude-fable-5","claude-fable-5-1m"]}' > "$PD/etc/claude-code/managed-settings.json"
rc="$(runp "$PD" --liberar-opus)"
chk "I2 tira so entradas com token opus; fable e entrada mista com fable permanecem negados" "$rc/$(jq -c .deniedModels "$PD/etc/claude-code/managed-settings.json")" '0/["opusplan","claude-fable-opus","fable","claude-fable-5","claude-fable-5-1m"]'

echo "== R13. politica do roteador reprovada deixa o estado intocado (I8)"
PF="$T/raizF"; runp "$PF" >/dev/null
printf '{}\n' > "$T/pol-invalida.json"
a="$(cont "$PF")"
rc="$(MANAGED_ROUTER_POLICY_SRC="$T/pol-invalida.json" MANAGED_PREFIX="$PF" bash "$AM" >"$T/out" 2>&1; echo $?)"
chk "I8 politica reprovada em validatePolicy: rc != 0 e nada mudou" "$([ "$rc" -ne 0 ] && echo falhou)/$([ "$(cont "$PF")" = "$a" ] && echo igual)" "falhou/igual"
rc="$(MANAGED_ROUTER_POLICY_SRC="$REPO/claude-plugins/plugins/tollens-router/router-policy.json" MANAGED_PREFIX="$PF" bash "$AM" >"$T/out" 2>&1; echo $?)"
chk "I8 controle: a politica valida pelo mesmo caminho de override passa" "$rc" 0

echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=48
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "instalacao do roteador verde ($P/$EXPECTED)" || echo "instalacao do roteador VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
