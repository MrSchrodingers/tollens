#!/usr/bin/env bash
set -euo pipefail
if ! command -v jq >/dev/null 2>&1; then echo 'Bloqueado: artifact-discipline requer jq.' >&2; exit 2; fi
INPUT="$(cat)"
printf '%s' "$INPUT" | jq -e . >/dev/null 2>&1 || { echo 'Bloqueado: input JSON inválido.' >&2; exit 2; }
CONTENT="$(printf '%s' "$INPUT" | jq -r '(.tool_input.content // empty),(.tool_input.new_string // empty),(.tool_input.edits[]?.new_string // empty),(.tool_input.new_source // empty)')"
FILE_PATH="$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')"
EMOJI='[\x{1F300}-\x{1FAFF}\x{2600}-\x{27BF}\x{2B00}-\x{2BFF}\x{1F000}-\x{1F2FF}\x{1F1E6}-\x{1F1FF}\x{FE0F}]'
# LOCALE PINADO E ERRO TRATADO COMO BLOQUEIO. Defeito medido na onda 15, no primeiro teste que
# este hook teve em toda a sua existencia:
#
#   $ LC_ALL=C grep -P '[\x{1F300}-...]'
#   grep: character code point value in \x{} or \o{} is too large      -> rc=2
#
# A linha anterior era `grep -P "$EMOJI" >/dev/null 2>&1 && { bloqueia; }`. Em `A && B`, rc=2
# (ERRO) e indistinguivel de rc=1 (NAO ACHOU): o `&&` nao dispara, o hook sai 0 e o emoji PASSA.
# O `2>&1` engolia ate a mensagem do grep. `scripts/status.sh` exporta `LC_ALL=C`, entao a
# garantia que CLAUDE.md secao 8 declara estava desligada em todo processo que herdasse esse
# ambiente - silenciosamente, e sem teste algum que pudesse acusar.
#
# Duas correcoes, e a segunda importa mais que a primeira: pinar um locale UTF-8 conserta o caso
# conhecido; tratar "nao consegui verificar" como BLOQUEIO conserta a classe. Portao que nao
# consegue checar nao pode responder "limpo".
_EMOJI_LOCALE=C.UTF-8
locale -a 2>/dev/null | grep -qiE '^C\.utf-?8$' || _EMOJI_LOCALE=en_US.UTF-8
# `|| _rc=$?` NAO E ESTILO: com `set -euo pipefail` na linha 2, um pipeline que sai 1 (grep sem
# casar) ENCERRA o hook antes do `case`. A primeira versao desta correcao caiu exatamente nisso -
# o hook passou a morrer com rc=1 em todo conteudo limpo, e quatro casos da suite acusaram. Em
# lista `A || B`, o `set -e` nao dispara sobre A.
_rc=0
printf '%s' "$CONTENT" | LC_ALL="$_EMOJI_LOCALE" grep -qP "$EMOJI" 2>/dev/null || _rc=$?
case "$_rc" in
  0) echo 'Bloqueado: emojis não permitidos.' >&2; exit 2 ;;
  1) : ;;
  *) echo "Bloqueado (fail-closed): nao foi possivel verificar emoji - grep -P indisponivel ou locale sem UTF-8 (LC_ALL=$_EMOJI_LOCALE)." >&2; exit 2 ;;
esac
case "$FILE_PATH" in *.fable-allowed|*/verify-cmd-approved) echo 'Bloqueado: sentinela de autorização só pode ser criado pelo usuário.' >&2; exit 2;; */.claude/*) exit 0;; esac
LEXICO='seco seco|bora seco|voltagem maxima|voltagem máxima|modo overclock|lata velha|youtuber de extremo sucesso|programador de extremo sucesso|agente de extremo sucesso|otima observacao|ótima observação|excelente observacao|excelente observação|voce esta absolutamente certo|você está absolutamente certo|voce tem toda razao|você tem toda razão'
# Mesmo tratamento do emoji: o padrao e ASCII e nao depende de locale, mas a ESTRUTURA
# `grep && bloqueia` e a mesma, e foi ela - nao o padrao - que produziu o fail-open acima.
_rc=0
printf '%s' "$CONTENT" | grep -qiE "$LEXICO" 2>/dev/null || _rc=$?
case "$_rc" in
  0) echo 'Bloqueado: léxico de hype/persona não deve vazar.' >&2; exit 2 ;;
  1) : ;;
  *) echo 'Bloqueado (fail-closed): nao foi possivel verificar o lexico.' >&2; exit 2 ;;
esac
exit 0
