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

# `pipefail` LOCAL, e nao herdado. O `tar -c | tar -x` abaixo tem um modo de falha silencioso:
# um arquivo ilegivel no meio da arvore faz o produtor sair !=0 mas escrever um TAR VALIDO; o
# consumidor sai 0 e a copia fica incompleta. Sem `pipefail` o `if !` le so o ultimo comando.
# Os 13 arneses atuais definem `pipefail` antes do source - conferido - mas depender disso e
# pre-condicao NAO DECLARADA de biblioteca: o proximo chamador que esquecer rebaixa a garantia.
set -o pipefail

if [ "${TOLLENS_ARENA:-on}" = "off" ]; then
  echo "AVISO: TOLLENS_ARENA=off - o arnes vai mutar a ARVORE DE TRABALHO." >&2
  echo "  Qualquer leitura concorrente observara o mutante. Use so para depuracao." >&2
else
  # VARREDURA POR DONO VIVO, e a versao anterior desta funcao ERA UM DEFEITO CRITICO.
  #
  # Ela removia arenas com `-mmin +60`, sob a justificativa escrita de que "nunca remove arena em
  # uso, porque nenhum arnes roda por uma hora". O codigo nao checava nada disso, e o relogio
  # mentia: `tar -xf -` extrai o membro `./` e aplica o MTIME DA RAIZ DA ARVORE FONTE sobre o
  # diretorio destino, sobrescrevendo o que `mktemp -d` acabou de criar. Medido:
  #
  #   mktemp criou:  2026-08-17 12:12:52  modo=700
  #   apos tar:      2026-08-14 11:32:04  modo=755   <- tres dias de idade no instante zero
  #   casaria com -mmin +60?  SIM
  #
  # Consequencia reproduzida por revisao independente: a varredura apagou a arena de um processo
  # VIVO (cwd confirmado por /proc), e o arnes morreu com `FAIL regressao baseline vermelha`,
  # exit 1. Isto e o INCIDENTE 4 do cabecalho deste mesmo arquivo - vermelho plausivel e falso -
  # recriado pela correcao que existe para elimina-lo.
  #
  # O modo dual e igualmente ruim: qualquer `git checkout` na raiz torna o mtime recente, o
  # `-mmin +60` nunca casa, e as arenas acumulam a ~14 MB cada, para sempre.
  #
  # A correcao troca o relogio por PROPRIEDADE: cada arena registra o pid do dono, e a varredura
  # so remove arena cujo dono nao existe mais. `kill -0` nao envia sinal, so testa existencia.
  for _a in "${TMPDIR:-/tmp}"/tollens-arena.*/; do
    [ -d "$_a" ] || continue
    _dono="$(cat "$_a/.arena-pid" 2>/dev/null)"
    # Sem marca de dono: arena de uma versao anterior desta lib. Removivel por idade, e aqui o
    # relogio serve, porque nao ha processo a proteger.
    if [ -z "$_dono" ]; then
      [ -n "$(find "$_a" -maxdepth 0 -mmin +60 2>/dev/null)" ] && rm -rf "$_a" 2>/dev/null
      continue
    fi
    kill -0 "$_dono" 2>/dev/null && continue   # dono VIVO: nao toca
    rm -rf "$_a" 2>/dev/null
  done

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

  # OS ALVOS DE MUTACAO CHEGARAM? O contador acima nao responde isso, e revisao independente
  # apontou: a fonte tem ~309 arquivos nao-.git, entao o limiar 150 tolera perder ~40% da arvore -
  # inclusive justamente os arquivos que os arneses mutam. O que hoje cobre esse buraco e o
  # baseline de cada arnes (todos os 13 tem um, conferido), que fica vermelho sem o alvo. Mas
  # isso e protecao de OUTRO mecanismo, e o comentario anterior a creditava a este portao.
  #
  # A lista e DERIVADA dos proprios arneses, nao escrita a mao: uma lista literal envelheceria em
  # silencio no dia em que um arnes mudasse de alvo.
  _arena_faltando=""
  for _t in $(grep -hoE '^(ORIG|ORIG_M|SRC)="[^"]+"' "$_arena_dst"/tests/mutation/*.sh 2>/dev/null \
              | cut -d'"' -f2 | sort -u); do
    [ -e "$_arena_dst/$_t" ] || _arena_faltando="$_arena_faltando $_t"
  done
  if [ -n "$_arena_faltando" ]; then
    echo "ERRO: arena sem alvo(s) de mutacao:$_arena_faltando" >&2
    rm -rf "$_arena_dst"
    exit 2
  fi

  # DESFAZ O QUE O `tar` FEZ COM O DIRETORIO-RAIZ. Ele aplicou o mtime e o modo da raiz da arvore
  # fonte sobre o destino: 755 num $TMPDIR que aqui e /tmp com sticky 1777, e uma data que faz a
  # varredura antiga apagar a arena no instante zero (ver o bloco de varredura acima).
  #   - `touch`: o mtime volta a ser o da CRIACAO, que e o unico que significa alguma coisa.
  #   - `chmod 700`: a arena e copia integral do repositorio, `.git` incluso. Em /tmp 1777 sem
  #     isso ela fica legivel por qualquer usuario local enquanto existir.
  touch "$_arena_dst" 2>/dev/null || true
  chmod 700 "$_arena_dst" 2>/dev/null || true

  # MARCA DE DONO. A varredura acima decide por existencia de processo, nao por relogio.
  printf '%s\n' "$$" > "$_arena_dst/.arena-pid" 2>/dev/null || true

  # ATRIBUICAO ARENA-PARA-PID, publicada FORA da arena. `tests/unit/arnes-de-mutacao.sh` precisa
  # saber qual arena pertence ao filho que ele lancou. Antes ele adivinhava com
  # `ls -dt .../tollens-arena.* | head -1`, e revisao independente reproduziu dois modos de falha:
  # observar arena ALHEIA ja mutada (falso positivo, com as assercoes seguintes passando por
  # vacuidade) e travar em arena alheia ILEGIVEL de outro usuario (inanicao). Agravado porque,
  # com o mtime corrompido pelo tar, todas as arenas do mesmo repo empatavam e o `ls -dt`
  # degenerava para ordem alfabetica.
  printf '%s\n' "$_arena_dst" > "${TMPDIR:-/tmp}/tollens-arena-of.$$" 2>/dev/null || true

  export TOLLENS_ARENA_DIR="$_arena_dst"
  cd "$_arena_dst" || exit 1
  unset _arena_src _arena_dst _arena_n _a _dono
fi
