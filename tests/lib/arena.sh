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
  #
  # ONDA 12, ACHADO DE AUDITORIA - DESTRUICAO DE DIRETORIO ARBITRARIO. O glob abaixo terminava em
  # BARRA (`tollens-arena.*/`), e barra final faz `[ -d ]`, `find` e `rm -rf` ATRAVESSAREM
  # symlink. Como /tmp e 1777, qualquer usuario local criava
  # `/tmp/tollens-arena.pwn -> /home/ti/.claude` e a proxima execucao de QUALQUER um dos treze
  # arneses apagava o alvo: o link nao tem `.arena-pid`, entao `_dono` ficava vazio e o ramo por
  # idade removia o conteudo apontado. Reproduzido pelo auditor executando o bloco LITERAL deste
  # arquivo contra um symlink plantado: conteudo do alvo integralmente removido, exit 0.
  #
  # Tres guardas, e a ORDEM importa:
  #   - glob sem barra final, para que `-L` possa ver o link em vez de resolve-lo;
  #   - `-L` recusa symlink antes de qualquer teste que o siga;
  #   - dono tem de ser o usuario corrente. `stat` NAO dereferencia por padrao, o que aqui e
  #     desejado; nao troque por `stat -L`.
  # Com isso um atacante ate cria `/tmp/tollens-arena.X`, mas nao consegue que este laco remova
  # nada que ele nao possua - e o que ele possui, nos pulamos.
  for _a in "${TMPDIR:-/tmp}"/tollens-arena.*; do
    [ -L "$_a" ] && continue
    [ -d "$_a" ] || continue
    [ "$(stat -c '%u' "$_a" 2>/dev/null)" = "$(id -u)" ] || continue
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

  # MARCA DE EXECUCAO (nonce), quando quem lanca o arnes a fornece. Existe porque a primeira
  # tentativa de dar frescor a atribuicao era TAUTOLOGICA: o leitor comparava o pid do nome do
  # arquivo `arena-of.<pid>` com o `.arena-pid` da arena apontada - e a arena escreve o MESMO `$$`
  # nos dois, entao sob reuso de pid eles coincidem POR CONSTRUCAO. Uma guarda que nao pode falhar
  # no caso bom nem detectar o caso ruim e ruido com aparencia de rigor; o portao final reproduziu
  # o falso positivo sobrevivendo a ela.
  # O nonce nao deriva do pid, entao arena de execucao anterior nunca casa.
  if [ -n "${TOLLENS_ARENA_TAG:-}" ]; then
    printf '%s\n' "$TOLLENS_ARENA_TAG" > "$_arena_dst/.arena-tag" 2>/dev/null || true
  fi

  # ATRIBUICAO ARENA-PARA-PID, publicada FORA da arena. `tests/unit/arnes-de-mutacao.sh` precisa
  # saber qual arena pertence ao filho que ele lancou. Antes ele adivinhava com
  # `ls -dt .../tollens-arena.* | head -1`, e revisao independente reproduziu dois modos de falha:
  # observar arena ALHEIA ja mutada (falso positivo, com as assercoes seguintes passando por
  # vacuidade) e travar em arena alheia ILEGIVEL de outro usuario (inanicao). Agravado porque,
  # com o mtime corrompido pelo tar, todas as arenas do mesmo repo empatavam e o `ls -dt`
  # degenerava para ordem alfabetica.
  #
  # M1 (auditoria do PR #19, corrigido na onda 12). A atribuicao ia para
  # `${TMPDIR}/tollens-arena-of.$$` - em /tmp com sticky 1777, nome DETERMINISTICO pelo pid,
  # escrita com falha ENGOLIDA por `|| true` e leitura sem validacao alguma. Outro usuario local
  # podia pre-criar o caminho como symlink e (a) fazer a arena apontar para arvore que ele
  # controla, ou (b) usar a escrita para truncar arquivo alheio - o MESMO ataque que
  # `tests/lib/lock.sh:56-74` ja tinha sofrido e corrigido neste repositorio, apos auditoria, com
  # diretorio 0700 por usuario. A arena nao reusou o mecanismo que o repositorio ja tinha.
  #
  # NAO e fatal se falhar: quem precisa da atribuicao e apenas `tests/unit/arnes-de-mutacao.sh`,
  # e o leitor la ja e monotonico - atribuicao ausente vira NOT_VERIFIED, nunca passe vazio.
  # Matar os treze arneses por causa de um /tmp hostil seria trocar um risco por uma parada.
  # O predicado de diretorio 0700 vive em `tests/lib/tmpdir.sh`, fonte unica: duas copias de uma
  # checagem de seguranca divergem em silencio, e esta era literalmente uma copia da de
  # `tests/lib/lock.sh`. Onde mora a garantia, o porque de `stat` sem `-L` e o limite do pai
  # sticky estao documentados la, uma vez.
  _arena_ad=""
  if [ -r "$(dirname "${BASH_SOURCE[0]}")/tmpdir.sh" ]; then
    . "$(dirname "${BASH_SOURCE[0]}")/tmpdir.sh"
    _arena_ad="$(tollens_tmpdir_privado)" || _arena_ad=""
  fi
  if [ -z "$_arena_ad" ]; then
    echo "AVISO: '${TMPDIR:-/tmp}/tollens-$(id -u)' nao e diretorio 0700 do usuario corrente," >&2
    echo "       ou tests/lib/tmpdir.sh esta ausente - atribuicao de arena RECUSADA." >&2
    echo "       Casos que dependem dela reportarao NOT_VERIFIED." >&2
  elif [ -L "$_arena_ad/arena-of.$$" ]; then
    echo "AVISO: '$_arena_ad/arena-of.$$' e symlink - atribuicao RECUSADA." >&2
  elif ! printf '%s\n' "$_arena_dst" > "$_arena_ad/arena-of.$$"; then
    echo "AVISO: falha ao publicar a atribuicao em '$_arena_ad/arena-of.$$'." >&2
  else
    # COLETA. Ninguem removia estes arquivos - a varredura de cima so olha `tollens-arena.*`.
    # Medido na estacao durante a revisao: 3 atribuicoes vivas para 1 arena, mais 20+ residuos do
    # esquema antigo. O risco nao e espaco, e REUSO DE PID: uma atribuicao estagnada com o mesmo
    # pid faz o leitor apontar para arena alheia, que e o falso positivo que esta atribuicao
    # existe para eliminar. `kill -0` no pid do nome decide.
    for _f in "$_arena_ad"/arena-of.*; do
      [ -f "$_f" ] || continue
      _p="${_f##*.}"
      case "$_p" in *[!0-9]*|'') rm -f "$_f" 2>/dev/null; continue;; esac
      [ "$_p" = "$$" ] || kill -0 "$_p" 2>/dev/null || rm -f "$_f" 2>/dev/null
    done
    unset _f _p
  fi

  export TOLLENS_ARENA_DIR="$_arena_dst"
  cd "$_arena_dst" || exit 1
  unset _arena_src _arena_dst _arena_n _a _dono _arena_ad
fi
