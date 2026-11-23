#!/usr/bin/env bash
# ESCOPOS DE install/verify.sh - issue #39.
#
# CAUSA MEDIDA (investigacao da issue #39): o agregado de `install/verify.sh` publicava
# `governed=managed` a partir de QUATRO alvos fixos sob `$MGD_DIR` (o equivalente de
# `/etc/claude-code`), sem nunca ler `/opt/tollens` - a arvore que DECIDE sob
# `allowManagedHooksOnly=true`. Alem disso, `.claude/agents` e `.claude/skills` so tinham
# teste de POSSE (nenhuma comparacao de conteudo), e uma falha de leitura (`sha256sum` sem
# permissao) caia no mesmo ramo de uma divergencia de conteudo real - a mesma medida negativa
# tratada como medida positiva.
#
# ESTA SUITE PROVA, com fixture (nao com o estado da estacao onde roda):
#   VE1/VE1b  conteudo de capacidade (.claude/agents) e comparado, e so diverge quando difere de
#             fato (antivacuidade: conteudo identico nao acusa DIVERGE);
#   VE2       a arvore de POLITICA (/opt) e lida - duas fixturas iguais em tudo, exceto a
#             politica, produzem vereditos DIFERENTES, e a desatualizada nomeia o hook;
#   VE3       politica que nao pode ser medida (delegado ausente) sai NAO VERIFICADO, nunca
#             DIVERGE, e o agregado se recusa a dizer "governado";
#   VE4       os tres vereditos por escopo aparecem nomeados, e a linha que
#             `control/hooks/session-integrity.sh` casa por regex continua existindo;
#   VE5       rc=1 (usuario diverge) e rc=2 (nao foi possivel medir) continuam distintos;
#   VE6       alvo de capacidade ILEGIVEL sai NAO VERIFICADO, nunca DIVERGE.
#
# NENHUM caso le `/opt/tollens` ou `/etc/claude-code` reais: toda fixture usa `TOLLENS_MANAGED_DIR`
# e `MANAGED_PREFIX`, os dois seams que `install/verify.sh` e `install/apply-managed.sh` ja
# aceitam (o segundo, nativamente).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

command -v jq >/dev/null 2>&1 || { echo "NAO VERIFICADO: jq ausente (exigido por apply-managed.sh)." >&2; exit 2; }

T="$(mktemp -d)"; trap 'chmod -R u+rwx "$T" 2>/dev/null; rm -rf "$T"' EXIT

# --- fixture de CAPACIDADE (equivalente a /etc/claude-code): CLAUDE.md + settings + agents/skills
mk_cap(){ # $1=dir  $2=sim|nao (sabota .claude/agents/refutador.md)
  mkdir -p "$1/.claude"
  cp -f execution/config/CLAUDE.md "$1/CLAUDE.md"
  : > "$1/managed-settings.json"
  rm -rf "$1/.claude/agents" "$1/.claude/skills"
  cp -a execution/agents "$1/.claude/agents"
  cp -a execution/skills "$1/.claude/skills"
  [ "${2:-nao}" = sim ] && printf '\nLINHA INTRODUZIDA PELO TESTE (VE1)\n' >> "$1/.claude/agents/refutador.md"
  return 0
}
# --- fixture de POLITICA (equivalente a /opt/tollens + managed-settings.json): deploy real do
# instalador managed sob prefixo de ensaio, para nao reimplementar o layout a mao.
mk_pol(){ MANAGED_PREFIX="$1" bash install/apply-managed.sh >/dev/null 2>&1; }

# --- projecao de USUARIO integra, construida pelo proprio instalador (nunca a mao)
DU="$T/home"; CLAUDE_HOME="$DU" bash install/apply.sh >/dev/null 2>&1
# nada implantado em nenhum dos dois escopos managed - usado para ISOLAR o escopo sob teste
MGD0="$T/mgd-vazio"; POL0="$T/pol-vazio"

CLAUDE_HOME="$DU" TOLLENS_MANAGED_DIR="$MGD0" MANAGED_PREFIX="$POL0" bash install/verify.sh >/dev/null 2>&1
chk "precondicao: usuario integro, managed ausente (os dois escopos) => rc=3" "$?" 3

echo "== VE1. capacidade (.claude/agents) divergente e reprovada POR CONTEUDO, nomeada =="
CAP_DIV="$T/cap-div"; mk_cap "$CAP_DIV" sim
OUT1="$(CLAUDE_HOME="$DU" TOLLENS_MANAGED_DIR="$CAP_DIV" MANAGED_PREFIX="$POL0" bash install/verify.sh 2>&1)"; RC1=$?
chk "VE1 nomeia DIVERGE em .claude/agents" \
    "$(printf '%s' "$OUT1" | grep -cE '^  DIVERGE +\.claude/agents')" 1
chk "VE1 rc=5 (managed divergente)" "$RC1" 5

echo "== VE1b. antivacuidade: conteudo identico NAO produz DIVERGE =="
CAP_OK="$T/cap-ok"; mk_cap "$CAP_OK" nao
OUT1B="$(CLAUDE_HOME="$DU" TOLLENS_MANAGED_DIR="$CAP_OK" MANAGED_PREFIX="$POL0" bash install/verify.sh 2>&1)"; RC1B=$?
chk "VE1b sem DIVERGE quando o conteudo confere" \
    "$(printf '%s' "$OUT1B" | grep -cE '^  DIVERGE')" 0
chk "VE1b ainda reprova a posse (rc=4, fixture nao-root)" "$RC1B" 4

echo "== VE2. escopo de POLITICA (/opt): duas fixturas iguais, exceto a politica, distinguem =="
POL_OK="$T/pol-ok"; mk_pol "$POL_OK"
POL_STALE="$T/pol-stale"; cp -a "$POL_OK" "$POL_STALE"
printf '\n# VERSAO ANTIGA (ONDA ANTERIOR)\n' >> "$POL_STALE/opt/tollens/hooks/graphify-scout-mode.sh"
A="$(CLAUDE_HOME="$DU" TOLLENS_MANAGED_DIR="$CAP_OK" MANAGED_PREFIX="$POL_OK"    bash install/verify.sh 2>&1)"; RCA=$?
B="$(CLAUDE_HOME="$DU" TOLLENS_MANAGED_DIR="$CAP_OK" MANAGED_PREFIX="$POL_STALE" bash install/verify.sh 2>&1)"; RCB=$?
chk "VE2 politica CONFORME: rc=4 (so a capacidade nao-root pesa)" "$RCA" 4
chk "VE2 politica DESATUALIZADA: rc=5 (a politica decide, mais severa)" "$RCB" 5
chk "VE2 a politica desatualizada e NOMEADA na saida" \
    "$([ "$(printf '%s' "$B" | grep -c 'graphify-scout-mode')" -gt 0 ] && echo sim || echo nao)" sim
chk "VE2 a politica conforme NAO acusa a politica" \
    "$(printf '%s' "$A" | grep -c 'DIVERGE.*opt/tollens')" 0

echo "== VE3. politica que o delegado recusa medir: NAO VERIFICADO, nunca DIVERGE =="
POL_OK2="$T/pol-ok2"; mk_pol "$POL_OK2"
C="$(CLAUDE_HOME="$DU" TOLLENS_MANAGED_DIR="$MGD0" MANAGED_PREFIX="$POL_OK2" \
     TOLLENS_MANAGED_WORKER="$T/worker-inexistente.sh" bash install/verify.sh 2>&1)"; RCC=$?
chk "VE3 imprime NAO VERIFICADO para a politica, com motivo" \
    "$([ "$(printf '%s' "$C" | grep -cE 'NAO VERIFICADO.*opt/tollens')" -gt 0 ] && echo sim || echo nao)" sim
chk "VE3 nunca imprime DIVERGE para a politica nesse caso" \
    "$(printf '%s' "$C" | grep -c 'DIVERGE.*opt/tollens')" 0
chk "VE3 o agregado NAO diz governado" "$([ "$RCC" -ne 0 ] && echo sim || echo nao)" sim
chk "VE3 rc=2 (NAO VERIFICADO), distinto de AUSENTE(3) e DIVERGENTE(5)" "$RCC" 2

echo "== VE4. os TRES vereditos nomeados aparecem, e a linha que session-integrity.sh casa segue unica =="
chk "VE4 publica os tres escopos nomeados" \
    "$(printf '%s' "$OUT1B" | grep -cE '^VEREDITO (USER_PROJECTION|MANAGED_PROJECTION|RUNTIME_ACTIVATION):')" 3
chk "VE4 'PROJECAO USUARIO:' continua com exatamente 1 casamento (CI9)" \
    "$(printf '%s' "$OUT1B" | grep -cE '^(PROJECAO USUARIO|conformidade):')" 1

echo "== VE5. regressao dos codigos: 1 (usuario) e 2 (nao verificado) seguem distintos =="
DX="$T/home-drift"; cp -a "$DU" "$DX"
_ESPECIME="$(find "$DX" -type f -name '*.sh' | head -1)"
[ -n "$_ESPECIME" ] && printf '\nDRIFT INTRODUZIDO PELO TESTE\n' >> "$_ESPECIME"
CLAUDE_HOME="$DX" TOLLENS_MANAGED_DIR="$MGD0" MANAGED_PREFIX="$POL0" bash install/verify.sh >/dev/null 2>&1
chk "VE5 divergencia de USUARIO continua rc=1" "$?" 1
bash install/verify.sh "$T/manifesto-inexistente.lock" >/dev/null 2>&1
chk "VE5 manifesto ausente continua rc=2 (NAO VERIFICADO)" "$?" 2

echo "== VE6. alvo de capacidade ILEGIVEL sai NAO VERIFICADO, nunca DIVERGE (F8) =="
CAP_ILEG="$T/cap-ilegivel"; mk_cap "$CAP_ILEG" nao
chmod 000 "$CAP_ILEG/CLAUDE.md"
OUT6="$(CLAUDE_HOME="$DU" TOLLENS_MANAGED_DIR="$CAP_ILEG" MANAGED_PREFIX="$POL0" bash install/verify.sh 2>&1)"
chmod 644 "$CAP_ILEG/CLAUDE.md"
chk "VE6 imprime NAO VERIFICADO para CLAUDE.md ilegivel" \
    "$(printf '%s' "$OUT6" | grep -cE '^  NAO VERIFICADO[[:space:]]+CLAUDE\.md')" 1
chk "VE6 jamais imprime DIVERGE para CLAUDE.md nesse caso" \
    "$(printf '%s' "$OUT6" | grep -cE '^  DIVERGE +CLAUDE\.md')" 0

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=19
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "verify-escopos verde ($P/$EXPECTED)" || echo "verify-escopos VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
