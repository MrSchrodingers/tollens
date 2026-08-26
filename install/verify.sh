#!/usr/bin/env bash
# CONFORMIDADE: o que esta instalado e o que o manifesto declara sao a mesma coisa?
#
# Este arquivo e a resposta ao achado que subordinou todos os outros: o repositorio descrevia
# um sistema e a maquina rodava outro. Hooks nao versionados, agentes ausentes do repo e um
# verify-gate uma versao atras - por tres meses, sem sinal. Nao havia operacao de conferir.
#
# Colunas do relatorio, conforme o contrato acordado:
#   desired    o manifesto declara
#   installed  existe no disco com o mesmo digest
#   governed   sob qual autoridade foi carregado (user = gravavel pelo ator)
#
# `governed=user` NAO e um erro: e o estado atual e declarado desta fase. Componente correto
# carregado de origem gravavel tem integridade momentanea, nao autoridade. A fase seguinte
# move a politica para managed settings; ate la, isto fica visivel em vez de implicito.
set -uo pipefail
export LC_ALL=C   # ver install/manifest.sh: digest nao pode depender do locale
cd "$(dirname "$0")/.." || exit 1
MAN="${1:-install/manifest.lock}"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
[ -f "$MAN" ] || { echo "manifesto ausente: $MAN (rode install/manifest.sh)"; exit 2; }

OK=0; DRIFT=0; MISSING=0; EXTRA=0
declare -A ESPERADO

while IFS=$'\t' read -r tipo origem destino digest; do
  case "$tipo" in ''|'#'*) continue;; esac
  ESPERADO["$destino"]=1
  alvo="$DEST/$destino"
  if [ ! -e "$alvo" ]; then
    printf '  AUSENTE   %-42s (declarado, nao instalado)\n' "$destino"; MISSING=$((MISSING+1)); continue
  fi
  if [ -d "$alvo" ]; then
    # O MANIFESTO e a autoridade, tambem para diretorio. Comparar instalado contra a working
    # tree deixava o manifesto fora do circuito: repo drift passava despercebido localmente.
    atual="$(cd "$alvo" && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort -k2 | sha256sum | cut -c1-64)"
    esper="$digest"
    fonte="$(cd "$origem" && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort -k2 | sha256sum | cut -c1-64)"
    if [ "$fonte" != "$digest" ]; then
      printf '  REPO-DRIFT %-40s (working tree != manifesto; rode install/manifest.sh)\n' "$destino"; DRIFT=$((DRIFT+1)); continue
    fi
  else
    atual="$(sha256sum "$alvo" 2>/dev/null | cut -c1-64)"; esper="$digest"
  fi
  if [ "$atual" = "$esper" ]; then OK=$((OK+1))
  else printf '  DIVERGE   %-42s (instalado != manifesto)\n' "$destino"; DRIFT=$((DRIFT+1)); fi
done < "$MAN"

# Componente ATIVO que o manifesto nao conhece: e o modo de falha original deste repo.
for d in hooks agents; do
  [ -d "$DEST/$d" ] || continue
  for f in "$DEST/$d"/*; do
    [ -e "$f" ] || continue
    rel="$d/$(basename "$f")"
    [ -n "${ESPERADO[$rel]:-}" ] || { printf '  ORFAO     %-42s (roda, nao esta no manifesto)\n' "$rel"; EXTRA=$((EXTRA+1)); }
  done
done
for f in "$DEST"/skills/*/; do
  [ -d "$f" ] || continue
  rel="skills/$(basename "${f%/}")"
  [ -n "${ESPERADO[$rel]:-}" ] || { printf '  ORFAO     %-42s (roda, nao esta no manifesto)\n' "$rel"; EXTRA=$((EXTRA+1)); }
done

TOT=$((OK+DRIFT+MISSING))
echo
printf 'PROJECAO USUARIO: %s/%s ok | %s divergentes | %s ausentes | %s orfaos\n' "$OK" "$TOT" "$DRIFT" "$MISSING" "$EXTRA"

# ONDA 22b (G33). Ate aqui esta linha dizia `ESTADO: conforme (governed=user)`, e isso era uma
# afirmacao VERDADEIRA sobre a projecao de usuario apresentada como descricao do SISTEMA. Depois
# que o escopo managed passou a existir, `48/49 ok` deixou de caracterizar governanca: ele mede
# integridade de digest numa arvore que o ator pode reescrever, enquanto a politica em vigor vem
# de outro lugar. Trocar a string por `governed=managed` seria corrigir o rotulo sem corrigir o
# instrumento - a classe que a onda 20 corrigiu.
#
# As tres observacoes sao INDEPENDENTES e so a conjuncao sustenta uma conclusao:
#   INSTALADO  digest bate           (o que este laco mede)
#   IMPOSTO    o ator nao reescreve  (posse do arquivo em vigor)
#   ATIVADO    o runtime carregou    (evento observado, fora do alcance de um verificador estatico)
MGD_DIR="${TOLLENS_MANAGED_DIR:-/etc/claude-code}"
M_OK=0; M_FALTA=0
_posse(){ stat -c '%U' "$1" 2>/dev/null || echo '?'; }
printf '\nPROJECAO MANAGED:\n'
for _alvo in "$MGD_DIR/CLAUDE.md" "$MGD_DIR/managed-settings.json" "$MGD_DIR/.claude/agents" "$MGD_DIR/.claude/skills"; do
  if [ ! -e "$_alvo" ]; then
    printf '  AUSENTE   %-42s\n' "${_alvo#$MGD_DIR/}"; M_FALTA=$((M_FALTA+1)); continue
  fi
  _d="$(_posse "$_alvo")"
  if [ "$_d" = root ]; then
    printf '  IMPOSTO   %-42s (root)\n' "${_alvo#$MGD_DIR/}"; M_OK=$((M_OK+1))
  else
    printf '  GRAVAVEL  %-42s (%s - imposicao NAO se sustenta)\n' "${_alvo#$MGD_DIR/}" "$_d"; M_FALTA=$((M_FALTA+1))
  fi
done

# ATIVACAO nao e observavel por verificador estatico: exige evento de runtime. O que este script
# pode dizer e se HA registro, nunca se o registro e completo - e o log e gravavel pelo ator
# (G39), entao ele e indicio, nao prova.
ATV="${TOLLENS_ACTIVATION_LOG:-/var/log/tollens-activation.jsonl}"
printf '\nATIVACAO:\n'
if [ -s "$ATV" ]; then
  _n="$(grep -c '"t":"Managed"' "$ATV" 2>/dev/null || echo 0)"
  printf '  INDICIO   %s evento(s) Managed em %s\n' "$_n" "$ATV"
  printf '  LIMITE    o log e %s - o ator governado pode forja-lo (G39). Indicio, nao prova.\n' "$(_posse "$ATV")"
else
  printf '  NAO VERIFICADO  sem registro de ativacao em %s\n' "$ATV"
fi

printf '\nGOVERNANCA GLOBAL: '
if [ $((DRIFT+MISSING+EXTRA)) -ne 0 ]; then
  echo "DIVERGENTE - a projecao de usuario nao e o que o repositorio declara."; exit 1
elif [ "$M_FALTA" -ne 0 ]; then
  echo "PARCIAL - projecao de usuario integra, escopo managed incompleto ou gravavel."; exit 1
else
  echo "governed=managed (projecao de usuario integra; politica em vigor root-owned; ativacao com indicio, nao prova)"
  exit 0
fi
