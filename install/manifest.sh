#!/usr/bin/env bash
# Gera o manifesto do estado DESEJADO: para cada componente, origem no repo, destino em
# ~/.claude e digest sha256. Sem manifesto nao existe "instalar" nem "conferir" - existe copiar,
# e copia diverge em silencio. Foi o que aconteceu: 32 componentes ativos, 12 versionados.
#
# Formato (TSV): tipo <TAB> origem <TAB> destino <TAB> sha256
set -uo pipefail
# LC_ALL=C em toda ordenacao: o digest de diretorio dependia do locale. Sob en_US.UTF-8,
# `SKILL.md` ordena DEPOIS de `references/`; sob C, antes. Duas maquinas com locales diferentes
# produziam identidades diferentes para o MESMO conteudo. Encontrado pela CI, nao pela suite
# local - que roda no mesmo locale e por construcao nao podia ver.
export LC_ALL=C

# LOCK DAS SUITES, adquirido aqui a partir da onda 10. REPRODUZIDO, nao inferido:
#
#   bash scripts/status.sh &                        # roda os arneses de mutacao
#   bash install/manifest.sh install/manifest.lock  # no mesmo instante
#   -> o manifesto gravou 819065d7... para evidence/hooks/verify-gate.sh
#   -> o arquivo em repouso e 486427303d... (identico ao de main, nunca editado nesta onda)
#
# Os arneses de `tests/mutation/` mutam arquivos de PRODUCAO no lugar e restauram no `trap`.
# Gerar o manifesto durante essa janela grava o digest do MUTANTE como estado desejado do
# sistema. Isso e pior que uma suite vermelha: e uma DECLARACAO falsa de qual codigo deve
# existir, escrita no arquivo que todo o resto usa como referencia.
#
# O caso foi pego pelo portao do deploy - `apply-managed.sh` comparou o stage contra o manifesto,
# achou 3 divergentes e abortou SEM tocar em /opt/tollens. O portao funcionou. Mas depender do
# portao para pegar um manifesto envenenado e depender do ultimo elo; a corrida se impede aqui.
#
# `flock -n` FALHA RAPIDO com exit 3, mesma decisao de tests/lib/lock.sh: esperar serializaria e
# as duas execucoes passariam, e absorcao silenciosa de corrida e exatamente o que este
# repositorio nao faz. Em CI os passos sao sequenciais e nao ha contencao.
#
# LACUNA DECLARADA: se `tests/lib/lock.sh` nao existir no contexto de execucao (copia reduzida do
# repositorio), este script segue sem lock e AVISA em stderr. Nesse caso a unica protecao volta a
# ser o portao do deploy. Nao se silencia a diferenca entre "protegido" e "desprotegido".
_MANIFEST_LOCK="$(cd "$(dirname "${BASH_SOURCE[0]}")/../tests/lib" 2>/dev/null && pwd -P)/lock.sh"
if [ -r "$_MANIFEST_LOCK" ]; then
  . "$_MANIFEST_LOCK"
else
  echo "AVISO: tests/lib/lock.sh ausente - manifesto gerado SEM lock." >&2
  echo "  Uma execucao concorrente de tests/mutation/* pode gravar o digest de um mutante." >&2
fi
cd "$(dirname "$0")/.." || exit 1
OUT="${1:-install/manifest.lock}"

# ESCRITA SO NO SUCESSO. O bloco gerador termina em `} > "$OUT"`, e o shell abre e TRUNCA o
# destino ao ENTRAR no grupo - antes de qualquer linha ser produzida. A primeira versao do portao
# de `config` fazia `exit 1` DENTRO desse grupo com a mensagem "o manifesto nao sera gravado
# incompleto", e a mensagem era falsa: medido em copia isolada, o arquivo ia de 52 para 51 linhas
# com `grep -c '^config'` = 0. Um manifesto TRUNCADO no disco e pior que nenhum, porque
# `install/apply.sh:35` so testa `[ -f "$MAN" ]` e nao confere exit code: o componente ausente
# vira "removido do manifesto" e a convergencia apaga o arquivo vivo correspondente. Achado do
# portao final; a acao destrutiva ficava desacoplada no tempo do erro que a causou.
#
# Agora o grupo escreve num temporario e o destino so e tocado se ele terminar inteiro. Nao uso
# `mv` porque `$OUT` pode ser `/dev/null` (ensaio), e renomear por cima de um device e outro
# problema. LIMITE: `cat >` nao e atomico contra leitor concorrente; a serializacao vem do lock
# das suites, adquirido acima.
_MTMP="$(mktemp "${TMPDIR:-/tmp}/tollens-manifest.XXXXXX")" || exit 1
trap 'rm -f "$_MTMP"' EXIT

emit(){ # $1=tipo $2=origem $3=destino
  [ -e "$1" ] 2>/dev/null
  local d
  if [ -d "$2" ]; then
    # diretorio (skill): digest do conteudo ordenado, para detectar qualquer alteracao interna
    # caminho NORMALIZADO (relativo a raiz do diretorio) para que o digest do repositorio e o
    # do instalado sejam comparaveis contra o MESMO valor do manifesto. Antes, verify.sh tinha
    # de recalcular a origem e comparava instalado<->working tree, deixando o manifesto de fora.
    d="$(cd "$2" && find . -type f -exec sha256sum {} + 2>/dev/null | LC_ALL=C sort -k2 | sha256sum | cut -c1-64)"
  else
    d="$(sha256sum "$2" 2>/dev/null | cut -c1-64)"
  fi
  printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$d"
}

{
  printf '# tollens manifest - estado DESEJADO de ~/.claude\n'
  printf '# gerado por install/manifest.sh; conferido por install/verify.sh\n'
  printf '# tipo\torigem\tdestino\tsha256\n'
  for f in control/hooks/*.sh execution/hooks/*.sh evidence/hooks/*.sh; do
    [ -f "$f" ] || continue; emit hook "$f" "hooks/$(basename "$f")"
  done
  for f in execution/agents/*.md; do
    [ -f "$f" ] || continue; emit agent "$f" "agents/$(basename "$f")"
  done
  for d in execution/skills/promoted/*/; do
    [ -d "$d" ] || continue; emit skill "${d%/}" "skills/$(basename "${d%/}")"
  done
  for f in execution/adapters/code/*.json; do
    [ -f "$f" ] || continue; emit adapter "$f" "tollens/adapters/code/$(basename "$f")"
  done
  for f in execution/adapters/documents/*.json; do
    [ -f "$f" ] || continue; emit adapter "$f" "tollens/adapters/documents/$(basename "$f")"
  done
  for f in execution/document-tools/*; do
    [ -f "$f" ] || continue; emit doctool "$f" "tollens/document-tools/$(basename "$f")"
  done
  # ONDA 12. O CLAUDE.md e o texto de MAIOR autoridade do harness - suas regras sobrepoem o
  # comportamento default - e era o unico fora do portao de conformidade. A consequencia foi
  # medida, nao temida: oito referencias vivas citavam secoes dele por numero, e a numeracao ja
  # tinha mudado sob todas (tres apontavam para secao inexistente, cinco resolviam para secao que
  # diz outra coisa). Nenhum portao podia ver, porque o referente nao estava no repositorio.
  #
  # A copia foi SEMEADA byte-exata do arquivo vivo, para que o primeiro `apply.sh` seja no-op
  # comprovado e nao um clobber silencioso da config do operador.
  #
  # CONSEQUENCIA OPERACIONAL, e ela muda o fluxo de quem edita: a partir daqui, editar
  # `~/.claude/CLAUDE.md` no lugar aparece como DIVERGE em `install/verify.sh`, e o proximo
  # `apply.sh` SOBRESCREVE essa edicao. O caminho passa a ser: editar aqui, depois aplicar.
  # FALHA ALTO SE SUMIR, e a razao e uma cadeia medida na revisao: com `[ -f ] || continue` (o
  # idioma dos globs acima, que ali esta certo porque glob vazio e legitimo), o arquivo sumir
  # tiraria o componente do manifesto EM SILENCIO. Ai `install/apply.sh` compara o manifesto novo
  # com `managed-files.lock`, ve `CLAUDE.md` como componente removido, e a convergencia executa
  # `rm -rf "$DEST/CLAUDE.md"` - apagando a config viva do operador por causa de um arquivo
  # faltando no repo. Aqui o alvo e UM caminho conhecido, nao um glob: ausencia e defeito.
  if [ -f execution/config/CLAUDE.md ]; then
    emit config execution/config/CLAUDE.md "CLAUDE.md"
  else
    echo "ERRO: execution/config/CLAUDE.md ausente - o destino nao sera tocado." >&2
    exit 1
  fi
} > "$_MTMP"

cat "$_MTMP" > "$OUT" || exit 1

n=$(grep -vc '^#' "$OUT")
echo "manifesto: $OUT  ($n componentes)"
awk -F'\t' '!/^#/{c[$1]++} END{for(t in c) printf "  %-8s %s\n", t, c[t]}' "$OUT"
