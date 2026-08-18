#!/usr/bin/env bash
# DIRETORIO TEMPORARIO PRIVADO DO USUARIO - fonte unica do predicado de seguranca.
#
# POR QUE EXISTE. `tests/lib/lock.sh` e `tests/lib/arena.sh` computavam cada um o seu
# `${TMPDIR}/tollens-<uid>` e repetiam o mesmo bloco de validacao 0700. Duas revisoes
# independentes apontaram a mesma coisa: sao duas copias de uma checagem de SEGURANCA, e copias
# divergem em silencio. O repositorio ja proibe esse padrao em outro ponto - `install/apply.sh`
# registra que "duas copias da mesma lista divergiriam em silencio, e e o defeito central deste
# repositorio" - e ainda assim a arena imitou o lock em vez de reusa-lo.
#
# O QUE O PREDICADO GARANTE, e a atribuicao importa porque a primeira redacao a errou:
#
#   - O diretorio e 0700 e do usuario corrente. Isso e o que impede outro usuario local de criar
#     entradas la dentro - e portanto o que fecha a janela TOCTOU entre validar e escrever.
#   - `mkdir -p -m 700` NAO corrige diretorio PRE-EXISTENTE com modo frouxo (shellcheck SC2174,
#     verdadeiro e deliberado). Quem corrige e a checagem abaixo, que RECUSA em vez de seguir.
#     Medido sobre diretorio 0777 pre-criado: recusa.
#   - `stat` SEM `-L` e deliberado. Symlink reporta modo 777 proprio, entao um link plantado no
#     lugar do diretorio cai na recusa mesmo que aponte para um 0700 nosso. Nao "enderece" isto
#     para `stat -L`: reabre o furo.
#
# LIMITE DECLARADO: a garantia depende de o PAI ser sticky. Em `/tmp` (1777) o nao-dono nao
# consegue renomear nem remover o nosso diretorio. Com `TMPDIR` apontando para um diretorio
# world-writable SEM sticky, a janela volta a ser exploravel - aqui, no lock e na arena
# igualmente. Nao ha checagem do sticky do pai: seria mais uma copia de predicado, e o cenario
# pressupoe um ambiente que o processo ja nao controla.
#
# CONTRATO: `tollens_tmpdir_privado` ecoa o caminho e devolve 0 quando o diretorio e utilizavel;
# devolve 1 SEM ecoar nada quando recusa. Nao emite aviso - quem chama decide se a recusa e fatal
# (o lock segue sem protecao e avisa; a arena perde a atribuicao e o caso vira NOT_VERIFIED).

tollens_tmpdir_privado(){
  local d
  d="${TMPDIR:-/tmp}/tollens-$(id -u)"
  # shellcheck disable=SC2174
  mkdir -p -m 700 "$d" 2>/dev/null || true
  [ -d "$d" ] || return 1
  [ "$(stat -c '%u:%a' "$d" 2>/dev/null)" = "$(id -u):700" ] || return 1
  printf '%s\n' "$d"
}
