#!/usr/bin/env bash
# Suite do MOTOR DE DECISAO do roteador interno de modelos (claude-plugins/plugins/tollens-router).
# Os casos vivem em tests/unit/router-engine.test.mjs (node:test, sem dependencia externa); este
# arquivo existe para o agregador tests/unit/run.sh, que despacha por disco apenas *.sh e *.py.
#
# Sem Node 20 ou superior, ou sem Object.hasOwn, structuredClone e node:test, a suite NAO PODE ser
# executada aqui: sai 2 (NAO VERIFICADO), nunca 0.
#
# PINO DE CONTAGEM: apagar um caso (ou o arquivo de teste inteiro) manteria `node --test` verde. A
# contagem esperada e literal e declarada aqui; qualquer outra contagem reprova (exit 1). Ao
# acrescentar ou remover um caso, atualize CASOS_ESPERADOS na mesma mudanca.
#
# Os mutantes do engine rodam a parte: node claude-plugins/plugins/tollens-router/tests/mutants.mjs
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"

CASOS_ESPERADOS=26

if ! command -v node >/dev/null 2>&1; then
  echo "  DEPENDENCIA AUSENTE: node. Estado: NAO VERIFICADO - a suite nao rodou."
  exit 2
fi
MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$MAJOR" -lt 20 ]; then
  echo "  NODE $MAJOR < 20. Estado: NAO VERIFICADO - a suite nao rodou."
  exit 2
fi
if ! node -e 'process.exit(typeof Object.hasOwn === "function" && typeof structuredClone === "function" && typeof require("node:test") === "function" ? 0 : 1)' 2>/dev/null; then
  echo "  Node sem Object.hasOwn, structuredClone ou node:test. Estado: NAO VERIFICADO - a suite nao rodou."
  exit 2
fi

SAIDA="$(node --test --test-reporter=tap tests/unit/router-engine.test.mjs 2>&1)"
rc=$?
printf '%s\n' "$SAIDA"
[ "$rc" -eq 0 ] || exit "$rc"
N="$(printf '%s\n' "$SAIDA" | sed -n 's/^# tests \([0-9][0-9]*\)$/\1/p' | tail -1)"
if [ "$N" != "$CASOS_ESPERADOS" ]; then
  echo "CONTAGEM INESPERADA: casos=${N:-?}, esperado $CASOS_ESPERADOS. Caso removido ou acrescentado sem atualizar este pino."
  exit 1
fi
exit 0
