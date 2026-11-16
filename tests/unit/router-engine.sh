#!/usr/bin/env bash
# Suite do MOTOR DE DECISAO do roteador interno de modelos (claude-plugins/plugins/tollens-router).
# Os casos vivem em tests/unit/router-engine.test.mjs (node:test, sem dependencia externa); este
# arquivo existe para o agregador tests/unit/run.sh, que despacha por disco apenas *.sh e *.py.
#
# Sem Node 22 ou superior a suite NAO PODE ser executada aqui: sai 2 (NAO VERIFICADO), nunca 0.
# Os mutantes do engine rodam a parte: node claude-plugins/plugins/tollens-router/tests/mutants.mjs
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"

if ! command -v node >/dev/null 2>&1; then
  echo "  DEPENDENCIA AUSENTE: node. Estado: NAO VERIFICADO - a suite nao rodou."
  exit 2
fi
MAJOR="$(node -p 'process.versions.node.split(".")[0]' 2>/dev/null || echo 0)"
if [ "$MAJOR" -lt 22 ]; then
  echo "  NODE $MAJOR < 22. Estado: NAO VERIFICADO - a suite nao rodou."
  exit 2
fi

node --test tests/unit/router-engine.test.mjs
exit $?
