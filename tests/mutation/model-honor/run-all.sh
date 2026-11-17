#!/usr/bin/env bash
# Gera os mutantes de evidence/hooks/model-honor.sh, roda a suite contra cada um e resume.
# Os mutantes vao para um diretorio temporario (removido ao sair); o ARQUIVO DE RESULTADO e
# gravado a cada mutante e NAO e removido, para sobreviver a timeout ou interrupcao (caminho
# impresso no inicio; MODEL_HONOR_MUT_RESULTADO o define; MODEL_HONOR_MUT_PARALELO e o numero de
# processos, padrao 2). Estados: morto (caso FAIL nomeado), vivo (rc 0), inconclusivo (rc != 0 sem
# caso nomeado). Exit 0 se todo nao equivalente morreu e nada ficou inconclusivo; 1 se algum nao
# equivalente sobreviveu; 2 se ha inconclusivo ou o instrumento falhou.
# Uso: cd "$(git rev-parse --show-toplevel)" && bash tests/mutation/model-honor/run-all.sh
set -uo pipefail
aqui="$(cd "$(dirname "$0")" && pwd)"
raiz="$(cd "$aqui/../../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
res="${MODEL_HONOR_MUT_RESULTADO:-${TMPDIR:-/tmp}/model-honor-mut.$$.txt}"
python3 -I "$aqui/gen.py" "$tmp" "$raiz/evidence/hooks/model-honor.sh" || exit 2
# Baseline: o hook intacto precisa passar na suite; se falhar, os "mortos" nao significam nada.
: > "$tmp/baseline.txt"
bash "$aqui/um.sh" "$raiz/evidence/hooks/model-honor.sh" "$tmp/baseline.txt" >/dev/null
grep -q ' rc=0 ' "$tmp/baseline.txt" || { echo "baseline (hook intacto) FALHOU: $(cat "$tmp/baseline.txt")" >&2; exit 2; }
: > "$res"; echo "resultado (parcial valido): $res"
ls "$tmp"/m_*.sh | xargs -P "${MODEL_HONOR_MUT_PARALELO:-2}" -I{} bash "$aqui/um.sh" {} "$res" >/dev/null
total="$(wc -l < "$res" | tr -d ' ')"
esperado="$(ls "$tmp"/m_*.sh | wc -l | tr -d ' ')"
[ "$total" -eq "$esperado" ] || { echo "instrumento: $total resultados para $esperado mutantes" >&2; exit 2; }
bash "$aqui/resumo.sh" "$res" "$tmp/equivalentes.txt"
