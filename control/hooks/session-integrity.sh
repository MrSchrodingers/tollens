#!/usr/bin/env bash
# PLANO DE CONTROLE - conformidade no inicio da sessao.  Hook: SessionStart.
#
# Existe porque o defeito mais grave encontrado neste projeto nao foi um bug de logica: foi a
# divergencia silenciosa entre o repositorio e a maquina. 32 componentes ativos, 12 versionados,
# um verify-gate uma versao atras - por meses, sem nenhum sinal. Nao havia quem comparasse.
#
# Este hook e o comparador. Ele nao corrige e nao bloqueia: declara, no primeiro turno, que o
# que esta rodando diverge do que o repositorio afirma. Bloquear a sessao por drift seria o
# falso positivo que faz o operador desligar o mecanismo.
#
# LIMITE DECLARADO: este hook vive em ~/.claude/hooks, que o ator governado pode escrever.
# Ele detecta drift acidental, nao adversario. Contra ator com intencao, a raiz de confianca
# precisa ser managed settings + launcher nao gravavel (docs/adr/0022, fase 2).
set -uo pipefail
command -v jq >/dev/null 2>&1 || exit 0
cat >/dev/null 2>&1 || true   # drena stdin

REPO="${TOLLENS_REPO:-$HOME/claude-mecanismo}"
[ -d "$REPO" ] || REPO="$HOME/tollens"
# `-f`, nao `-x`: a chamada e `bash install/verify.sh`. Exigir o bit de execucao numa guarda
# que a chamada nao exige e fail-open - perder o bit desligava o comparador em silencio.
[ -f "$REPO/install/verify.sh" ] || exit 0

OUT="$(cd "$REPO" && bash install/verify.sh 2>&1)"; RC=$?

# ONDA 22c. O EXIT DO VERIFICADOR NOMEIA O ESCOPO, e este hook so pode ler `RC` como veredito sobre
# a projecao de USUARIO. `install/verify.sh` devolve 3 quando a fase managed nao foi implantada e 4
# quando ela existe mas e gravavel pelo ator; nos dois casos a projecao de usuario esta INTEGRA.
# Ler qualquer nao-zero como drift de usuario faria este hook afirmar divergencia sobre um escopo
# que confere - o falso positivo que o comentario da secao managed, abaixo, existe para evitar.
URC=0; case "$RC" in 0|3|4) URC=0 ;; *) URC=1 ;; esac

# SEGUNDO ESCOPO - a arvore managed root-owned.
#
# `install/verify.sh` le apenas $HOME/.claude. Numa maquina com a fase managed ativa isso e
# METADE do que roda, e e a metade que deveria ser a raiz de confianca. Medido em 2026-08-10:
# o banner anunciava "48/49 ok | 1 divergentes" enquanto /opt/tollens carregava duas
# divergencias - entre elas o proprio verify-gate, uma versao atras. O comparador existia e
# acertava (`apply-managed.sh --verify`, exit 1); ninguem o chamava. Este hook e escrito para
# ser o comparador, e nao pode declarar conformidade sobre um escopo que nao olhou.
#
# `absent` NAO e `conformant`: maquina sem fase managed e o caso comum, e reportar drift ali
# seria o falso positivo que faz o operador desligar o mecanismo. Os tres estados sao distintos
# no heartbeat justamente para que "nao ha managed" nunca seja lido como "managed confere".
# A GUARDA E A UNIAO DOS ARTEFATOS JULGADOS, nao um deles. O verificador managed julga DUAS
# metades - a arvore em $OPT e a politica em managed-settings.json (apply-managed-worker.sh:249:
# "ActiveState = (arvore em $OPT, politica em $SETTINGS). AS DUAS metades"). Testar so a arvore
# fazia o PIOR drift possivel passar por benigno: com a politica viva e a arvore apagada - estado
# que o proprio worker documenta como resultado de SIGKILL entre os dois renames, e que `rm -rf`
# manual reproduz - o hook gravava `absent` e calava. Com allowManagedHooksOnly=true isso e o
# mecanismo inteiro desligado, apontando para caminhos inexistentes, reportado como conformidade.
#
# `-f` e nao `-x`: a chamada abaixo e `bash install/apply-managed.sh`, que nao precisa do bit de
# execucao. Exigir `-x` na guarda e depois nao precisar dele na chamada e fail-open silencioso -
# um `cp` sem `-p`, um tarball ou um FS sem modo POSIX desligava a verificacao inteira sem sinal.
# `MANAGED_PREFIX` e SEAM DE TESTE, nao configuracao. Ele desloca qual arvore e auditada, entao
# um valor errado (ou um `export` esquecido apos rodar tests/unit/managed.sh) faz o hook auditar
# uma arvore falsa e reportar conformidade sobre ela. Nao ha guarda possivel aqui - o hook vive
# no espaco do ator, que ja pode edita-lo - mas a fraude fica AUDITAVEL: o prefixo efetivo vai
# para o heartbeat em `managed_prefix`, abaixo. Silencio sobre qual arvore foi olhada seria o
# mesmo defeito que este arquivo corrige, um nivel acima.
MPFX="${MANAGED_PREFIX:-}"
MTREE="$MPFX/opt/tollens"
MSET="$MPFX/etc/claude-code/managed-settings.json"
MOUT=""; MRC=0; MSTATE="absent"
if { [ -d "$MTREE" ] || [ -f "$MSET" ]; } && [ -f "$REPO/install/apply-managed.sh" ]; then
  MOUT="$(cd "$REPO" && bash install/apply-managed.sh --verify 2>&1)"; MRC=$?
  # EXIT CODE MULTIVALORADO: `apply-managed.sh` sai 2 (legado ausente), 64 (uso invalido),
  # 77 (exige root) e 78 (fonte privilegiada nao confiavel) - todos RECUSA DE VERIFICAR, nao
  # divergencia medida. Coagir tudo que nao e 0 para `drift` publicava um alerta que AFIRMA
  # divergencia exibindo um resumo verde e zero evidencia. Lacuna e NOT_VERIFIED (CLAUDE.md).
  case "$MRC" in
    0) MSTATE="conformant" ;;
    1) MSTATE="drift" ;;
    *) MSTATE="not_verified" ;;
  esac
fi

# HEARTBEAT: silencio nao prova conformidade - prova apenas ausencia de mensagem. Este hook sai
# 0 calado em pelo menos seis cenarios (jq ausente, repo nao localizado, verify nao executavel,
# hook nao carregado, SessionStart removido, hook apagado). Sem registro observavel, "nao vi
# nada" e indistinguivel de "o mecanismo esta morto". O log e a prova de liveness; a ausencia
# de mensagem ao modelo e so higiene de contexto.
#
# LIMITE DA ALEGACAO: ha heartbeat em toda execucao do hook que ULTRAPASSA as precondicoes
# (jq presente, repo localizado, verify executavel). Nao ha heartbeat quando o hook nem chega
# a rodar - nao carregado, apagado, ou removido do settings. Portanto:
#   heartbeat presente  => o hook executou aquela verificacao
#   heartbeat ausente  =/=> drift  (pode ser observador morto)
# Detectar a ausencia do proprio observador exige autoridade externa: managed settings, ou
# `/hooks` e `--debug`. Fase 2.
HB="$HOME/.claude/evidence/session-integrity.jsonl"
mkdir -p "$(dirname "$HB")" 2>/dev/null || true
MANDIG="$(sha256sum "$REPO/install/manifest.lock" 2>/dev/null | cut -c1-16)"
jq -cn --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" \
       --arg r "$(if [ "$URC" -eq 0 ] && [ "$RC" -ne 4 ] && [ "$MRC" -eq 0 ]; then echo conformant
                  elif [ "$URC" -eq 0 ] && [ "$MSTATE" = not_verified ]; then echo not_verified
                  else echo drift; fi)" \
       --arg u "$([ "$URC" -eq 0 ] && echo conformant || echo drift)" \
       --arg vrc "$RC" \
       --arg g "$MSTATE" \
       --arg m "${MANDIG:-unknown}" --arg s "$(printf '%s' "$OUT" | grep -E '^(PROJECAO USUARIO|conformidade):' | head -1)" \
       --arg ms "$(printf '%s' "$MOUT" | grep -E '^managed:' | head -1)" \
       --arg mp "${MPFX:-/}" --arg mrc "$MRC" \
       '{ts:$t,event:"session_integrity",result:$r,user:$u,managed:$g,
         manifest_digest:$m,summary:$s,managed_summary:$ms,
         managed_prefix:$mp,managed_rc:$mrc,verify_rc:$vrc}' \
  >> "$HB" 2>/dev/null || true

# Silencio SO quando os dois escopos conferem. Um escopo conforme nao autoriza calar sobre o
# outro: era exatamente assim que a divergencia da arvore root-owned ficava invisivel.
# `RC` 4 - managed implantado e GRAVAVEL pelo ator - nunca cala: e o estado em que a imposicao
# nao se sustenta, e calar sobre ele seria reportar conformidade sobre a politica que o ator pode
# reescrever. `RC` 3 (fase nao implantada) cala como antes: e o caso comum e ja e reportado por
# `MSTATE=absent` no heartbeat.
[ "$URC" -eq 0 ] && [ "$RC" -ne 4 ] && [ "$MRC" -eq 0 ] && exit 0

# AS DUAS ETIQUETAS, e nao por indecisao: este hook roda de `~/.claude/hooks/` e chama o
# `install/verify.sh` de `$REPO`. Os dois arquivos vivem em arvores que PODEM estar em versoes
# diferentes - e a divergencia entre elas e justamente o que este hook existe para detectar.
# A onda 22 trocou `conformidade:` por `PROJECAO USUARIO:`; casar so com a nova faria o resumo
# ficar vazio contra um repo anterior, e casar so com a antiga o faz ficar vazio contra o atual -
# medido: `grep -c '^conformidade:'` devolve 0 na saida do verificador desta onda. Sonda que nao
# acha o caso positivo conhecido devolve vazio, e vazio le-se como "nada a relatar" (G45).
RESUMO="$(printf '%s' "$OUT" | grep -E '^(PROJECAO USUARIO|conformidade):' | head -1)"
DETALHE="$(printf '%s' "$OUT" | grep -E '^  (DIVERGE|AUSENTE|ORFAO)' | head -12)"
MRESUMO="$(printf '%s' "$MOUT" | grep -E '^managed:' | head -1)"
MDETALHE="$(printf '%s' "$MOUT" | grep -E '^  (DIVERGE|AUSENTE|ORFAO)' | head -8)"

# RECUSA DE VERIFICAR CARREGA A CAUSA. Os dois `grep` acima so casam o caminho em que o
# verificador chegou a COMPARAR. Nos codigos de recusa (2, 64, 77, 78) a explicacao existe em
# $MOUT e era descartada: o resultado era um alerta afirmando divergencia, com resumo verde e
# nenhuma evidencia. Um alerta sem referente e pior que silencio - ensina a ignorar o alerta.
if [ "$MSTATE" = "not_verified" ]; then
  MRESUMO="managed: NAO VERIFICADO - o verificador recusou verificar (exit $MRC)"
  MDETALHE="$(printf '%s' "$MOUT" | grep -E '^(ERRO|NOT_VERIFIED|uso:)' | head -4)"
  [ -z "$MDETALHE" ] && MDETALHE="$(printf '%s' "$MOUT" | head -3)"
fi

# O escopo managed so entra na mensagem quando ha o que dizer sobre ele. Numa maquina sem a
# fase managed as duas linhas ficam vazias e o texto e o de antes.
BLOCO_MANAGED=""
[ -n "$MRESUMO" ] && BLOCO_MANAGED="
$MRESUMO
$MDETALHE
Para reconciliar o escopo managed (exige root, e a arvore de origem precisa ser root:root -
ver docs/adr/0026): sudo bash \"$REPO\"/install/apply-managed.sh"

jq -cn --arg c "CONFORMIDADE - o que roda diverge do que o repositorio declara.

$RESUMO
$DETALHE$BLOCO_MANAGED

O estado instalado NAO e o estado versionado. Qualquer afirmacao sobre o comportamento do
harness baseada no repositorio esta, neste turno, sem referente verificado.
Para reconciliar: cd \"$REPO\" && bash install/apply.sh
Para inspecionar: cd \"$REPO\" && bash install/verify.sh" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$c}}' 2>/dev/null
exit 0
