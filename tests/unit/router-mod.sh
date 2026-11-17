#!/usr/bin/env bash
# Suite do MOD do roteador interno de modelos (claude-plugins/plugins/tollens-router/hooks, fatia R2).
# Os casos vivem em tests/unit/router-mod.test.mjs (node:test, `$` simulado em memoria); este arquivo existe
# para o agregador tests/unit/run.sh, que despacha por disco apenas *.sh e *.py.
#
# LIMITES DECLARADOS: `claude plugin test` nao roda onde allowManagedHooksOnly esta ativo, e esta suite nao
# carrega o mod numa sessao real: o carregamento pelo Claude Code NAO e verificado aqui. Quando o binario
# `claude` existe, `claude plugin validate` confere a analise estatica do modulo (hooks e chamadas que o
# Claude Code enxerga); sem ele, essa parte fica NAO VERIFICADA (aviso, sem reprovar).
#
# PINO DE CONTAGEM: apagar um caso manteria `node --test` verde. A contagem esperada e literal; ao
# acrescentar ou remover um caso, atualize CASOS_ESPERADOS na mesma mudanca.
#
# Mutantes do mod: nao ha arnes versionado; as mutacoes medidas na entrega estao descritas no relato da onda.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"

CASOS_ESPERADOS=13

if ! command -v node >/dev/null 2>&1; then
  echo "  DEPENDENCIA AUSENTE: node. Estado: NAO VERIFICADO - a suite nao rodou."
  exit 2
fi
MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$MAJOR" -lt 20 ]; then
  echo "  NODE $MAJOR < 20. Estado: NAO VERIFICADO - a suite nao rodou."
  exit 2
fi

SAIDA="$(node --test --test-reporter=tap tests/unit/router-mod.test.mjs 2>&1)"
rc=$?
printf '%s\n' "$SAIDA"
[ "$rc" -eq 0 ] || exit "$rc"
N="$(printf '%s\n' "$SAIDA" | sed -n 's/^# tests \([0-9][0-9]*\)$/\1/p' | tail -1)"
if [ "$N" != "$CASOS_ESPERADOS" ]; then
  echo "CONTAGEM INESPERADA: casos=${N:-?}, esperado $CASOS_ESPERADOS. Caso removido ou acrescentado sem atualizar este pino."
  exit 1
fi

if command -v claude >/dev/null 2>&1; then
  VAL="$(claude plugin validate claude-plugins/plugins/tollens-router 2>&1)"
  vrc=$?
  if [ "$vrc" -ne 0 ] || ! printf '%s\n' "$VAL" | grep -q 'hooks: tool.call.*agent.spawn.*session.measure'; then
    printf '%s\n' "$VAL"
    echo "claude plugin validate: reprovou ou nao enxergou os tres hooks (tool.call, agent.spawn, session.measure)."
    exit 1
  fi
  echo "claude plugin validate: ok (tool.call, agent.spawn, session.measure)"
else
  echo "  AVISO: binario claude ausente; analise estatica do modulo NAO VERIFICADA."
fi
exit 0
