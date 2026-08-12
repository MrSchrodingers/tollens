#!/usr/bin/env bash
# CONCORRENCIA - o lock de execucao das suites (tests/lib/lock.sh).
#
# Esta suite NAO toma o lock: ela e quem o exercita. Toma-lo aqui faria os processos-filho
# herdarem TOLLENS_LOCK=held, pularem a aquisicao, e o teste passaria sem exercitar nada
# - a forma vacua que este repositorio ja pagou cinco vezes. Por isso todo filho e lancado com
# `env -u TOLLENS_LOCK`, e o caso C4 existe justamente para provar que a marca foi
# limpa: sem ele, C1 poderia estar medindo outra coisa.
#
# DEFEITO QUE ORIGINOU O LOCK, reproduzido antes de existir codigo:
#   contrato.sh (que muta subagent-contract.sh no lugar) rodando junto de run.sh fez run.sh
#   reportar "FAIL  BARRA blocos completos SEM ancora (got=0 want=2)", exit 1. Isolada no
#   instante seguinte: PASS=45 FAIL=0. A vermelhidao era PLAUSIVEL - o pior modo de falha,
#   porque manda o operador depurar um defeito que nao existe.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# DEPENDENCIA DE ORACULO, nao variacao de ambiente: sem flock nao existe o mecanismo sob teste,
# e "nao reprovou" seria indistinguivel de "nao foi testado". exit 2 = NAO VERIFICADO.
if ! command -v flock >/dev/null 2>&1; then
  echo "NAO VERIFICADO: flock ausente - o mecanismo sob teste nao existe neste ambiente." >&2
  exit 2
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
LOCKLIB="$PWD/tests/lib/lock.sh"
# LOCK PROPRIO, isolado do real. Sem isto esta suite nao pode rodar sob scripts/status.sh,
# que ja segura o lock do repositorio: os clientes-filho sairiam 3 e C1 mediria a colisao com
# o pai em vez da exclusao mutua entre si.
export TOLLENS_LOCK_FILE="$T/suite-sob-teste.lock"

# Cliente minimo: exercita o LOCK, nao uma suite. Uma suite real traria dezenas de outras
# causas de falha e o exit code deixaria de ser atribuivel ao lock.
cat > "$T/cliente.sh" <<EOF
#!/usr/bin/env bash
set -uo pipefail
. "$LOCKLIB"
# O sinal vem ANTES da espera, de proposito. Na primeira versao deste teste o \`echo\` vinha
# DEPOIS do \`sleep\`, entao o loop de espera de C1 so via o marcador quando o primeiro cliente
# ja tinha TERMINADO e liberado o lock - os dois clientes nunca se sobrepunham e C1 media
# ausencia de concorrencia. A invariante de contagem foi quem denunciou.
echo adquirido
[ -n "\${1:-}" ] && sleep "\$1"
exit 0
EOF
chmod +x "$T/cliente.sh"

echo "== C1. duas execucoes concorrentes: a segunda REPROVA em vez de corromper =="
env -u TOLLENS_LOCK bash "$T/cliente.sh" 5 >"$T/a.out" 2>"$T/a.err" &
BG=$!
# espera ATIVA pela aquisicao do primeiro. `sleep` fixo tornaria o teste dependente de
# escalonamento: numa maquina carregada o segundo cliente rodaria antes do primeiro pegar o
# lock, e C1 falharia por corrida do proprio teste - defeito na medicao, nao no mecanismo.
for _ in $(seq 1 100); do grep -q adquirido "$T/a.out" 2>/dev/null && break; sleep 0.1; done
chk "o primeiro cliente adquiriu o lock" "$(grep -q adquirido "$T/a.out" && echo sim || echo nao)" "sim"
env -u TOLLENS_LOCK bash "$T/cliente.sh" >"$T/b.out" 2>"$T/b.err"; RC2=$?
chk "  o segundo sai 3 (corrida detectada, nao defeito de teste)" "$RC2" 3
chk "  e diz por que, nomeando o lock" \
    "$(grep -q '^LOCK:' "$T/b.err" && echo sim || echo nao)" "sim"
chk "  o segundo NAO executou o corpo" \
    "$(grep -q adquirido "$T/b.out" && echo nao || echo sim)" "sim"

echo "== C2. liberado o lock, a execucao seguinte e normal =="
wait "$BG"; chk "o primeiro terminou com exit 0" "$?" 0
env -u TOLLENS_LOCK bash "$T/cliente.sh" >"$T/c.out" 2>&1; RC3=$?
chk "  apos a liberacao, adquire normalmente" "$RC3" 0

echo "== C3. RE-ENTRANCIA: o filho nao trava no lock do pai =="
# Os runners de mutacao invocam as suites de regressao. Sem re-entrancia o lock seria um
# deadlock por desenho, e o mecanismo de protecao viraria o defeito.
env -u TOLLENS_LOCK bash "$T/cliente.sh" 5 >"$T/d.out" 2>&1 &
BG2=$!
for _ in $(seq 1 100); do grep -q adquirido "$T/d.out" 2>/dev/null && break; sleep 0.1; done
TOLLENS_LOCK=held bash "$T/cliente.sh" >"$T/e.out" 2>&1; RC4=$?
chk "com a marca herdada, o filho passa mesmo com o lock tomado" "$RC4" 0
wait "$BG2" 2>/dev/null

echo '== C4. DISCRIMINADOR: `env -u` de fato limpa a marca =='
# Sem este caso, C1 poderia estar medindo um cliente que pulou a aquisicao por herdar a marca -
# e "o segundo saiu 3" teria vindo de outra causa qualquer.
RC5=$(env -u TOLLENS_LOCK bash -c 'echo "${TOLLENS_LOCK:-VAZIO}"')
chk "a marca chega VAZIA ao filho lancado com env -u" "$RC5" "VAZIO"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=8
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "concorrencia verde ($P/$EXPECTED)" || echo "concorrencia VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
