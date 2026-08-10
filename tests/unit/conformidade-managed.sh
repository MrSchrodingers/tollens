#!/usr/bin/env bash
# CONFORMIDADE DE DOIS ESCOPOS.
#
# Defeito medido em 2026-08-10, numa maquina com o deploy managed ATIVO: o banner de
# SessionStart dizia "48/49 ok | 1 divergentes" enquanto /opt/evidence-gate carregava DUAS
# divergencias que ninguem reportava. `install/verify.sh` le apenas $HOME/.claude; ele nao
# conhece a arvore root-owned. O instrumento que existe para responder "o que roda e o que o
# repositorio declara?" era cego para metade do que roda - e cego justamente para a metade que
# deveria ser a raiz de confianca.
#
# O verificador managed JA EXISTIA (`install/apply-managed.sh --verify`, exit 1 em drift) e JA
# detectava (`DIVERGE /opt/evidence-gate/hooks/verify-gate.sh`). Nao faltava mecanismo: faltava
# o hook chama-lo. Por isso os casos abaixo testam a INTEGRACAO (o hook invoca e reporta), e
# nao a deteccao - que `tests/unit/managed.sh` ja cobre com 65 assercoes.
#
# ESCOPO DESTE ARQUIVO: a logica do hook. Os verificadores sao stubs deterministicos, para que
# um caso vermelho aqui signifique "o hook nao integrou", e nunca "o verificador mudou".
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. "$(dirname "$0")/../lib/lock.sh"
HOOK="$PWD/control/hooks/session-integrity.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# Monta um repo falso: verify.sh (escopo de usuario) e apply-managed.sh (escopo managed), cada
# um com exit code controlado por variavel. Assim cada combinacao dos dois escopos e exercitada.
monta(){ # $1=dir  $2=rc_user  $3=rc_managed
  local d="$1"
  mkdir -p "$d/install"
  cat > "$d/install/verify.sh" <<EOF
#!/usr/bin/env bash
echo "conformidade: 49/49 ok | $([ "$2" -eq 0 ] && echo 0 || echo 1) divergentes | 0 ausentes | 0 orfaos"
[ "$2" -ne 0 ] && echo "  DIVERGE   hooks/exemplo.sh                           (instalado != manifesto)"
exit $2
EOF
  cat > "$d/install/apply-managed.sh" <<EOF
#!/usr/bin/env bash
echo "managed: 30 componentes | $([ "$3" -eq 0 ] && echo 0 || echo 2) divergentes | 0 com dono errado | 0 gravaveis pelo ator"
[ "$3" -ne 0 ] && echo "  DIVERGE  /opt/evidence-gate/hooks/verify-gate.sh"
exit $3
EOF
  chmod +x "$d/install/verify.sh" "$d/install/apply-managed.sh"
  : > "$d/install/manifest.lock"
}

# Roda o hook com HOME e prefixo managed isolados. Devolve o additionalContext (vazio = calou).
roda(){ # $1=repo  $2=home  $3=managed_prefix
  printf '{"hook_event_name":"SessionStart"}' \
    | EVIDENCE_GATE_REPO="$1" HOME="$2" MANAGED_PREFIX="$3" bash "$HOOK" 2>/dev/null \
    | jq -r '.hookSpecificOutput.additionalContext // ""' 2>/dev/null
}

echo "== CM1. escopo managed divergente com escopo de usuario CONFORME =="
# O caso central. Antes desta correcao o hook saia 0 calado na linha 47 (`[ "$RC" -eq 0 ] && exit 0`)
# e a divergencia da arvore root-owned nunca chegava ao modelo.
R="$TMP/r1"; H="$TMP/h1"; PFX="$TMP/p1"; monta "$R" 0 1; mkdir -p "$H/.claude" "$PFX/opt/evidence-gate"
OUT="$(roda "$R" "$H" "$PFX")"
[ -n "$OUT" ]; chk "hook NAO se cala quando so o escopo managed diverge" $? 0
printf '%s' "$OUT" | grep -q "^managed:"; chk "  o resumo managed chega ao modelo" $? 0
printf '%s' "$OUT" | grep -q "verify-gate.sh"; chk "  o componente divergente e nomeado" $? 0

echo "== CM2. heartbeat registra os DOIS escopos =="
# Sem isto, a prova de liveness cobre so metade: um managed morto seria indistinguivel de um
# managed conforme, que e exatamente o modo de falha que este arquivo existe para fechar.
HBF="$H/.claude/evidence/session-integrity.jsonl"
[ -f "$HBF" ]; chk "heartbeat escrito" $? 0
[ "$(jq -r '.managed // "AUSENTE"' "$HBF" | tail -1)" = "drift" ]; chk "  heartbeat marca managed=drift" $? 0
[ "$(jq -r '.result' "$HBF" | tail -1)" = "drift" ]; chk "  resultado agregado e drift" $? 0

echo "== CM3. ausencia de deploy managed NAO vira falso positivo =="
# Maquina sem fase managed e o caso comum. Reportar drift ali seria o falso positivo que faz o
# operador desligar o mecanismo - o proprio motivo pelo qual este hook nao bloqueia a sessao.
R="$TMP/r2"; H="$TMP/h2"; PFX="$TMP/p2"; monta "$R" 0 1; mkdir -p "$H/.claude" "$PFX"
OUT="$(roda "$R" "$H" "$PFX")"
[ -z "$OUT" ]; chk "sem arvore managed, hook fica calado" $? 0
[ "$(jq -r '.managed' "$H/.claude/evidence/session-integrity.jsonl" | tail -1)" = "absent" ]
chk "  heartbeat distingue 'absent' de 'conformant'" $? 0

echo "== CM4. regressao: escopo de usuario divergente continua reportando =="
R="$TMP/r3"; H="$TMP/h3"; PFX="$TMP/p3"; monta "$R" 1 0; mkdir -p "$H/.claude" "$PFX/opt/evidence-gate"
OUT="$(roda "$R" "$H" "$PFX")"
printf '%s' "$OUT" | grep -q "^conformidade:"; chk "resumo do escopo de usuario preservado" $? 0

echo "== CM5. os DOIS divergentes: nenhum resumo engole o outro =="
R="$TMP/r4"; H="$TMP/h4"; PFX="$TMP/p4"; monta "$R" 1 1; mkdir -p "$H/.claude" "$PFX/opt/evidence-gate"
OUT="$(roda "$R" "$H" "$PFX")"
printf '%s' "$OUT" | grep -q "^conformidade:"; chk "resumo de usuario presente" $? 0
printf '%s' "$OUT" | grep -q "^managed:"; chk "resumo managed presente" $? 0

echo "== CM6. tudo conforme: silencio (higiene de contexto) =="
R="$TMP/r5"; H="$TMP/h5"; PFX="$TMP/p5"; monta "$R" 0 0; mkdir -p "$H/.claude" "$PFX/opt/evidence-gate"
OUT="$(roda "$R" "$H" "$PFX")"
[ -z "$OUT" ]; chk "nenhum ruido quando os dois escopos conferem" $? 0
[ "$(jq -r '.managed' "$H/.claude/evidence/session-integrity.jsonl" | tail -1)" = "conformant" ]
chk "  heartbeat prova que a verificacao managed RODOU (liveness)" $? 0

echo "== CM7. politica VIVA com a arvore APAGADA e o pior drift, nao 'absent' =="
# Achado critico da revisao independente. O verificador julga DUAS metades; a guarda testava
# UMA. Estado real: SIGKILL entre os dois renames (documentado em apply-managed-legacy.sh:254),
# ou `rm -rf /opt/evidence-gate`. Com allowManagedHooksOnly=true e o mecanismo inteiro desligado
# apontando para caminhos inexistentes - e era reportado como conformidade silenciosa.
R="$TMP/r6"; H="$TMP/h6"; PFX="$TMP/p6"; monta "$R" 0 1; mkdir -p "$H/.claude" "$PFX/etc/claude-code"
echo '{}' > "$PFX/etc/claude-code/managed-settings.json"   # politica presente, arvore NAO
OUT="$(roda "$R" "$H" "$PFX")"
[ -n "$OUT" ]; chk "politica orfa (sem arvore) NAO passa por 'absent'" $? 0
[ "$(jq -r '.managed' "$H/.claude/evidence/session-integrity.jsonl" | tail -1)" = "drift" ]
chk "  heartbeat marca drift, nao absent" $? 0

echo "== CM8. recusa de verificar e NOT_VERIFIED, nao divergencia medida =="
# `apply-managed.sh` sai 2/64/77/78 quando RECUSA verificar. Coagir isso para `drift` produzia
# um alerta afirmando divergencia com resumo verde e zero evidencia - alerta sem referente.
R="$TMP/r7"; H="$TMP/h7"; PFX="$TMP/p7"; monta "$R" 0 0; mkdir -p "$H/.claude" "$PFX/opt/evidence-gate"
cat > "$R/install/apply-managed.sh" <<'EOF'
#!/usr/bin/env bash
echo "ERRO: fonte privilegiada nao confiavel: /home/x/evidence-gate" >&2
exit 78
EOF
chmod +x "$R/install/apply-managed.sh"
OUT="$(roda "$R" "$H" "$PFX")"
[ "$(jq -r '.managed' "$H/.claude/evidence/session-integrity.jsonl" | tail -1)" = "not_verified" ]
chk "estado e not_verified (nao drift)" $? 0
[ "$(jq -r '.result' "$H/.claude/evidence/session-integrity.jsonl" | tail -1)" = "not_verified" ]
chk "  agregado tambem e not_verified" $? 0
printf '%s' "$OUT" | grep -q "NAO VERIFICADO"; chk "  a mensagem declara NAO VERIFICADO" $? 0
printf '%s' "$OUT" | grep -q "fonte privilegiada nao confiavel"; chk "  a CAUSA chega ao modelo" $? 0

echo "== CM9. verificador sem bit de execucao ainda e verificado (e chamado com bash) =="
# Guarda `-x` sobre arquivo invocado com `bash` era fail-open: um cp sem -p desligava tudo.
R="$TMP/r8"; H="$TMP/h8"; PFX="$TMP/p8"; monta "$R" 0 1; mkdir -p "$H/.claude" "$PFX/opt/evidence-gate"
chmod -x "$R/install/apply-managed.sh" "$R/install/verify.sh"
OUT="$(roda "$R" "$H" "$PFX")"
[ -n "$OUT" ]; chk "sem bit +x, a verificacao NAO e pulada em silencio" $? 0
[ "$(jq -r '.managed' "$H/.claude/evidence/session-integrity.jsonl" | tail -1)" = "drift" ]
chk "  o drift real continua sendo reportado" $? 0

echo
echo "================ PASS=$P  FAIL=$F ================"
# CONTAGEM INVARIANTE (README secao 6.2): matcher quebrado ou bloco nao executado nao pode
# reduzir cobertura em silencio.
EXPECTED=21
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "conformidade de dois escopos verde" || echo "conformidade de dois escopos VERMELHA"
exit "$F"
