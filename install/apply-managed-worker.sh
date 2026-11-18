#!/usr/bin/env bash
# RAIZ DE CONFIANCA - fase 2. Instala a politica FORA do espaco de escrita do ator governado.
#
# O PROBLEMA QUE ISTO RESOLVE. Ate aqui, `install/apply.sh` grava em `~/.claude`, que o ator
# governado escreve. Isso detecta drift ACIDENTAL e nada mais: contra intencao, o ator apaga o
# hook, edita o `settings.json`, ou muda `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`. Parametro de
# politica dentro do espaco de escrita do governado nao e politica (ADR 0022).
#
# O QUE PRECISA SER ROOT-OWNED, e por que nao basta o hook. Verificado no codigo:
#   hooks (14)      - a politica em si;
#   adapters (11)   - `verify-gate.sh` le a tabela em `$CLAUDE_ADAPTERS_DIR`. Se ela for
#                     gravavel pelo ator, ele desliga o gate esvaziando o diretorio (o proprio
#                     G5 mostra que tabela vazia e fail-closed, mas um adaptador ADULTERADO
#                     passaria); e `doctool.sh` le `$DOC_ADAPTERS_DIR`;
#   doctools (5)    - `read-budget.sh` os executa.
# Politica root-owned lendo tabela user-owned e raiz de confianca so no nome.
#
# O QUE NAO E COBERTO, declarado: agentes (10) e skills (9) seguem em `~/.claude`. Nao sao
# politica - sao capacidade. O ator pode edita-los; o que ele NAO pode e desativar o hook que
# cobra o contrato de retorno deles.
#
# ARMADILHA CENTRAL, confirmada na documentacao primaria antes de qualquer escrita:
#   "allowManagedHooksOnly | (Managed settings only) Only managed hooks, SDK hooks, and hooks
#    from plugins force-enabled in managed settings `enabledPlugins` are loaded. User, project,
#    and all other plugin hooks are blocked."
# Ou seja, ativar isso ANTES de os 14 hooks existirem no escopo managed derruba o mecanismo
# inteiro. Por isso o deploy e a ativacao sao PASSOS SEPARADOS, e `--enforce` recusa rodar se a
# conformidade do escopo managed nao passar.
#
# TESTABILIDADE: `MANAGED_PREFIX` desloca a raiz (default `/`). Toda a logica - copia, digest,
# geracao do JSON, verificacao, reversao - roda sem privilegio contra um prefixo temporario, e
# e isso que `tests/unit/managed.sh` exercita. Com prefixo `/` exige root, e so ai a posse por
# root e verificada.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
# MANAGED_MANIFEST e override SO PARA TESTE: `tests/unit/managed.sh` precisa exercitar o caso
# "deploy incompleto" sem mutar o manifesto real - se a suite morresse no meio, o repositorio
# ficaria com o manifesto sabotado no disco.
MAN="${MANAGED_MANIFEST:-install/manifest.lock}"
PREFIX="${MANAGED_PREFIX:-/}"
PREFIX="${PREFIX%/}"                 # normaliza: "/" vira "", evitando "//etc"
# CANONICALIZA o prefixo: sem isto, `MANAGED_PREFIX=/tmp/x/opt/..` faz $OPT conter `..` e a
# checagem de confinamento abaixo comparara prefixos textuais que nao correspondem ao caminho
# real. `realpath -m` resolve sem exigir que o caminho exista.
if [ -n "$PREFIX" ]; then
  PREFIX="$(realpath -m "$PREFIX" 2>/dev/null || printf '%s' "$PREFIX")"
  PREFIX="${PREFIX%/}"
fi
OPT="$PREFIX/opt/tollens"
# RAIZ e a arvore que as funcoes de validacao INSPECIONAM. Em `--verify` e a arvore ativa; no
# deploy passa a ser a area de staging, e so vira a ativa depois de todo portao ter passado.
# Sem esta indirecao, validar antes de publicar seria impossivel sem duplicar as funcoes.
RAIZ="$OPT"
ETC="$PREFIX/etc/claude-code"
SETTINGS="$ETC/managed-settings.json"
REAL=0; [ -z "$PREFIX" ] && REAL=1   # prefixo vazio = raiz de verdade

MODO="deploy"
# ONDA 12. Este `case` inspeciona apenas "$1", e o worker e invocavel DIRETO (documentado, e via
# TOLLENS_MANAGED_WORKER). Medido: `apply-managed.sh --revert --dry-run` chegava aqui com argc=2 e
# executava um revert REAL e privilegiado, descartando o `--dry-run` em silencio - justamente o
# habito de seguranca do operador sendo engolido no unico caminho que roda como root. O supervisor
# passou a contar antes do `exec`; aqui a checagem se repete porque o worker tem entrada propria.
#
# ONDA 34 (ADR 0049). Unico par aceito com dois argumentos: `--liberar-opus --dry-run`, tratado
# por igualdade exata. Qualquer outro excesso segue recusado.
OPUS_DRY=0
REVERT_FORCAR=0
if [ "$#" -eq 2 ] && [ "$1" = "--liberar-opus" ] && [ "$2" = "--dry-run" ]; then
  OPUS_DRY=1; set -- --liberar-opus
fi
[ "$#" -le 1 ] || { echo "ERRO: argumentos em excesso ($#): $*" >&2; exit 64; }
case "${1:-}" in
  --dry-run) MODO="dry" ;;
  --enforce) MODO="enforce" ;;
  --revert)  MODO="revert" ;;
  --revert-forcar) MODO="revert"; REVERT_FORCAR=1 ;;
  --verify)  MODO="verify" ;;
  --liberar-opus)  MODO="opus" ;;
  --revert-router) MODO="revert-router" ;;
  "")        MODO="deploy" ;;
  *) echo "uso: $0 [--dry-run|--enforce|--revert|--revert-forcar|--verify|--liberar-opus [--dry-run]|--revert-router]" >&2; exit 64 ;;
esac

if [ "$REAL" -eq 1 ] && [ "$MODO" != "dry" ] && [ "$MODO" != "verify" ] && [ "$OPUS_DRY" -eq 0 ] && [ "$(id -u)" -ne 0 ]; then
  echo "ERRO: '$MODO' sobre a raiz real exige root. Rode com sudo, ou use MANAGED_PREFIX=<dir> para ensaiar." >&2
  exit 77
fi
[ -f "$MAN" ] || { echo "ERRO: $MAN ausente - rode install/manifest.sh" >&2; exit 1; }

# destino de cada componente dentro de $OPT. `hooks/x.sh` fica `hooks/x.sh`; os demais vem com
# o prefixo `tollens/` do layout de ~/.claude, que aqui e redundante e sai.
destino_managed(){ printf '%s\n' "${1#tollens/}"; }

# tipos que compoem a POLITICA. agent e skill ficam de fora por decisao declarada no cabecalho.
# `lib` entrou na onda 25: a POLITICA precisa das bibliotecas que seus hooks chamam. Sem isso o
# `verify-gate.sh` chegava a /opt/tollens sem o `lint-delta.py` que o ramo `delta` invoca, e
# declarava lacuna a cada parada - portao instalado que nao verifica nada.
tipos_politica(){ awk -F'\t' '!/^#/ && ($1=="hook" || $1=="adapter" || $1=="doctool" || $1=="lib" || $1=="plugin")' "$MAN"; }

# ONDA 34 (ADR 0049): marketplace do roteador. Os tres nomes abaixo precisam coincidir com
# claude-plugins/.claude-plugin/marketplace.json e plugins/tollens-router/.claude-plugin/plugin.json.
ROUTER_MARKET="tollens-tools"
ROUTER_ID="tollens-router@$ROUTER_MARKET"
ROUTER_POLICY_SRC="claude-plugins/plugins/tollens-router/router-policy.json"
# Override SO PARA TESTE (tests/unit/managed-router.sh: politica reprovada). Ignorado em raiz real:
# la a fonte da politica e a do repositorio ja validado como root:root (ADR 0026).
[ "$REAL" -eq 0 ] && ROUTER_POLICY_SRC="${MANAGED_ROUTER_POLICY_SRC:-$ROUTER_POLICY_SRC}"
ROUTER_POLICY="$ETC/router-policy.json"
# Liberacao do Opus: ID da versao 5.5 (um prefixo de versao permite a versao nomeada e as que a
# estendem). Os tokens negados removidos de deniedModels sao os que casam `opus`.
OPUS_ID="claude-opus-5-5"

# ===================== CONFINAMENTO DE CAMINHO (auditoria de 2026-08-04) =====================
# DEFEITO CRITICO CORRIGIDO, com PoC executada. O manifesto e um ARQUIVO DO REPOSITORIO, isto e,
# esta dentro do espaco de escrita do ator governado. Suas colunas `origem` e `destino` eram
# usadas VERBATIM como caminho de `mkdir -p`, `cp -f` e `rm -rf`, e este script roda como ROOT.
# Medido, com prefixo temporario:
#
#   destino = ../../../ZONA_PROIBIDA/vitima.conf   -> arquivo FORA do prefixo sobrescrito
#   destino = ../../../ZONA_PROIBIDA  (origem=dir) -> `rm -rf` destruiu o diretorio FORA do prefixo
#
# Sob `sudo`, isso e escrita e remocao arbitrarias como root a partir de dado que o ator
# controla: `/etc/cron.d/`, `/etc/sudoers.d/`, `~/.ssh/authorized_keys`. A raiz de confianca
# seria instalada a partir de entrada nao confiavel - a inversao exata da tese deste projeto.
#
# O DIGEST NAO PROTEGE. `install/manifest.sh` calcula o sha256 do MESMO working tree que
# deveria proteger, e o loop de deploy descartava a coluna. A conformidade compara o arquivo
# copiado com o valor que o proprio atacante escreveu. E detector de drift contra `~/.claude`,
# nunca controle de integridade sobre o repositorio - e essa distincao passou despercebida ate
# a auditoria.
#
# A regra e REJEITAR A LINHA E ABORTAR, nunca sanear: sanear um caminho hostil deixa a duvida
# sobre o que sobrou, e num contexto root a duvida nao e aceitavel.
confinado(){ # $1=caminho candidato  $2=raiz que deve conte-lo -> 0 se dentro
  local c r
  c="$(realpath -m "$1" 2>/dev/null)" || return 1
  r="$(realpath -m "$2" 2>/dev/null)" || return 1
  case "$c" in "$r"|"$r"/*) return 0 ;; *) return 1 ;; esac
}

valida_manifesto(){ # ecoa violacoes; retorna != 0 se houver qualquer uma
  local ruins=0 tipo origem destino _sha
  while IFS=$'\t' read -r tipo origem destino _sha; do
    # 1. forma. Rejeita absoluto e qualquer componente `..` ANTES de tocar no filesystem.
    case "$destino" in
      ""|/*|../*|*/../*|*/..|"..") echo "  DESTINO INVALIDO: [$destino]"; ruins=$((ruins+1)); continue ;;
    esac
    case "$origem" in
      ""|/*|../*|*/../*|*/..|"..") echo "  ORIGEM INVALIDA: [$origem]"; ruins=$((ruins+1)); continue ;;
    esac
    # 2. confinamento efetivo. A checagem de forma sozinha nao cobre symlink no meio do
    #    caminho; `realpath -m` resolve e a comparacao e sobre o caminho REAL.
    confinado "$RAIZ/$(destino_managed "$destino")" "$RAIZ" \
      || { echo "  DESTINO ESCAPA DE $RAIZ: [$destino]"; ruins=$((ruins+1)); continue; }
    confinado "$REPO/$origem" "$REPO" \
      || { echo "  ORIGEM ESCAPA DE $REPO: [$origem]"; ruins=$((ruins+1)); continue; }
    [ -e "$REPO/$origem" ] || { echo "  ORIGEM INEXISTENTE: [$origem]"; ruins=$((ruins+1)); }
  done < <(tipos_politica)
  [ "$ruins" -eq 0 ]
}
# =============================================================================================

plano(){
  tipos_politica | while IFS=$'\t' read -r tipo origem destino _sha; do
    printf '  %-8s %s -> %s/%s\n' "$tipo" "$origem" "$OPT" "$(destino_managed "$destino")"
  done
}

# ===================== ONDA 34: ROTEADOR E LIBERACAO DO OPUS (ADR 0049) =====================
# O managed-settings.json vivo foi editado a mao (availableModels, deniedModels, hooks de outro
# repositorio). O gerador antigo reescrevia o arquivo inteiro e apagava tudo isso. Daqui em diante,
# sobre um arquivo JA marcado `_managed_by: tollens`, o gerador PRESERVA toda chave que nao e dele
# e os hooks que a especificacao nao declara. Sobre arquivo de terceiro o comportamento antigo
# vale (backup .pre-tollens e substituicao).
atual_e_tollens(){ [ -f "$SETTINGS" ] && jq -e '._managed_by == "tollens"' "$SETTINGS" >/dev/null 2>&1; }

# grupos de hook do arquivo atual cujos comandos a especificacao nova NAO declara. $1 = hooks novos.
hooks_externos(){
  atual_e_tollens || { echo '{}'; return 0; }
  jq -c --argjson novo "$1" '
    ([$novo | .. | objects | select(has("command")) | .command] | unique) as $conhecidos
    | (.hooks // {})
    | with_entries(.value |= [ .[] | .hooks |= map(select((.command // null) as $c | ($conhecidos | index($c)) | not))
                               | select((.hooks | length) > 0) ])
    | with_entries(select(.value | length > 0))' "$SETTINGS"
}
junta_hooks(){ jq -nc --argjson a "$1" --argjson b "$2" 'reduce ($b | to_entries[]) as $e ($a; .[$e.key] = ((.[$e.key] // []) + $e.value))'; }

# $1 = hooks (spec + externos), $2 = true|false (enforce solicitado). O enforce ja ativo NAO e rebaixado.
gera_settings(){
  local base='{}'
  atual_e_tollens && base="$(cat "$SETTINGS")"
  jq -n --argjson b "$base" --argjson h "$1" --argjson enf "$2" --arg rp "$REPO" \
        --arg ad "$OPT/adapters/code" --arg dd "$OPT/adapters/documents" \
        --arg pid "$ROUTER_ID" --arg mk "$ROUTER_MARKET" --arg mp "$OPT/claude-plugins" '
    ($b | del(.hooks, .allowManagedHooksOnly)) as $r
    | $r + {_managed_by: "tollens",
            allowManagedHooksOnly: ($enf or ($b.allowManagedHooksOnly == true)),
            hooks: $h,
            env: (($r["env"] // {}) + {CLAUDE_ADAPTERS_DIR: $ad, DOC_ADAPTERS_DIR: $dd, TOLLENS_REPO: $rp}),
            enabledPlugins: (($r.enabledPlugins // {}) + {($pid): true}),
            extraKnownMarketplaces: (($r.extraKnownMarketplaces // {}) + {($mk): {source: {source: "directory", path: $mp}}}),
            prependPlugins: ([$pid, "sec-default@builtin"] + ($b.prependPlugins // [])
                             | reduce .[] as $x ([]; if index($x) then . else . + [$x] end))}'
}

# Politica do roteador: conteudo embarcado, mantendo o `mode` ja instalado (o operador o muda no passo D).
politica_json(){
  local m=""
  [ -f "$ROUTER_POLICY" ] && m="$(jq -r '.mode // empty' "$ROUTER_POLICY" 2>/dev/null)"
  case "$m" in
    shadow|enforce|off) jq -S --arg m "$m" '.mode = $m' "$ROUTER_POLICY_SRC" ;;
    *) jq -S . "$ROUTER_POLICY_SRC" ;;
  esac
}

# Em raiz real o motor roda COMO ROOT. Um `node` do ator (nvm, PATH herdado por `sudo env PATH=$PATH` ou
# `sudo -E`) seria execucao de codigo do ator como root. $1 = caminho do executavel. Exige o binario
# resolvido (realpath) e todo diretorio ate `/` pertencentes a root e sem escrita de grupo/outros.
node_raiz(){
  local d own mode
  d="$(realpath -e "$1" 2>/dev/null)" || return 1
  while :; do
    read -r own mode < <(stat -c '%U %a' "$d" 2>/dev/null) || return 1
    if [ "$own" != "root" ] || [ $(( 8#$mode & 8#022 )) -ne 0 ]; then
      echo "ERRO: '$d' (dono=$own, modo=$mode) esta no caminho do node ($1), e ele nao e de root ou e gravavel por outros." >&2
      echo "      Em raiz real o motor roda como root e exige um node root-owned em caminho de sistema, instalado" >&2
      echo "      pelo operador (pacote da distribuicao). Nao use 'sudo -E' nem 'sudo env PATH=\$PATH'." >&2
      return 1
    fi
    [ "$d" = "/" ] && break
    d="$(dirname "$d")"
  done
}

# validatePolicy do motor, com `now`. $1 = arquivo de politica, $2 = engine.mjs. Exit 0 so com ok:true.
valida_politica(){
  command -v node >/dev/null 2>&1 || { echo "ERRO: node ausente - a politica do roteador nao pode ser validada." >&2; return 1; }
  # MANAGED_NODE_ROOT=1 so ENDURECE (permite ensaiar a recusa sob prefixo); nunca afrouxa a raiz real.
  if [ "$REAL" -eq 1 ] || [ "${MANAGED_NODE_ROOT:-}" = "1" ]; then
    node_raiz "$(command -v node)" || return 1
  fi
  node --input-type=module -e '
    const [, pol, eng] = process.argv;
    const fs = await import("node:fs");
    const { validatePolicy } = await import(eng);
    const r = validatePolicy(JSON.parse(fs.readFileSync(pol, "utf8")), { now: Date.now() });
    if (!r.ok) { console.error(JSON.stringify(r.erros)); process.exit(1); }
    if (r.degradaPara) console.error("AVISO: politica degrada para " + r.degradaPara + " (vencida ou enforce sem tier medido)");
  ' "$1" "file://$2"
}

# settings com o Opus liberado: so availableModels e deniedModels mudam.
opus_json(){
  jq --arg id "$OPUS_ID" '
    def tokens: ascii_downcase | [scan("[a-z]+")];
    # entrada com token `fable` NUNCA sai, mesmo se tambem tiver `opus` (Fable segue negado, ADR 0012)
    def tem_opus: tokens | (index("opus") != null) and (index("fable") == null);
    (if has("availableModels") then .availableModels |= (if index($id) then . else . + [$id] end) else . end)
    | (if has("deniedModels") then .deniedModels |= map(select(type != "string" or (tem_opus | not))) else . end)' "$SETTINGS"
}

mostra_diff(){ # $1=rotulo $2=JSON atual (ou {}) $3=JSON novo
  local d
  d="$(diff -u --label "atual:$1" --label "novo:$1" <(printf '%s\n' "$2") <(printf '%s\n' "$3") || true)"
  if [ -n "$d" ]; then printf '%s\n' "$d"; else echo "  (sem mudanca em $1)"; fi
}

dry_diff(){ # nunca escreve: so le, e compara em memoria (process substitution usa pipe)
  local sp ext hj novo atual polnova polatual
  sp="$(bash install/hooks-spec.sh "$OPT/hooks")" || return 1
  ext="$(hooks_externos "$sp")" || return 1
  hj="$(junta_hooks "$sp" "$ext")" || return 1
  echo "--- componentes de politica em $OPT"
  while IFS=$'\t' read -r _t origem destino sha; do
    alvo="$OPT/$(destino_managed "$destino")"
    if [ ! -e "$alvo" ]; then printf '  INSTALA   %s\n' "$(destino_managed "$destino")"; continue; fi
    if [ -d "$alvo" ]; then cur="$(cd "$alvo" && find . -type f -exec sha256sum {} + | LC_ALL=C sort -k2 | sha256sum | cut -d' ' -f1)"
    else cur="$(sha256sum "$alvo" | cut -d' ' -f1)"; fi
    if [ "$cur" = "$sha" ]; then printf '  igual     %s\n' "$(destino_managed "$destino")"
    else printf '  ATUALIZA  %s\n' "$(destino_managed "$destino")"; fi
  done < <(tipos_politica)
  echo "--- hooks externos preservados (comandos que a especificacao nao declara)"
  printf '%s' "$ext" | jq -r '.[] | .[] | .hooks[] | "  " + (.command // "?")' 2>/dev/null | sort -u
  echo "--- managed-settings.json"
  if [ -f "$SETTINGS" ]; then atual="$(jq -S . "$SETTINGS" 2>/dev/null || echo '{}')"; else atual='{}'; fi
  novo="$(gera_settings "$hj" false | jq -S .)" || return 1
  mostra_diff "$SETTINGS" "$atual" "$novo"
  echo "--- router-policy.json"
  if [ -f "$ROUTER_POLICY" ]; then polatual="$(jq -S . "$ROUTER_POLICY" 2>/dev/null || echo '{}')"; else polatual='{}'; fi
  polnova="$(politica_json)" || return 1
  mostra_diff "$ROUTER_POLICY" "$polatual" "$polnova"
}

if [ "$MODO" = "opus" ]; then
  atual_e_tollens || { echo "ERRO: $SETTINGS ausente ou sem a marca _managed_by=tollens. Instale antes (passo A)." >&2; exit 1; }
  novo="$(opus_json)" || { echo "ERRO: nao foi possivel calcular a liberacao." >&2; exit 1; }
  if [ "$OPUS_DRY" -eq 1 ]; then
    echo "PLANO (nada sera escrito): liberacao do Opus ($OPUS_ID em availableModels; opus fora de deniedModels)"
    mostra_diff "$SETTINGS" "$(jq -S . "$SETTINGS")" "$(printf '%s' "$novo" | jq -S .)"
    exit 0
  fi
  if [ "$(printf '%s' "$novo" | jq -S -c .)" = "$(jq -S -c . "$SETTINGS")" ]; then
    echo "Opus ja liberado: nada a fazer."; exit 0
  fi
  _ts="$(date -u +%Y%m%dT%H%M%SZ)"
  cp -p "$SETTINGS" "$SETTINGS.pre-liberar-opus.$_ts" || { echo "ERRO: backup falhou; nada mudou." >&2; exit 1; }
  _tmp="$ETC/.managed-settings.json.opus.$$"
  printf '%s\n' "$novo" > "$_tmp" && jq -e . "$_tmp" >/dev/null 2>&1 && chmod 0644 "$_tmp" \
    && { [ "$REAL" -eq 0 ] || chown root:root "$_tmp"; } && mv -f "$_tmp" "$SETTINGS" \
    || { rm -f "$_tmp"; echo "ERRO: escrita da liberacao falhou; backup em $SETTINGS.pre-liberar-opus.$_ts" >&2; exit 1; }
  echo "Opus liberado. Backup: $SETTINGS.pre-liberar-opus.$_ts"
  echo "Fable segue negado; fable-guard.sh e sentinela inalterados."
  exit 0
fi

if [ "$MODO" = "revert-router" ]; then
  # Inverso do que ESTE roteador instala: arvore do plugin, politica e as chaves de plugin. Nao toca
  # hooks, modelos nem o resto de /opt/tollens (diferente de --revert, que remove tudo).
  atual_e_tollens || { echo "ERRO: $SETTINGS ausente ou sem a marca _managed_by=tollens; nada removido." >&2; exit 1; }
  _tmp="$ETC/.managed-settings.json.rr.$$"
  jq --arg pid "$ROUTER_ID" --arg mk "$ROUTER_MARKET" '
      (if has("enabledPlugins") then .enabledPlugins |= del(.[$pid]) else . end)
    | (if has("extraKnownMarketplaces") then .extraKnownMarketplaces |= del(.[$mk]) else . end)
    | (if has("prependPlugins") then .prependPlugins |= map(select(. != $pid)) else . end)
    | (if (.enabledPlugins // {}) == {} then del(.enabledPlugins) else . end)
    | (if (.extraKnownMarketplaces // {}) == {} then del(.extraKnownMarketplaces) else . end)
    | (if (.prependPlugins // []) == ["sec-default@builtin"] then del(.prependPlugins) else . end)' "$SETTINGS" > "$_tmp" \
    && jq -e . "$_tmp" >/dev/null 2>&1 && chmod 0644 "$_tmp" \
    && { [ "$REAL" -eq 0 ] || chown root:root "$_tmp"; } \
    || { rm -f "$_tmp"; echo "ERRO: nao foi possivel recalcular o settings; nada removido." >&2; exit 1; }
  mv -f "$_tmp" "$SETTINGS" || { rm -f "$_tmp"; echo "ERRO: instalacao do settings falhou." >&2; exit 1; }
  rm -rf "$OPT/claude-plugins" "$ROUTER_POLICY"
  echo "roteador removido: chaves de plugin, $OPT/claude-plugins e $ROUTER_POLICY. Hooks e modelos intactos."
  exit 0
fi
# =============================================================================================

if [ "$MODO" = "dry" ]; then
  echo "PLANO (nada sera escrito). prefixo='${PREFIX:-/}'"
  plano
  n=$(tipos_politica | wc -l)
  echo "  $n componentes de politica; settings managed em $SETTINGS"
  echo "  allowManagedHooksOnly: NAO seria ativado neste modo (use --enforce, depois de verificar)"
  echo "=== DIFF do que mudaria (calculado em memoria; nenhuma escrita) ==="
  dry_diff || { echo "ERRO: diff indisponivel" >&2; exit 1; }
  exit 0
fi

if [ "$MODO" = "revert" ]; then
  # Remove SOMENTE o que este script cria. Nunca toca em caminho desconhecido.
  #
  # A MARCA `_managed_by` E CONSULTADA AQUI, e nao so no ramo de backup. Antes, o comentario
  # acima ja prometia isto e o codigo nao cumpria: `--revert` apagava QUALQUER
  # `managed-settings.json`, inclusive uma politica corporativa de outra ferramenta - que pode
  # conter `permissions.deny` - sem backup e sem aviso, e sob `sudo`. Promessa em comentario
  # que o codigo nao entrega e o defeito central deste repositorio, aqui no caminho destrutivo.
  if [ -f "$SETTINGS" ] && ! jq -e '._managed_by == "tollens"' "$SETTINGS" >/dev/null 2>&1; then
    echo "ERRO: '$SETTINGS' NAO foi escrito por este instalador (falta a marca _managed_by)." >&2
    echo "      Nada foi removido. Se a intencao e descartar essa politica, remova-a a mao" >&2
    echo "      depois de ler o conteudo - este script nao apaga o que nao criou." >&2
    exit 1
  fi
  # ONDA 34 (ADR 0049). So e restaurado por padrao um `.pre-tollens` que o proprio tollens escreveu. O
  # `.pre-tollens` vivo e de 2026-08-12 (`_managed_by=evidence-gate`, hooks em /opt/evidence-gate, que nao
  # existe): restaura-lo troca a politica atual por uma antiga e o `rm -rf` abaixo apaga hooks que nao
  # estao no repositorio. Recusa ANTES de remover qualquer coisa; `--revert-forcar` e a saida explicita.
  if [ "$REVERT_FORCAR" -ne 1 ] && [ -f "$SETTINGS.pre-tollens" ] \
     && ! jq -e '._managed_by == "tollens"' "$SETTINGS.pre-tollens" >/dev/null 2>&1; then
    echo "ERRO: '$SETTINGS.pre-tollens' nao tem _managed_by=tollens: restaura-lo substitui a politica atual por uma" >&2
    echo "      anterior ao tollens e '$OPT' e removido por inteiro (inclui hooks fora do repositorio)." >&2
    echo "      Nada foi removido. Para desfazer so o roteador: --revert-router. Para restaurar mesmo assim," >&2
    echo "      depois de ler o arquivo: --revert-forcar." >&2
    exit 1
  fi
  if [ -f "$SETTINGS" ]; then rm -f "$SETTINGS"; echo "removido: $SETTINGS"; fi
  if [ -f "$SETTINGS.pre-tollens" ]; then
    mv -f "$SETTINGS.pre-tollens" "$SETTINGS"; echo "restaurado o managed-settings.json anterior"
  fi
  if [ -d "$OPT" ]; then rm -rf "$OPT"; echo "removido: $OPT"; fi
  rmdir "$ETC" 2>/dev/null && echo "removido (vazio): $ETC"
  echo "REVERTIDO. Os hooks de escopo de usuario em ~/.claude voltam a valer."
  exit 0
fi

conformidade_managed(){   # ecoa "ok N" ou lista divergencias; nunca escreve
  local div=0 n=0 dono_ruim=0 grav=0
  while IFS=$'\t' read -r _tipo origem destino sha; do
    n=$((n+1))
    local alvo="$RAIZ/$(destino_managed "$destino")"
    if [ ! -e "$alvo" ]; then echo "  AUSENTE  $alvo"; div=$((div+1)); continue; fi
    local d
    if [ -d "$alvo" ]; then d="$(cd "$alvo" && find . -type f -exec sha256sum {} + | LC_ALL=C sort -k2 | sha256sum | cut -d' ' -f1)"
    else d="$(sha256sum "$alvo" | cut -d' ' -f1)"; fi
    [ "$d" = "$sha" ] || { echo "  DIVERGE  $alvo"; div=$((div+1)); }
    if [ "$REAL" -eq 1 ]; then
      [ "$(stat -c '%U' "$alvo")" = "root" ] || { echo "  DONO!=root  $alvo"; dono_ruim=$((dono_ruim+1)); }
      # o ponto inteiro da fase 2: o ator governado nao pode reescrever a politica
      [ -w "$alvo" ] && [ "$(id -u)" -ne 0 ] && { echo "  GRAVAVEL pelo ator  $alvo"; grav=$((grav+1)); }
    fi
  done < <(tipos_politica)
  echo "RESUMO $n $div $dono_ruim $grav"
}

if [ "$MODO" = "verify" ]; then
  # Tambem valida o manifesto: `--verify` monta caminhos a partir dele para hashear, e um
  # destino hostil faria a conformidade LER fora de $OPT. Nao escreve, mas "conforme" sobre
  # arquivo de outro lugar seria conformidade falsa.
  if ! valida_manifesto; then
    echo "ERRO: manifesto rejeitado - caminho fora dos limites. Conformidade NAO VERIFICADA." >&2
    exit 1
  fi
  out="$(conformidade_managed)"; printf '%s\n' "$out" | grep -v '^RESUMO' || true
  read -r _ n div dono grav <<<"$(printf '%s\n' "$out" | grep '^RESUMO')"
  # HONESTIDADE DE MODO. As colunas de dono e de gravabilidade so sao AVALIADAS quando o
  # prefixo e a raiz real; sob prefixo de ensaio o laco nem entra nesse ramo. Imprimir "0
  # gravaveis pelo ator" ali era pos-condicao vacuamente verdadeira - a checagem nao executou -
  # e a suite lia esse veredito como aprovacao da garantia CENTRAL da fase 2.
  if [ "$REAL" -eq 1 ]; then
    printf 'managed: %s componentes | %s divergentes | %s com dono errado | %s gravaveis pelo ator\n' \
           "$n" "$div" "$dono" "$grav"
  else
    printf 'managed: %s componentes | %s divergentes | dono=NAO VERIFICADO gravabilidade=NAO VERIFICADO (prefixo de ensaio)\n' \
           "$n" "$div"
  fi
  if [ -f "$SETTINGS" ]; then
    printf 'allowManagedHooksOnly=%s\n' "$(jq -r '.allowManagedHooksOnly // false' "$SETTINGS" 2>/dev/null)"
  else
    echo "managed-settings.json AUSENTE"; exit 1
  fi
  [ "${n:-0}" -gt 0 ] || { echo "ESTADO: conjunto VAZIO - nada a verificar, nao e conformidade" >&2; exit 1; }
  [ "$div" -eq 0 ] && [ "$dono" -eq 0 ] && [ "$grav" -eq 0 ] || exit 1
  if [ "$REAL" -eq 1 ]; then
    echo "ESTADO: politica fora do espaco de escrita do ator"
  else
    # A frase acima e a AFIRMACAO CENTRAL da fase 2, e sob prefixo de ensaio ela nao foi
    # medida: posse e gravabilidade so sao avaliadas na raiz real. Imprimi-la aqui seria
    # publicar a garantia a partir do modo em que ela e inverificavel.
    echo "ESTADO: conteudo conforme. A posse por root e a NAO-gravabilidade pelo ator sao"
    echo "        NAO VERIFICADAS neste modo - exigem a raiz real e execucao como root."
  fi
  exit 0
fi

# ---------------------------------------------------------------- deploy / enforce
# PORTAO ZERO: valida TODO o manifesto antes da primeira escrita. Nao ha "aborta no meio":
# um manifesto parcialmente aplicado como root e pior do que nenhum.
if ! valida_manifesto; then
  echo "ERRO: manifesto rejeitado - caminho fora dos limites. NADA foi escrito." >&2
  echo "      O manifesto e conteudo de repositorio; num contexto root ele e entrada nao" >&2
  echo "      confiavel. Regenere com 'bash install/manifest.sh' e inspecione o diff." >&2
  exit 1
fi
# --- DEPLOY EM STAGING ---------------------------------------------------------------------
# ATE 2026-08-04 este laco copiava DIRETO na arvore ativa e os portoes rodavam depois. O proprio
# script admitia a consequencia no caminho de falha: "ATENCAO: arquivos sob $OPT PODEM ter sido
# escritos antes desta checagem". Isto e, um deploy reprovado deixava a arvore ativa PARCIALMENTE
# atualizada - alguns componentes na versao nova, outros na antiga - com a politica velha ainda
# apontando para ela. A auditoria externa nomeou a propriedade que faltava:
#
#     DeployFail  =>  ActiveState_depois == ActiveState_antes
#
# ESCOPO EXATO DESSA IMPLICACAO, porque publica-la larga demais ja custou uma revisao:
#   ActiveState = (arvore em $OPT, politica em $SETTINGS). AS DUAS metades.
#   DeployFail  = qualquer saida != 0 deste script POR ERRO OBSERVADO - portao, `jq`, `cp`,
#                 `chmod`, `chown`, `mv`. Cada uma dessas chamadas tem retorno verificado, e a
#                 fase de commit chama `desfaz` antes de sair.
#   NAO COBERTO  = terminacao que o shell nao observa: `SIGKILL`, queda de energia, filesystem
#                 desmontado no meio. `rename(2)` nao substitui diretorio nao vazio, entao a
#                 troca da arvore sao DUAS chamadas, e uma morte subita entre elas deixa $OPT
#                 ausente. Isso e disponibilidade, nao arvore meio-escrita, e nao ha rollback
#                 possivel de dentro do processo morto. Fechar essa janela exigiria $OPT ser um
#                 symlink trocado por um unico rename - muda o layout, o `--verify`, o
#                 `--revert` e a checagem de posse. Nao feito; registrado no roadmap.
#
# Agora a construcao inteira acontece numa area de staging irmã, todo portao roda LA, e a arvore
# ativa so e tocada quando nada mais pode reprovar. Reprovou: a area de staging e descartada e a
# ativa nunca foi aberta.
STAGE="$OPT.stage.$$"
# TRAP: staging orfa sob /opt seria lixo root-owned acumulando a cada falha. Removida em
# QUALQUER saida - inclusive nos `exit 1` dos portoes abaixo, que sao o caminho esperado.
trap 'rm -rf "$STAGE" 2>/dev/null || true' EXIT
rm -rf "$STAGE" || exit 1
mkdir -p "$STAGE" "$ETC" || exit 1
RAIZ="$STAGE"          # a partir daqui, validar significa validar o STAGING
# RETORNO VERIFICADO EM TODA ESCRITA DO STAGING. Este arquivo nao tem `set -e` (linha 34), e
# ate 2026-08-10 `mkdir`, `cp` e `chmod` aqui eram as unicas escritas do caminho privilegiado
# sem retorno conferido. O ADR 0026 fechou a CONSEQUENCIA - a pos-condicao passou a verificar
# modos exatos, entao um `chmod` mudo vira falha de commit e rollback. Mas a pos-condicao e
# checagem de runtime; a causa e a chamada sem `||`. Corrigir na fonte deixa o erro atribuivel
# ao componente que falhou, em vez de aparecer como "modo inesperado" a tres estagios de
# distancia. Falhar aqui e seguro: o staging e descartavel e o trap da linha 267 o remove.
while IFS=$'\t' read -r _tipo origem destino _sha; do
  alvo="$STAGE/$(destino_managed "$destino")"
  mkdir -p "$(dirname "$alvo")" || { echo "ERRO: mkdir do staging falhou: $alvo" >&2; exit 1; }
  if [ -d "$origem" ]; then
    rm -rf "$alvo" || { echo "ERRO: limpeza do staging falhou: $alvo" >&2; exit 1; }
    cp -a "$origem" "$alvo" || { echo "ERRO: copia de diretorio falhou: $origem" >&2; exit 1; }
  else
    cp -f "$origem" "$alvo" || { echo "ERRO: copia de arquivo falhou: $origem" >&2; exit 1; }
  fi
  case "$alvo" in
    *.sh|*/document-tools/*) chmod 0755 "$alvo" ;;
    *)                       if [ -d "$alvo" ]; then chmod 0755 "$alvo"; else chmod 0644 "$alvo"; fi ;;
  esac || { echo "ERRO: chmod do staging falhou: $alvo" >&2; exit 1; }
done < <(tipos_politica)
# Plugin: o contrato de modos e exato (arquivos 0644, *.sh 0755); a fonte do repo pode trazer 0755.
if [ -d "$STAGE/claude-plugins" ]; then
  find "$STAGE/claude-plugins" -type f \! -name '*.sh' -exec chmod 0644 {} + \
    && find "$STAGE/claude-plugins" -type f -name '*.sh' -exec chmod 0755 {} + \
    || { echo "ERRO: chmod do plugin no staging falhou" >&2; exit 1; }
fi
find "$STAGE" -type d -exec chmod 0755 {} + || { echo "ERRO: chmod de diretorio do staging falhou" >&2; exit 1; }
# POSSE APLICADA NO STAGING, e nao depois da publicacao: se `chown` falhasse com a arvore ja
# ativa, o resultado seria uma politica ativa com arquivos do ator - o oposto da garantia.
if [ "$REAL" -eq 1 ]; then chown -R root:root "$STAGE" || exit 1; fi

# --- PORTAO ANTES DA ESCRITA DA POLITICA -------------------------------------------------
# ORDEM DELIBERADA, e o motivo e um defeito que este repositorio ja pagou. Na primeira versao
# deste script a conformidade era conferida DEPOIS de gravar o `managed-settings.json`. Com
# `--enforce` isso significa: a flag que bloqueia TODO hook de usuario e de plugin ja estaria
# no disco quando a checagem reprovasse - deixando o sistema sem os hooks managed (deploy
# incompleto) E sem os de usuario (bloqueados). O mecanismo inteiro cairia, que e exatamente a
# armadilha que o handoff nomeia.
# E a MESMA classe do defeito do `--dry-run` (ADR 0022, adendo 2): a garantia nova estava
# correta e mal posicionada em relacao a escrita. Acrescentar garantia nao prova que os modos
# existentes continuam seguros.
echo "=== conformidade do escopo managed (ANTES de escrever a politica) ==="
out="$(conformidade_managed)"; printf '%s\n' "$out" | grep -v '^RESUMO' || true
read -r _ n div dono grav <<<"$(printf '%s\n' "$out" | grep '^RESUMO')"
printf 'managed: %s componentes | %s divergentes | %s com dono errado | %s gravaveis pelo ator\n' \
       "$n" "$div" "$dono" "$grav"
# `n` ENTRA NO PORTAO. Sem isto o portao contava DIVERGENCIA e nunca POPULACAO: com o conjunto
# de politica VAZIO, o laco de copia nao copia nada, a conformidade nao itera nada, e
# `0 divergentes` era lido como aprovacao - gravando `allowManagedHooksOnly: true` apontando
# para 14 caminhos inexistentes. Isto e o mecanismo inteiro de hooks desligado com aparencia de
# ligado, que e exatamente a armadilha que este arquivo diz tratar.
# Medido: `tr '\t' ' ' < manifest.lock` (qualquer normalizacao de whitespace, filtro de git ou
# renome de coluna) produz 0 linhas e o --enforce aprovava. MG6 nao pegava: ele sabota UMA
# entrada (div=1), nao esvazia o conjunto. Ausencia de divergencia num conjunto vazio e
# vacuamente verdadeira - a mesma forma logica que este repositorio persegue desde o ADR 0022.
ESPERADOS="$(tipos_politica | wc -l | tr -d ' ')"
if [ "${n:-0}" -eq 0 ] || [ "$n" -ne "$ESPERADOS" ]; then
  echo "ERRO: conjunto de politica VAZIO ou incompleto (n=$n, esperado=$ESPERADOS)." >&2
  echo "      Nada foi escrito e allowManagedHooksOnly NAO foi ativado." >&2
  echo "      Um manifesto que nao produz componentes nao e um deploy conforme: e um deploy" >&2
  echo "      inexistente. Regenere com 'bash install/manifest.sh'." >&2
  exit 1
fi
if [ "$div" -ne 0 ] || [ "$dono" -ne 0 ] || [ "$grav" -ne 0 ]; then
  # MENSAGEM CORRIGIDA (auditoria de 2026-08-04). A versao anterior afirmava "o estado anterior
  # permanece intacto", e isso foi MEDIDO COMO FALSO: quando esta linha era alcancada, os
  # arquivos ja haviam sido copiados. O portao protege a POLITICA, nao a arvore em $OPT - e uma
  # mensagem de erro que promete mais do que o codigo entrega e a mesma classe de defeito que
  # este repositorio persegue, agravada por aparecer justamente no caminho de falha.
  # MENSAGEM CORRIGIDA DE NOVO (2026-08-04, auditoria externa). A versao anterior avisava que
  # arquivos sob $OPT "PODEM ter sido escritos antes desta checagem" - e era verdade, porque a
  # copia ia direto na arvore ativa. Com staging isso deixou de ser possivel, e a frase honesta
  # mudou junto. A anterior ja tinha sido corrigida uma vez por prometer MAIS do que o codigo
  # entregava; esta so pode ser publicada porque o codigo passou a entregar.
  echo "ERRO: deploy incompleto." >&2
  echo "      A POLITICA nao foi escrita e allowManagedHooksOnly NAO foi ativado." >&2
  echo "      A arvore ativa em $OPT NAO foi tocada: tudo foi construido em $STAGE," >&2
  echo "      que sera descartado. Nao ha o que limpar." >&2
  exit 1
fi

# --- managed-settings.json, a partir da MESMA especificacao que o escopo de usuario ---
ENFORCE=false; [ "$MODO" = "enforce" ] && ENFORCE=true
# base = "$OPT/hooks", nao literal "/opt/...": sob prefixo de ensaio o JSON precisa apontar
# para os arquivos que de fato existem, senao o teste nao pode conferir que o caminho declarado
# corresponde a um hook presente - e essa checagem e justamente a que impede ativar apontando
# para o vazio.
HOOKS_JSON="$(bash install/hooks-spec.sh "$OPT/hooks")" || exit 1
# ONDA 34: hooks que ja estavam registrados e a especificacao nao declara (ex.: secret-guard,
# budget-guard, quality-gate, de outro repositorio) sao PRESERVADOS, com o arquivo quando ele
# vive em $OPT/hooks. Sem isto a troca da arvore e do arquivo apagava guardas ativas.
EXT="$(hooks_externos "$HOOKS_JSON")" || { echo "ERRO: leitura dos hooks externos falhou; nada foi alterado." >&2; exit 1; }
HOOKS_JSON="$(junta_hooks "$HOOKS_JSON" "$EXT")" || exit 1
while IFS= read -r _cmd; do
  _p="${_cmd#bash }"
  case "$_p" in
    "$OPT"/hooks/*)
      _rel="${_p#"$OPT"}"
      if [ -f "$OPT$_rel" ] && [ ! -e "$STAGE$_rel" ]; then
        cp -p "$OPT$_rel" "$STAGE$_rel" && chmod 0755 "$STAGE$_rel" \
          || { echo "ERRO: preservacao do hook externo falhou: $_p" >&2; exit 1; }
        if [ "$REAL" -eq 1 ]; then chown root:root "$STAGE$_rel" || exit 1; fi
        echo "  hook externo preservado: $_p"
      fi ;;
  esac
done < <(printf '%s' "$EXT" | jq -r '[..|objects|select(has("command"))|.command]|unique[]')

# PORTAO DE POPULACAO CONTRA A FONTE QUE DECLARA O CONSUMO.
#
# O portao anterior era TAUTOLOGICO, e o cabecalho deste arquivo prometia o que ele nao fazia.
# Ele comparava `n` (itens conformes) com `tipos_politica | wc -l` - e `n` vinha do laco que
# itera a MESMA `tipos_politica`. So podia falhar com o conjunto vazio. Medido: removendo UMA
# linha do manifesto (`grep -v` do verify-gate), `--enforce` saia 0, gravava
# `allowManagedHooksOnly: true`, e a politica declarava `bash .../hooks/verify-gate.sh` para um
# arquivo QUE NAO EXISTIA. `--verify` sobre esse estado imprimia `0 divergentes` e
# `conteudo conforme`.
#
# O gatilho e o procedimento NORMAL do repositorio, nao sabotagem: `install/manifest.sh` gera
# por glob de diretorio; renomear ou mover um hook e regenerar produz esse estado.
#
# A politica vem de OUTRA fonte - `install/hooks-spec.sh` - e o produto nunca a confrontava com
# o disco. A propriedade existia apenas no oraculo do teste (MG4), exercitada sobre o manifesto
# real, onde era vacuamente verdadeira: a garantia morava no TESTE e nao no ARTEFATO, que e a
# inversao que este repositorio persegue. Agora quem DECLARA o consumo e quem e cobrado.
#
# A POLITICA DECLARA O CAMINHO ATIVO ($OPT), mas quem existe neste instante e o STAGING. A
# presenca e conferida no staging TRADUZINDO o prefixo - e nao gerando a politica com o caminho
# de staging, que iria parar no managed-settings.json e apontaria para um diretorio que sera
# apagado. Conferir no lugar errado seria a mesma familia de defeito que este portao ja corrigiu:
# uma checagem que passa sem tocar no que decide.
AUSENTES=0
while IFS= read -r _cmd; do
  _p="${_cmd#bash }"
  case "$_p" in "$OPT"/*) _p_stage="$STAGE${_p#"$OPT"}" ;; *) _p_stage="$_p" ;; esac
  [ -f "$_p_stage" ] || { echo "  HOOK DECLARADO NA POLITICA E AUSENTE NO DISCO: $_p" >&2; AUSENTES=$((AUSENTES+1)); }
done < <(printf '%s' "$HOOKS_JSON" | jq -r '[..|objects|select(has("command"))|.command]|unique[]')
if [ "$AUSENTES" -ne 0 ]; then
  echo "ERRO: a politica declara $AUSENTES hook(s) inexistentes em $OPT." >&2
  echo "      Nada foi escrito e allowManagedHooksOnly NAO foi ativado." >&2
  echo "      A arvore ativa NAO foi tocada; o staging sera descartado." >&2
  echo "      Politica apontando para o vazio COM enforcement ligado e o mecanismo inteiro" >&2
  echo "      desligado com aparencia de ligado. Regenere o manifesto e reinstale." >&2
  exit 1
fi

# =============================================================================================
# ESTADO ATIVO = (arvore em $OPT, politica em $SETTINGS). OS DOIS, e nao so a arvore.
#
# SEGUNDA CORRECAO (revisao independente do PR #5). A versao anterior publicava a arvore, APAGAVA
# a anterior, e so entao gerava e instalava o `managed-settings.json` - com `mktemp`, `jq`, `cp`,
# `chmod` e `chown` todos apos o ponto sem volta, e nenhum deles com retorno verificado num
# script que roda sob `set -uo pipefail`, sem `set -e`. Consequencias reais:
#
#   - `mktemp`/`jq` falhando  -> `exit 1` com a arvore ativa JA trocada e a anterior JA apagada;
#   - `cp` falhando           -> execucao SEGUIA, imprimia a mensagem de sucesso e saia 0, com a
#                                arvore nova e a politica velha (ou ausente);
#   - `chmod`/`chown` falhando -> idem.
#
# A propriedade PUBLICADA era `DeployFail => ActiveState inalterado`. A propriedade ENTREGUE era
# `GateFail_{pre-publicacao} => OptTree inalterada`. Publicar a primeira enquanto o codigo
# entregava a segunda e exatamente a classe de defeito que este repositorio persegue - mensagem
# que promete mais do que o mecanismo cumpre - e aconteceu no proprio commit que dizia corrigi-la.
#
# A correcao tem duas partes:
#
#   1. TUDO QUE PODE FALHAR ACONTECE ANTES. A politica e gerada e validada enquanto o estado
#      ativo ainda esta intocado. Ela nao depende do staging: os caminhos que ela declara sao os
#      caminhos FINAIS, conhecidos desde o inicio.
#   2. A FASE DE COMMIT SO CONTEM RENAMES, cada um com retorno verificado, e o material de
#      rollback (arvore anterior e politica anterior) so e descartado quando os dois ja estao
#      no lugar. Qualquer falha ali chama `desfaz`, que devolve OS DOIS.
# =============================================================================================

# --- FASE DE PREPARO: nada aqui toca o estado ativo -------------------------------------------
# O temporario vive em $ETC, e nao em /tmp, para que a instalacao final seja `rename(2)` no MESMO
# filesystem - atomico - em vez de `cp`, que tem estado intermediario observavel.
SET_NOVO="$ETC/.managed-settings.json.novo.$$"
SET_ROLLBACK="$ETC/.managed-settings.json.rollback.$$"
trap 'rm -rf "$STAGE" "$SET_NOVO" "$SET_ROLLBACK" 2>/dev/null || true' EXIT

if ! gera_settings "$HOOKS_JSON" "$ENFORCE" > "$SET_NOVO" || ! jq -e . "$SET_NOVO" >/dev/null 2>&1; then
  echo "ERRO: managed-settings.json nao pode ser gerado ou nao e JSON valido." >&2
  echo "      NADA foi alterado: nem a arvore ativa, nem a politica." >&2
  exit 1
fi
chmod 0644 "$SET_NOVO" || { echo "ERRO: chmod da politica nova falhou; nada foi alterado." >&2; exit 1; }
if [ "$REAL" -eq 1 ]; then
  chown root:root "$SET_NOVO" || { echo "ERRO: chown da politica nova falhou; nada foi alterado." >&2; exit 1; }
fi

# ONDA 34: politica do roteador, validada ANTES de qualquer escrita ativa, a partir do que sera
# publicado (o motor e a politica do staging).
POL_NOVO="$ETC/.router-policy.json.novo.$$"
POL_ROLLBACK="$ETC/.router-policy.json.rollback.$$"
trap 'rm -rf "$STAGE" "$SET_NOVO" "$SET_ROLLBACK" "$POL_NOVO" "$POL_ROLLBACK" 2>/dev/null || true' EXIT
politica_json > "$POL_NOVO" && jq -e . "$POL_NOVO" >/dev/null 2>&1 \
  || { echo "ERRO: politica do roteador nao pode ser gerada; nada foi alterado." >&2; exit 1; }
valida_politica "$POL_NOVO" "$STAGE/claude-plugins/plugins/tollens-router/engine.mjs" \
  || { echo "ERRO: politica do roteador reprovada em validatePolicy; nada foi alterado." >&2; exit 1; }
chmod 0644 "$POL_NOVO" || { echo "ERRO: chmod da politica do roteador falhou; nada foi alterado." >&2; exit 1; }
if [ "$REAL" -eq 1 ]; then chown root:root "$POL_NOVO" || { echo "ERRO: chown da politica do roteador falhou." >&2; exit 1; }; fi
TEM_POL=0
if [ -f "$ROUTER_POLICY" ]; then
  cp -p "$ROUTER_POLICY" "$POL_ROLLBACK" || { echo "ERRO: copia de rollback da politica do roteador falhou; nada mudou." >&2; exit 1; }
  TEM_POL=1
fi
# Backup datado do settings atual, so quando o conteudo muda (reaplicar nao acumula backups).
if atual_e_tollens && [ "$(jq -S -c . "$SETTINGS")" != "$(jq -S -c . "$SET_NOVO")" ]; then
  cp -p "$SETTINGS" "$SETTINGS.pre-roteador.$(date -u +%Y%m%dT%H%M%SZ)" \
    || { echo "ERRO: backup do settings falhou; nada mudou." >&2; exit 1; }
fi

# COPIA DE ROLLBACK da politica atual. Distinta do backup `.pre-tollens`, que tem outra
# funcao (preservar politica de TERCEIRO, ver MG8/MG12) e outra duracao (permanente). Esta e
# efemera e existe so para desfazer uma fase de commit que falhou pela metade.
TEM_ROLLBACK=0
if [ -f "$SETTINGS" ]; then
  cp -f "$SETTINGS" "$SET_ROLLBACK" \
    || { echo "ERRO: nao foi possivel copiar a politica atual para rollback; nada mudou." >&2; exit 1; }
  TEM_ROLLBACK=1
fi

# BACKUP SO DO QUE NAO E NOSSO. Defeito encontrado por MG8: a condicao era apenas "existe e
# ainda nao ha backup", entao a SEGUNDA execucao (deploy e depois --enforce) tratava o arquivo
# que o proprio instalador havia escrito como se fosse pre-existente. O `--revert` seguinte
# restaurava esse "backup" e recriava a politica - reversao que nao reverte, que e pior do que
# nao ter reversao, porque o operador acredita ter voltado ao estado anterior.
# A marca `_managed_by` responde "este arquivo e nosso?" sem depender de heuristica.
FEZ_PRE=0
if [ -f "$SETTINGS" ] && [ ! -f "$SETTINGS.pre-tollens" ] \
   && ! jq -e '._managed_by == "tollens"' "$SETTINGS" >/dev/null 2>&1; then
  cp -f "$SETTINGS" "$SETTINGS.pre-tollens" \
    || { echo "ERRO: backup da politica de terceiro falhou; nada mudou." >&2; exit 1; }
  FEZ_PRE=1
fi

# --- FASE DE COMMIT: so renames, cada um verificado -------------------------------------------
ANTERIOR="$OPT.anterior.$$"

desfaz(){  # devolve o estado ativo INTEIRO ao que era: arvore E politica
  if [ -d "$ANTERIOR" ]; then
    rm -rf "$OPT" 2>/dev/null || true
    mv -f "$ANTERIOR" "$OPT" 2>/dev/null \
      && echo "      ROLLBACK: arvore anterior recolocada em $OPT." >&2 \
      || echo "      ATENCAO: o rollback da arvore FALHOU; $OPT pode estar ausente." >&2
  fi
  if [ "$TEM_ROLLBACK" -eq 1 ] && [ -f "$SET_ROLLBACK" ]; then
    mv -f "$SET_ROLLBACK" "$SETTINGS" 2>/dev/null \
      && echo "      ROLLBACK: politica anterior recolocada em $SETTINGS." >&2 \
      || echo "      ATENCAO: o rollback da politica FALHOU." >&2
  elif [ "$TEM_ROLLBACK" -eq 0 ]; then
    # nao havia politica antes; o estado anterior e a AUSENCIA dela
    rm -f "$SETTINGS" 2>/dev/null || true
  fi
  [ "$FEZ_PRE" -eq 1 ] && rm -f "$SETTINGS.pre-tollens" 2>/dev/null || true
  if [ "$TEM_POL" -eq 1 ] && [ -f "$POL_ROLLBACK" ]; then
    mv -f "$POL_ROLLBACK" "$ROUTER_POLICY" 2>/dev/null || echo "      ATENCAO: o rollback da politica do roteador FALHOU." >&2
  elif [ "$TEM_POL" -eq 0 ]; then
    rm -f "$ROUTER_POLICY" 2>/dev/null || true
  fi
}

# FAILPOINT - existe SO para teste (tests/unit/managed.sh, MG17/MG18). Sem a variavel definida
# e um no-op. Nao concede autoridade alguma: o unico efeito possivel e provocar uma falha e o
# rollback correspondente. Sem ele, a falha POS-PUBLICACAO nao pode ser exercitada de forma
# deterministica - e foi justamente a ausencia desse caso que deixou o defeito acima passar.
falha_se(){ [ "${MANAGED_FAILPOINT:-}" = "$1" ] && { echo "ERRO: falha injetada no ponto '$1'." >&2; return 0; }; return 1; }

if [ -d "$OPT" ]; then
  mv -f "$OPT" "$ANTERIOR" \
    || { echo "ERRO: nao foi possivel afastar a arvore ativa; nada mudou." >&2; exit 1; }
fi
if falha_se afastar-opt; then desfaz; exit 1; fi

if ! mv -f "$STAGE" "$OPT"; then
  echo "ERRO: a publicacao da arvore falhou." >&2; desfaz; exit 1
fi
if falha_se publicar-opt; then desfaz; exit 1; fi

if ! mv -f "$SET_NOVO" "$SETTINGS"; then
  echo "ERRO: a instalacao da politica falhou APOS a publicacao da arvore." >&2
  desfaz; exit 1
fi
if falha_se instalar-politica; then desfaz; exit 1; fi
if ! mv -f "$POL_NOVO" "$ROUTER_POLICY"; then
  echo "ERRO: a instalacao da politica do roteador falhou." >&2; desfaz; exit 1
fi

# COMMIT CONFIRMADO. So agora o material de rollback pode ser descartado - antes disto, qualquer
# saida do script passa por `desfaz` ou pelo trap, e ambos precisam dele.
rm -rf "$ANTERIOR" 2>/dev/null || true
rm -f "$SET_ROLLBACK" "$POL_ROLLBACK" 2>/dev/null || true
RAIZ="$OPT"   # publicado: validar volta a significar validar a arvore ativa

if [ "$MODO" = "enforce" ] || [ "$(jq -r '.allowManagedHooksOnly' "$SETTINGS" 2>/dev/null)" = "true" ]; then
  echo "allowManagedHooksOnly=true - hooks de escopo de USUARIO e de PLUGIN estao agora bloqueados."
  echo "(hooks de plugin passam so se o plugin estiver em enabledPlugins do managed: o roteador esta.)"
  echo "Desfazer o roteador: sudo bash install/apply-managed.sh --revert-router. NAO use --revert sobre um"
  echo ".pre-tollens antigo: ele recusa por padrao (ver docs/runbooks/roteador-instalacao.md, Rollback)."
else
  echo "allowManagedHooksOnly=false - por enquanto os hooks managed SOMAM aos de usuario."
  echo "Cada hook rodara DUAS vezes ate a ativacao. Isso e esperado e mensuravel; e o passo que"
  echo "prova que o escopo managed carregou ANTES de desligar o escopo de usuario."
fi
