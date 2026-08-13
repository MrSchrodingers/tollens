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
# A TOLERANCIA VALE SO PARA O `.gitignore` VERSIONADO.
#
# `git check-ignore` honra tres fontes: `.gitignore` (versionado), `.git/info/exclude` e
# `core.excludesFile` global. As duas ultimas NAO sao versionadas e nao aparecem em diff nenhum -
# entao a versao anterior desta funcao podia ser neutralizada por um canal que nenhum revisor ve.
# Medido: `echo "payload/" >> .git/info/exclude` fazia o teste inteiro passar (exit 0) com um
# diretorio nao declarado na raiz. Achado do portao final.
#
# `-v` reporta a FONTE da regra que casou; exigir que seja `.gitignore` fecha os outros dois
# canais sem perder a correcao do falso positivo, porque o que se quer tolerar - residuo de
# ferramenta - esta declarado no arquivo versionado, onde a decisao e revisavel.
ignorado(){
  [ "$(git check-ignore -v -- "$1" 2>/dev/null | cut -d: -f1)" = ".gitignore" ]
}
# MASCARA DO RUNTIME, e nao entrada do repositorio. Medido em 2026-08-12: rodando dentro do
# Claude Code, `find` na raiz devolve `.mcp.json` como CHARACTER SPECIAL FILE, dono nobody:nobody,
# dispositivo 1,3 - e /proc/self/mountinfo confirma um bind mount read-only de `devtmpfs /null`
# sobre esse caminho. Nove entradas nesta arvore estao nessa condicao (`.mcp.json` e oito sob
# `.claude/`), parte de 176 mascaras que o runtime aplica a arquivos de configuracao e credencial
# no namespace de mount da sessao. Elas nao existem em disco e somem com a sessao.
#
# Sem esta clausula a suite dava FALSO VERMELHO para qualquer pessoa que a rodasse de dentro do
# Claude Code - foi o que aconteceu aqui, e ainda arrastou junto `evidence/cobertura.sh`, que se
# recusa (corretamente) a medir cobertura sobre um oraculo ja vermelho.
#
# NAO E AFROUXAMENTO, e o motivo e estrutural: o git so versiona arquivo regular, symlink e
# gitlink. Um character device NAO PODE ser conteudo commitado - `git add` o recusa. Logo esta
# clausula nao cria caminho para esconder nada; ela ignora exatamente a classe de entrada que o
# teste jamais poderia ter a ver. Diretorio e arquivo regular seguem valendo integralmente.
#
# O TIPO OSCILA, e por isso o predicado nao pode ser so o tipo. Medido em 2026-08-12: o mesmo
# caminho mascarado apareceu como `character special file / nobody:nobody / 666` numa leitura e
# como `regular empty file / ti:ti / 444` minutos depois, sem nada ter mudado no repositorio.
# Uma execucao desta suite reprovou nesse intervalo e a seguinte passou - falha intermitente num
# portao de higiene, que este repositorio nao normaliza como "as vezes acontece".
#
# O discriminante ESTAVEL nao e o tipo: e ser um PONTO DE MONTAGEM. A mascara existe porque o
# runtime monta algo sobre o caminho no namespace da sessao; o que a montagem expoe (devtmpfs
# /null, bind ro do proprio arquivo) varia, a montagem nao. As tres condicoes sao exigidas em
# CONJUNTO para nao abrir buraco: montado, NAO rastreado pelo git, e sem conteudo.
mascara_de_runtime(){
  # PARENTESES DELIBERADOS. `A || B && C` associa a esquerda em bash: `(A || B) && C`, que aqui
  # por acaso produz o comportamento certo. Auditoria de 2026-08-12 apontou que o codigo lia como
  # disjuncao onde o comentario prometia conjuncao. Funciona por precedencia, nao por intencao
  # escrita - e a proxima edicao quebra em silencio. Explicitar custa dois caracteres.
  if [ -c "$1" ] || [ -b "$1" ]; then return 0; fi
  local abs; abs="$(cd "$(dirname -- "$1")" 2>/dev/null && pwd -P)/$(basename -- "$1")" || return 1
  grep -qF " $abs " /proc/self/mountinfo 2>/dev/null || return 1
  git ls-files --error-unmatch -- "$1" >/dev/null 2>&1 && return 1   # rastreado: nunca e mascara
  [ -s "$1" ] && return 1                                            # tem conteudo: nao e mascara
  return 0
}
while IFS= read -r entry; do
  if ! [[ "$entry" =~ $allowed_root ]]; then
    if ignorado "$entry"; then continue; fi
    if mascara_de_runtime "$entry"; then
      echo "  ignorado (mascara do runtime, nao versionavel): $entry"
      continue
    fi
    echo "FAIL entrada nao declarada na raiz: $entry"
    fail=1
  fi
done < <(find . -maxdepth 1 -mindepth 1 -printf '%f\n' | sort)

if [[ "$fail" -ne 0 ]]; then
  exit 1
fi

echo "PASS higiene do repositorio"
