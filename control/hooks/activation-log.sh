#!/usr/bin/env bash
# REGISTRADOR DE ATIVACAO: o unico canal que responde "o runtime CARREGOU", e nao "esta instalado".
#
# POR QUE ESTE ARQUIVO EXISTE. Ate 2026-08-26 este registro era feito por programas `jq` EMBUTIDOS
# direto em /etc/claude-code/managed-settings.json, escritos a mao naquele arquivo e em nenhum
# outro lugar. Nao estavam em `install/hooks-spec.sh`, que e a FONTE UNICA da especificacao de
# hooks, nem em nenhum dos backups da politica. Consequencia medida no mesmo dia: uma execucao de
# `install/apply-managed.sh --enforce` - operacao NORMAL, publicada no README - regenerou a
# politica a partir da especificacao versionada e os apagou. Antes: 2 registradores. Depois: 0.
# O log parou (mtime 17:32 contra enforce as 17:34) sem uma linha de erro.
#
# Isso e exatamente o defeito que originou este repositorio, e o cabecalho de `hooks-spec.sh` o
# nomeia: componente ATIVO que nao esta VERSIONADO diverge em silencio. A agravante e que
# `install/verify.sh:114` publica `ATIVACAO: INDICIO N evento(s)` lendo este log - isto e, a
# afirmacao de governanca do repositorio dependia de um instrumento que o proprio repositorio
# destruia ao ser aplicado.
#
# LIMITE QUE NAO SE RESOLVE AQUI (G39): o log e gravavel pelo ator governado, entao ele e INDICIO
# de ativacao, nunca prova. `verify.sh` ja imprime esse limite junto do numero. Versionar o
# registrador corrige a fragilidade do INSTRUMENTO, nao a do canal.
#
# CONTRATO DE SAIDA. Este hook nunca escreve em stdout: em `PreToolUse` o stdout e interpretado
# pelo runtime e viraria injecao de contexto a cada chamada de ferramenta. E sai 0 sempre - um
# registrador que barra a ferramenta que ele so deveria observar seria pior que a ausencia dele.
# Falta de permissao no log nao e silenciada por conveniencia: ela aparece em `verify.sh` como
# "sem registro de ativacao", que e o estado correto a reportar.
set -uo pipefail
LOG="${TOLLENS_ACTIVATION_LOG:-/var/log/tollens-activation.jsonl}"
command -v jq >/dev/null 2>&1 || exit 0

IN="$(cat 2>/dev/null)"; [ -n "$IN" ] || exit 0

# O evento vem do proprio payload, nao de um argumento: um argumento errado no registro da politica
# faria este hook rotular todo evento com o nome de outro, e o log passaria a mentir com aparencia
# de completude. `hook_event_name` e o que o runtime declara.
printf '%s' "$IN" | jq -c '
  {ev: (.hook_event_name // "?"), s: (.session_id // "?")}
  + (if   .hook_event_name == "InstructionsLoaded" then {f: (.file_path // "?"), t: (.memory_type // "?")}
     elif .hook_event_name == "SubagentStart"      then {a: (.agent_type // "?")}
     elif .hook_event_name == "PreToolUse"         then {k: (.tool_input.skill // .tool_name // "?")}
     else {} end)' >> "$LOG" 2>/dev/null || true
exit 0
