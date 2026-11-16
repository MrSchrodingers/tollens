#!/usr/bin/env bash
# Gera os mutantes de evidence/hooks/model-honor.sh, roda a suite contra cada um (4 em paralelo)
# e resume. Nada e escrito na arvore: tudo vai para um diretorio temporario. Exit 0 se todo
# mutante NAO equivalente morreu; 1 se algum sobreviveu; 2 se o instrumento falhou.
# Uso: cd "$(git rev-parse --show-toplevel)" && bash tests/mutation/model-honor/run-all.sh
set -uo pipefail
aqui="$(cd "$(dirname "$0")" && pwd)"
raiz="$(cd "$aqui/../../.." && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
python3 -I "$aqui/gen.py" "$tmp" "$raiz/evidence/hooks/model-honor.sh" || exit 2
: > "$tmp/resultado.txt"
ls "$tmp"/m_*.sh | xargs -P 4 -I{} bash "$aqui/um.sh" {} "$tmp/resultado.txt"
total="$(wc -l < "$tmp/resultado.txt" | tr -d ' ')"
esperado="$(ls "$tmp"/m_*.sh | wc -l | tr -d ' ')"
[ "$total" -eq "$esperado" ] || { echo "instrumento: $total resultados para $esperado mutantes" >&2; exit 2; }
vivos="$(grep ' rc=0' "$tmp/resultado.txt" | awk '{print $1}' | sort)"
mortos="$(grep -vc ' rc=0' "$tmp/resultado.txt")"
inesperados=""
for v in $vivos; do grep -qx "$v" "$tmp/equivalentes.txt" || inesperados="$inesperados $v"; done
echo "MORTOS=$mortos DE=$total"
echo "VIVOS: $(echo $vivos)"
echo "EQUIVALENTES DECLARADOS: $(tr '\n' ' ' < "$tmp/equivalentes.txt")"
[ -z "$inesperados" ] || { echo "SOBREVIVENTES NAO EQUIVALENTES:$inesperados"; exit 1; }
exit 0
