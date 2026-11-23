#!/usr/bin/env bash
# Resume o arquivo de resultado dos mutantes (uma linha `<ID> rc=<rc> <casos vermelhos>` por mutante).
# Uso: resumo.sh <resultado> <equivalentes>
#   morto         rc != 0 E pelo menos um caso FAIL nomeado
#   vivo          rc = 0
#   inconclusivo  rc != 0 SEM caso nomeado (timeout 124, CONTAGEM INESPERADA, dependencia ausente)
# Imprime `MUTANTE <ID> <estado> casos=<...>[ EQUIVALENTE]` por mutante, depois
# `MORTOS=<n> DE=<total> INCONCLUSIVOS=<k>`. Exit 2 se houver inconclusivo, 1 se algum mutante
# NAO equivalente estiver vivo, 0 caso contrario (precedencia 2 > 1 > 0).
set -uo pipefail
res="${1:?uso: resumo.sh <resultado> <equivalentes>}"; eq="${2:?uso: resumo.sh <resultado> <equivalentes>}"
mortos=0; total=0; inconc=0; vivos_ne=0
while read -r nome rc casos; do
  [ -n "$nome" ] || continue
  total=$((total + 1))
  if [ "$rc" = "rc=0" ]; then estado=vivo
  elif [ -n "${casos:-}" ]; then estado=morto; mortos=$((mortos + 1))
  else estado=inconclusivo; inconc=$((inconc + 1)); fi
  marca=""
  if grep -qx "$nome" "$eq"; then marca=" EQUIVALENTE"; elif [ "$estado" = vivo ]; then vivos_ne=$((vivos_ne + 1)); fi
  echo "MUTANTE $nome $estado casos=${casos:--}$marca"
done < <(LC_ALL=C sort "$res")
echo "MORTOS=$mortos DE=$total INCONCLUSIVOS=$inconc"
[ "$inconc" -eq 0 ] || exit 2
[ "$vivos_ne" -eq 0 ] || exit 1
exit 0
