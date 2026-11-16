#!/usr/bin/env bash
# Roda a suite tests/unit/model-honor.sh contra UM mutante do hook e acrescenta uma linha
# `<ID> rc=<rc> <casos vermelhos>` ao arquivo de resultado. Uso: um.sh <m_ID.sh> <arquivo_de_resultado>
# Lock proprio por mutante (TOLLENS_LOCK_FILE): permite rodar ate 4 em paralelo sem exit 3.
set -uo pipefail
f="${1:?uso: um.sh <mutante.sh> <resultado>}"; res="${2:?uso: um.sh <mutante.sh> <resultado>}"
n="$(basename "$f" .sh)"; n="${n#m_}"
cd "$(dirname "$0")/../../.." || exit 1
lk="$(dirname "$res")/lk-$n"
out="$(TOLLENS_LOCK_FILE="$lk" MODEL_HONOR_HOOK="$f" timeout 200 bash tests/unit/model-honor.sh 2>&1)"; rc=$?
echo "$n rc=$rc $(printf '%s' "$out" | grep -E '^  FAIL' | sed -E 's/^  FAIL  ([0-9]+) .*/\1/' | tr '\n' ',')" >> "$res"
