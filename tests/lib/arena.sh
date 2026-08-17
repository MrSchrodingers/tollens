#!/usr/bin/env bash
# ARENA DE MUTACAO. Este arquivo e SOURCED por tests/mutation/*.sh, nunca executado direto.
#
# O QUE ELE RESOLVE, e o defeito e medido, nao inferido.
#
# Ate 2026-08-14 todo arnes de mutacao alterava um arquivo de PRODUCAO na ARVORE DE TRABALHO e o
# restaurava no `trap`. Restauracao e uma propriedade; isolamento e outra:
#
#     EventuallyRestored  NAO IMPLICA  NeverObservableAsMutant
#
# Durante a janela entre mutar e restaurar, QUALQUER coisa que leia a arvore observa o mutante e o
# trata como estado real. Seis incidentes distintos em dois dias decorreram disso, todos medidos:
#
#   1. `install/manifest.sh` gravou 819065d7 para evidence/hooks/verify-gate.sh; o arquivo em
#      repouso e 486427303d. O manifesto - documento que declara qual codigo DEVE existir -
#      passou a apontar para um mutante. O portao do deploy pegou (3 divergentes, abortou sem
#      tocar em /opt/tollens), mas depender do ultimo elo nao e desenho.
#   2. Nove blobs vazios de mascara de runtime entraram num commit por `git add` na janela errada.
#   3. `pkill` num arnes matou-o ANTES do trap: validate-claims.py e cobertura.sh ficaram mutados.
#   4. `scripts/status.sh --check` mediu `claims.sh 50 FAIL=1` sobre validate-literature.py mutado
#      por outra execucao - vermelho PLAUSIVEL e falso, que e pior que vermelho obvio.
#   5. github-ruleset.py mutado por job concorrente lancado sobreposto.
#   6. cobertura.sh mutado por job morto na tentativa anterior.
#
# Nenhum e defeito de logica. Todos decorrem de ONDE o experimento roda. E o agravante: o proprio
# `scripts/status.sh --check` executa os arneses, entao o verificador do documento de estado e ele
# mesmo um mutador de estado. No runner de CI isso e inofensivo (checkout descartavel, ninguem
# mais le); num diretorio de trabalho compartilhado com agentes e outras suites, nao e.
#
# COMO RESOLVE. Copia a arvore inteira para um diretorio temporario e faz `cd` para la. Os arneses
# usam caminhos RELATIVOS A RAIZ (`ORIG="evidence/hooks/verify-gate.sh"`, `REG="tests/unit/..."`),
# entao nada mais precisa mudar: eles passam a mutar a copia. A arvore candidata deixa de ser
# observavel como mutante mesmo se o arnes for morto por SIGKILL - nao ha o que restaurar, porque
# nada foi tocado.
#
# POR QUE COPIA E NAO `git worktree`. Tres razoes medidas:
#   - `git worktree add` materializa um COMMIT. A arvore de trabalho pode ter alteracao nao
#     commitada, e o arnes precisa testar o que esta ali, nao o que esta em HEAD.
#   - `.git/worktrees/<nome>/{commondir,config.worktree}` sao bind-montados pelo runtime nesta
#     estacao; `git worktree remove` devolve "Device or resource busy" e deixa 47 diretorios de
#     metadado orfaos - medido.
#   - `.git/config` fica read-only sob a politica managed, e `git worktree add` precisa escrever
#     nele. Medido: "could not lock config file .git/config".
#
# O QUE A COPIA INCLUI, e por que. `.git` VAI JUNTO: suites deste repositorio usam `git
# check-ignore`, `git ls-files` e `git status` (tests/unit/repository-hygiene.sh, entre outras), e
# uma arena sem `.git` faria essas suites reprovarem por ausencia de ambiente, nao por defeito -
# falso vermelho, que e o que este arquivo existe para nao produzir.
#
# EXCLUSOES, cada uma com razao:
#   .git/worktrees  - bind mounts do runtime; `cp` falha com "Device or resource busy"
#   .claude/worktrees - arvores de subagente, podem ser grandes e nao participam de teste nenhum
#   __pycache__, .ruff_cache, .mypy_cache - residuo regeneravel
#
# LIMITE DECLARADO, e ele importa: a arena isola a ARVORE, nao o SISTEMA. Um arnes que escreva em
# `~/.claude`, `/opt/tollens` ou `/etc` continua escapando. Nenhum dos 13 arneses atuais faz isso
# (conferido por grep), mas o proximo pode - e a arena nao o impedira.
#
# Desativar com TOLLENS_ARENA=off, exclusivamente para depuracao. Nesse caso o arnes volta a mutar
# a arvore de trabalho, e o aviso sai em stderr: nao se silencia a diferenca entre isolado e nao.

if [ "${TOLLENS_ARENA:-on}" = "off" ]; then
  echo "AVISO: TOLLENS_ARENA=off - o arnes vai mutar a ARVORE DE TRABALHO." >&2
  echo "  Qualquer leitura concorrente observara o mutante. Use so para depuracao." >&2
else
  # VARREDURA NA ENTRADA. O `trap EXIT` de cada arnes e definido DEPOIS deste source e SOBRESCREVE
  # o que fosse registrado aqui - entao a arena nao se limpa sozinha ao sair. Em vez de editar os
  # treze arneses para acumular trap (invasivo e faceis de esquecer), a limpeza e por varredura de
  # arenas velhas: uma execucao nova remove as de mais de uma hora. Auto-limitante, e nunca remove
  # arena em uso, porque nenhum arnes deste repo roda por uma hora (o mais longo mede ~4 min).
  find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'tollens-arena.*' -type d -mmin +60 \
       -exec rm -rf {} + 2>/dev/null || true

  _arena_src="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)" || exit 1
  _arena_dst="$(mktemp -d "${TMPDIR:-/tmp}/tollens-arena.XXXXXXXX")" || exit 1

  # `tar` em vez de `cp -a`: preserva modo e link, e o `--exclude` age no caminho relativo, o que
  # `cp` nao oferece sem construir a lista a mao. O pipe falha alto - arena incompleta produziria
  # reprovacao por ausencia de arquivo, indistinguivel de defeito real.
  if ! ( cd "$_arena_src" && tar -cf - \
            --exclude='./.git/worktrees' \
            --exclude='./.claude/worktrees' \
            --exclude='*/__pycache__' \
            --exclude='./.ruff_cache' \
            --exclude='./.mypy_cache' \
            . 2>/dev/null ) | ( cd "$_arena_dst" && tar -xf - 2>/dev/null ); then
    echo "ERRO: nao foi possivel montar a arena de mutacao em $_arena_dst" >&2
    rm -rf "$_arena_dst"
    exit 2
  fi

  # PORTAO DE INTEGRIDADE. Arena vazia ou parcial faria todo mutante "morrer" por ausencia de
  # arquivo, e o arnes reportaria verde perfeito medindo nada - o falso verde mais caro possivel.
  _arena_n="$(find "$_arena_dst" -type f -not -path '*/.git/*' | wc -l)"
  if [ "$_arena_n" -lt 150 ]; then
    echo "ERRO: arena com $_arena_n arquivos (esperado >=150) - copia incompleta." >&2
    rm -rf "$_arena_dst"
    exit 2
  fi

  # O `trap` de EXIT dos arneses e definido DEPOIS deste source e sobrescreve o daqui. Por isso a
  # remocao vai por `TOLLENS_ARENA_DIR`, que os arneses nao tocam, e o diretorio fica sob $TMPDIR:
  # mesmo que nada limpe, e temporario por construcao e nao suja o repositorio.
  export TOLLENS_ARENA_DIR="$_arena_dst"
  cd "$_arena_dst" || exit 1
fi
