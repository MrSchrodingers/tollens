#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

fail=0

for path in \
  logitech-flow-kvm package.json quebrado.py servico.js solto.py \
  .bootstrap .bootstrap-trigger .materialize-trigger \
  .github/workflows/materialize-multiruntime.yml \
  .github/workflows/export-source.yml; do
  if [[ -e "$path" ]]; then
    echo "FAIL legado/transport temporario presente: $path"
    fail=1
  fi
done

allowed_root='^(\.agents|\.claude|\.claude-plugin|\.codex|\.git|\.github|\.gitignore|AGENTS\.md|CLAUDE\.md|CONTRIBUTING\.md|LICENSE|README\.md|README\.pt-BR\.md|SECURITY\.md|control|docs|evidence|execution|install|orchestration|scripts|tests)$'
# RESIDUO IGNORADO PELO GIT NAO E ENTRADA NAO DECLARADA.
#
# Este laco varre o FILESYSTEM, nao o indice do git. Ate 2026-08-10 ele reprovava em
# `.mypy_cache` e `.ruff_cache` - que o proprio `.gitignore` deste repo declara nas linhas 7-8.
# Consequencia medida: qualquer maquina que tivesse rodado a suite (ruff cria o cache) nao
# conseguia mais rodar este teste. Na CI passava por ORDEM, nao por desenho: `runtime-ports`
# roda antes dos casos que invocam ruff. Verde por acidente de sequencia e o modo de falha que
# este repositorio existe para nao ter.
#
# A intencao original permanece intacta: os arquivos-lixo da lista acima (`quebrado.py`,
# `solto.py`, `servico.js`, gatilhos de transporte) NAO estao no `.gitignore` e continuam
# reprovando. O que passa a ser tolerado e exclusivamente o que o repositorio ja declarou
# como residuo de ferramenta.
ignorado(){ git check-ignore -q -- "$1" 2>/dev/null; }
while IFS= read -r entry; do
  if ! [[ "$entry" =~ $allowed_root ]]; then
    if ignorado "$entry"; then continue; fi
    echo "FAIL entrada nao declarada na raiz: $entry"
    fail=1
  fi
done < <(find . -maxdepth 1 -mindepth 1 -printf '%f\n' | sort)

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "PASS higiene do repositorio"
