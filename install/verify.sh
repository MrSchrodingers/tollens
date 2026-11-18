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
# ONDA 22d (F7 do refutador): o preambulo abaixo descrevia a fase ANTERIOR e sobreviveu a onda que
# a encerrou. Hoje este script mede TRES observacoes e deriva `governed=managed`; `governed=user`
# nao e mais impresso por ele. O paragrafo fica como registro do que a fase 1 admitia, e nao como
# descricao do comportamento atual.
#
# [HISTORICO, fase 1] `governed=user` NAO e um erro: e o estado atual e declarado desta fase. Componente correto
# carregado de origem gravavel tem integridade momentanea, nao autoridade. A fase seguinte
# move a politica para managed settings; ate la, isto fica visivel em vez de implicito.
set -uo pipefail
export LC_ALL=C   # ver install/manifest.sh: digest nao pode depender do locale
cd "$(dirname "$0")/.." || exit 1
# ONDA 34: o tipo `plugin` e so do escopo managed (root:root); o escopo de usuario o ignora.
MAN="${1:-install/manifest.lock}"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
[ -f "$MAN" ] || { echo "manifesto ausente: $MAN (rode install/manifest.sh)"; exit 2; }

OK=0; DRIFT=0; MISSING=0; EXTRA=0
declare -A ESPERADO

while IFS=$'\t' read -r tipo origem destino digest; do
  case "$tipo" in ''|'#'*|plugin) continue;; esac
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

# ONDA 22d (F9 do refutador). ORFAO DE TOPO NUNCA FOI VARRIDO. A varredura acima cobre
# `hooks/`, `agents/` e `skills/`; arquivo na RAIZ de $DEST nunca entrou nela. Consequencia
# medida: numa maquina sem `$DEST/tollens/managed-files.lock`, o `apply.sh` NAO remove o
# `CLAUDE.md` que saiu do manifesto, e 18 KB de kernel morto seguem sendo CONCATENADOS em toda
# sessao - com este verificador imprimindo `0 orfaos`. O componente saiu do manifesto; a copia
# antiga no disco nao some sozinha, e silencio sobre ela e a conformidade falsa que este arquivo
# existe para impedir.
if [ -f "$DEST/CLAUDE.md" ]; then
  printf '  ORFAO     %-42s (saiu do manifesto; e CONCATENADO a toda sessao)\n' "CLAUDE.md"
  EXTRA=$((EXTRA+1))
fi

TOT=$((OK+DRIFT+MISSING))
echo
printf 'PROJECAO USUARIO: %s/%s ok | %s divergentes | %s ausentes | %s orfaos\n' "$OK" "$TOT" "$DRIFT" "$MISSING" "$EXTRA"
# ONDA 29 (issue #39). VEREDITO NOMEADO POR ESCOPO, alem do resumo numerico acima: o agregado
# final (GOVERNANCA GLOBAL, adiante) publicava um unico veredito derivado de um subconjunto do
# que decide. Cada escopo passa a ter uma linha propria, nunca coalescida nas outras.
if [ $((DRIFT+MISSING+EXTRA)) -eq 0 ]; then
  echo 'VEREDITO USER_PROJECTION: CONFORME'
else
  echo 'VEREDITO USER_PROJECTION: DIVERGENTE'
fi

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
#
# ONDA 22c. AUSENTE NAO E DIVERGENTE, E OS DOIS NAO PODEM COMPARTILHAR CONTADOR. A primeira versao
# desta secao somava AUSENTE e GRAVAVEL num unico `M_FALTA` e devolvia exit 1 para qualquer um dos
# dois. Consequencia medida na CI (runs 33007234824 e 33007230205, ambos vermelhos em d4fd41b):
# `install/apply.sh` termina chamando este script, entao o exit deste virou o exit DAQUELE, e o
# instalador da projecao de USUARIO passou a reprovar em toda maquina onde a fase managed nao esta
# implantada - que e o caso comum, e um estado que `apply.sh` NAO PODE corrigir, porque implantar
# managed exige root e snapshot root-owned (ADR 0026). O instalador reprovava por um escopo alheio.
#
# O principio ja estava escrito neste repositorio, em control/hooks/session-integrity.sh:29:
# "`absent` NAO e `conformant`: maquina sem fase managed e o caso comum, e reportar drift ali seria
# o falso positivo que faz o operador desligar o mecanismo". O hook acertava; este verificador, nao.
#
# Os dois estados sao materialmente diferentes e por isso tem contador e codigo de saida proprios:
#   AUSENTE   a fase managed nao foi implantada        -> benigno, acionavel, exit 3
#   GRAVAVEL  foi implantada e o ator pode reescrever  -> imposicao NAO se sustenta, exit 4
MGD_DIR="${TOLLENS_MANAGED_DIR:-/etc/claude-code}"
M_OK=0; M_AUSENTE=0; M_GRAVAVEL=0; M_DIVERGE=0; M_NV=0
_posse(){ stat -c '%U' "$1" 2>/dev/null || echo '?'; }
# Digest recursivo de arquivo OU diretorio; stdout vazio (nunca "0 arquivos") quando a leitura
# falha - e o que permite ao chamador distinguir "nao pude ler" de "conteudo bate por acaso".
_digest_arvore(){
  if [ -d "$1" ]; then
    (cd "$1" 2>/dev/null && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort -k2 | sha256sum | cut -d' ' -f1)
  else
    sha256sum "$1" 2>/dev/null | cut -d' ' -f1
  fi
}
printf '\nPROJECAO MANAGED (capacidade - %s):\n' "$MGD_DIR"
for _alvo in "$MGD_DIR/CLAUDE.md" "$MGD_DIR/managed-settings.json" "$MGD_DIR/.claude/agents" "$MGD_DIR/.claude/skills"; do
  if [ ! -e "$_alvo" ]; then
    printf '  AUSENTE   %-42s\n' "${_alvo#$MGD_DIR/}"; M_AUSENTE=$((M_AUSENTE+1)); continue
  fi
  _d="$(_posse "$_alvo")"
  # ONDA 22d (F2 do refutador). POSSE NAO E CONTEUDO. Ate aqui a unica pergunta feita a cada alvo
  # era "o dono e root?", e a resposta virava `IMPOSTO`. Medido: o kernel em vigor podia ser
  # SUBSTITUIDO por qualquer conteudo root-owned e esta linha seguia imprimindo IMPOSTO, com
  # `GOVERNANCA GLOBAL: governed=managed` e exit 0. Ninguem comparava digest - e o kernel e o
  # componente de maior alcance do sistema, porque entra em toda sessao.
  # ONDA 29 (issue #39, F5). O EIXO DE CONTEUDO SO EXISTIA PARA O KERNEL. `.claude/agents` e
  # `.claude/skills` so tinham teste de POSSE - `IMPOSTO` saia impresso sem nenhuma comparacao
  # contra `execution/agents`/`execution/skills`, a mesma classe que a onda 22d ja havia corrigido
  # para o kernel e nao propagou para os vizinhos. `managed-settings.json` continua sem fonte
  # canonica proxima o bastante para comparar byte a byte aqui - o comparador proprio dele e a
  # arvore de POLITICA, abaixo (`apply-managed.sh --verify` confere o JSON gerado contra o que
  # esta em vigor).
  _fonte=""
  case "${_alvo#$MGD_DIR/}" in
    CLAUDE.md)      _fonte="execution/config/CLAUDE.md" ;;
    .claude/agents) _fonte="execution/agents" ;;
    .claude/skills) _fonte="execution/skills" ;;
  esac
  if [ -n "$_fonte" ] && [ -e "$_fonte" ]; then
    _d_alvo="$(_digest_arvore "$_alvo")"; _d_fonte="$(_digest_arvore "$_fonte")"
    # ONDA 29 (issue #39, F8). LEITURA QUE FALHA NAO E MEDIDA NEGATIVA. `sha256sum` que morre por
    # permissao produz string vazia; comparar essa string vazia contra um digest valido sempre
    # "diverge", e o alvo caia no ramo DIVERGE por um motivo que nunca foi lido - o instrumento
    # convertia ausencia de medida em medida negativa. Falha de leitura tem estado proprio.
    if [ -z "$_d_alvo" ] || [ -z "$_d_fonte" ]; then
      printf '  NAO VERIFICADO %-38s (motivo: sem permissao de leitura)\n' "${_alvo#$MGD_DIR/}"
      M_NV=$((M_NV+1)); continue
    fi
    if [ "$_d_alvo" != "$_d_fonte" ]; then
      printf '  DIVERGE   %-42s (conteudo != %s)\n' "${_alvo#$MGD_DIR/}" "$_fonte"; M_DIVERGE=$((M_DIVERGE+1)); continue
    fi
  fi
  if [ "$_d" = root ]; then
    printf '  IMPOSTO   %-42s (root%s)\n' "${_alvo#$MGD_DIR/}" "$([ -n "$_fonte" ] && echo ', digest confere')"; M_OK=$((M_OK+1))
  else
    printf '  GRAVAVEL  %-42s (%s - imposicao NAO se sustenta)\n' "${_alvo#$MGD_DIR/}" "$_d"; M_GRAVAVEL=$((M_GRAVAVEL+1))
  fi
done
if   [ "$M_DIVERGE"  -ne 0 ]; then CAP_STATE=divergente
elif [ "$M_GRAVAVEL" -ne 0 ]; then CAP_STATE=gravavel
elif [ "$M_AUSENTE"  -ne 0 ]; then CAP_STATE=ausente
elif [ "$M_NV"       -ne 0 ]; then CAP_STATE=nao_verificado
else CAP_STATE=conforme
fi

# ONDA 29 (issue #39). ESCOPO DE POLITICA - /opt/tollens (hooks+adapters+doctools+lib). E A
# ARVORE QUE DECIDE sob `allowManagedHooksOnly=true`: nenhum dos quatro alvos acima e ela, e ate
# aqui o agregado publicava veredito sobre o escopo managed sem nunca ter lido a metade que o
# runtime de fato aplica. G50 (corpus) ja registrava a prescricao: DELEGAR a
# `apply-managed.sh --verify`, que ja cobre confinamento, digest, posse e gravabilidade dos ~32
# componentes de politica, em vez de reimplementar um segundo comparador que poderia divergir do
# que o instalador de fato aplica.
#
# SEAM DE TESTE (estilo control/hooks/session-integrity.sh:57-65): `MANAGED_PREFIX` e o seam que
# `apply-managed.sh` ja aceita nativamente, herdado pelo subprocesso sem precisar de novo
# `export` - por isso a fixtura NUNCA audita o `/opt` real quando o chamador o define. E o UNICO
# seam que de fato isola o delegado: `TOLLENS_MANAGED_OPT` sozinho (sem `MANAGED_PREFIX`) muda
# so o que esta secao EXIBE e a checagem de AUSENCIA logo abaixo - a chamada a
# `apply-managed.sh --verify` continua auditando `/opt` real, porque esse binario nao conhece
# `TOLLENS_MANAGED_OPT`. Fixture que precisa isolar o delegado tem de definir `MANAGED_PREFIX`.
OPT_DIR="${TOLLENS_MANAGED_OPT:-${MANAGED_PREFIX:-}/opt/tollens}"
_POL_SETTINGS="${MANAGED_PREFIX:-}/etc/claude-code/managed-settings.json"
POL_STATE="ausente"
printf '\nPROJECAO MANAGED (politica - %s):\n' "$OPT_DIR"
if [ ! -d "$OPT_DIR" ] && [ ! -f "$_POL_SETTINGS" ]; then
  # AUSENTE, nao NAO VERIFICADO: fase managed nao implantada e o caso comum (maquina sem root), e
  # tratar isso como divergencia ou como lacuna de medida e o falso positivo que
  # session-integrity.sh:43 ja nomeia para o mesmo par arvore/politica.
  printf '  AUSENTE   %-42s (fase managed nao implantada)\n' "$OPT_DIR"
elif [ ! -f install/apply-managed.sh ]; then
  POL_STATE="nao_verificado"
  printf '  NAO VERIFICADO %-38s (motivo: install/apply-managed.sh ausente)\n' "$OPT_DIR"
else
  POL_OUT="$(MANAGED_PREFIX="${MANAGED_PREFIX:-}" bash install/apply-managed.sh --verify 2>&1)"; POL_RC=$?
  printf '%s\n' "$POL_OUT" | sed 's/^/  /'
  # MAPA DE RC - o mesmo que control/hooks/session-integrity.sh:73-77 ja usa para o mesmo
  # binario: 0 CONFORME, 1 DIVERGENTE (conteudo, posse OU gravabilidade - o worker nao os
  # discrimina no exit code, e a linha acima ja publica QUAL), {2,64,77,78} e qualquer outro
  # RECUSA DE VERIFICAR - nao e medida de divergencia, e ausencia de medida.
  case "$POL_RC" in
    0) POL_STATE="conforme" ;;
    1) POL_STATE="divergente" ;;
    *) POL_STATE="nao_verificado"
       printf '  NAO VERIFICADO %-38s (motivo: apply-managed.sh --verify recusou verificar, exit %s)\n' \
              "$OPT_DIR" "$POL_RC" ;;
  esac
fi

# COMBINACAO DAS DUAS METADES DE MANAGED. Nenhuma decide sozinha: a politica pode divergir com a
# capacidade conforme (kernel substituido, hooks intactos) e vice-versa. A pior das duas e o
# veredito do escopo managed - "pior" no sentido de que NAO VERIFICADO nunca e mascarado por um
# AUSENTE que aconteceu de ser medido no outro lado (issue #39, criterio 3).
_rank(){ case "$1" in
  divergente) echo 4 ;; gravavel) echo 3 ;; nao_verificado) echo 2 ;; ausente) echo 1 ;; *) echo 0 ;;
esac; }
if [ "$(_rank "$POL_STATE")" -ge "$(_rank "$CAP_STATE")" ]; then MNG_STATE="$POL_STATE"; else MNG_STATE="$CAP_STATE"; fi
printf 'VEREDITO MANAGED_PROJECTION: %s (politica=%s capacidade=%s)\n' \
  "$(printf '%s' "$MNG_STATE" | tr '[:lower:]' '[:upper:]')" "$POL_STATE" "$CAP_STATE"

# ATIVACAO nao e observavel por verificador estatico: exige evento de runtime. O que este script
# pode dizer e se HA registro, nunca se o registro e completo - e o log e gravavel pelo ator
# (G39), entao ele e indicio, nao prova.
ATV="${TOLLENS_ACTIVATION_LOG:-/var/log/tollens-activation.jsonl}"
printf '\nATIVACAO:\n'
if [ -s "$ATV" ]; then
  # `grep -c ... || echo 0` emitia AS DUAS saidas quando a contagem era zero: `grep` imprime `0` e
  # SAI 1, entao o `||` acrescentava outro `0` e a linha saia quebrada em duas - justo no caso que
  # ela existe para reportar. `|| true` preserva a contagem e descarta so o status.
  _n="$(grep -c '"t":"Managed"' "$ATV" 2>/dev/null || true)"; _n="${_n:-0}"
  printf '  INDICIO   %s evento(s) Managed em %s\n' "$_n" "$ATV"
  printf '  LIMITE    o log e %s - o ator governado pode forja-lo (G39). Indicio, nao prova.\n' "$(_posse "$ATV")"
else
  printf '  NAO VERIFICADO  sem registro de ativacao em %s\n' "$ATV"
fi
# ONDA 29 (issue #39, A6/A8). O EVENTO NAO DISCRIMINA ESCOPO: o log so registra que ALGUM
# componente `Managed` carregou, nunca QUAL. Afirmar ativacao para agents/skills/hooks a partir
# dele seria amplitude maior que a medida sustenta - a mesma classe que
# docs/architecture/managed-capabilities.pt.md:16 ja declara para o par INSTALLED/ACTIVATED.
printf 'VEREDITO RUNTIME_ACTIVATION: '
if [ -s "$ATV" ] && [ "${_n:-0}" -gt 0 ]; then
  printf 'CLAUDE.md managed = INDICIO DE ATIVACAO (%s evento(s), nao prova); ' "$_n"
  echo '.claude/agents, .claude/skills e os hooks managed = NAO VERIFICADO (o evento nao discrimina escopo).'
else
  echo "NAO VERIFICADO (sem registro de ativacao em $ATV)"
fi

# O CODIGO DE SAIDA NOMEIA O ESCOPO, e nao so o veredito. Quem chama este script cuida de UM
# escopo: `apply.sh` instala a projecao de usuario e nada mais; o hook de sessao audita managed com
# um verificador proprio. Um unico "nao-zero" para tres causas obriga o chamador a adivinhar de
# quem e a falha - e foi assim que a falha de um escopo derrubou o instalador do outro.
#   0  as duas projecoes integras, politica /opt medida e conforme
#   1  projecao de USUARIO divergente        (do instalador de usuario, e propagavel)
#   2  NAO VERIFICADO: um escopo que DECIDE (politica /opt, capacidade em /etc) nao pode ser
#      medido aqui, com o motivo impresso acima (issue #39, criterio 3 - o agregado nao afirma
#      "governado" sobre o que nao mediu)
#   3  usuario integra, managed AUSENTE      (fase nao implantada; exige root, nao e do apply.sh)
#   4  usuario integra, managed GRAVAVEL     (implantada e reescrivivel: imposicao nao se sustenta)
#   5  usuario integra, managed DIVERGENTE    (politica e/ou capacidade != fonte canonica)
printf '\nGOVERNANCA GLOBAL: '
if [ $((DRIFT+MISSING+EXTRA)) -ne 0 ]; then
  echo "DIVERGENTE - a projecao de usuario nao e o que o repositorio declara."; exit 1
fi
case "$MNG_STATE" in
  divergente)
    echo "DIVERGENTE - o escopo managed em vigor (politica e/ou capacidade) nao e o que o repositorio declara."
    exit 5 ;;
  gravavel)
    echo "NAO IMPOSTO - projecao de usuario integra, mas o escopo managed e gravavel pelo ator."
    exit 4 ;;
  nao_verificado)
    echo "NAO VERIFICADO - projecao de usuario integra; o escopo que decide (managed) nao pode ser medido aqui."
    exit 2 ;;
  ausente)
    echo "PARCIAL - projecao de usuario integra; fase managed nao implantada (exige root, ADR 0026)."
    exit 3 ;;
  *)
    echo "governed=managed (projecao de usuario integra; politica /opt e capacidade root-owned medidas e conformes; ativacao com indicio, nao prova)"
    exit 0 ;;
esac
