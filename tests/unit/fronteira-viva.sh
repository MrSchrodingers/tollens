#!/usr/bin/env bash
# FRONTEIRA VIVA - Applies(P,r) medido no SERVIDOR, nao inferido do YAML.
#
# POR QUE ESTA SUITE EXISTE - defeito MEDIDO, nao inferido (2026-08-10).
#
# `tests/unit/fronteira-externa.sh` e ESTATICO: le os arquivos de workflow deste repositorio.
# O defeito que esta suite protege era, por definicao, INVISIVEL a essa leitura - o YAML dos
# workflows nunca mudou. O que mudou foi a configuracao do ruleset no GitHub:
#
#   enforcement: active, bypass_actors: [], exigindo `verify-pr` com
#   strict_required_status_checks_policy: true - e conditions.ref_name.include era `[]`.
#
# A formula publicada, ExternalGate(P,a) <=> RequiredCheck(P) ^ not Bypass(a,P), ficava
# SATISFEITA enquanto o portao nao valia para ref nenhuma: faltava o termo de aplicabilidade.
# A propriedade correta e Gate(P,a,r) <=> Applies(P,r) ^ Required(P) ^ not Bypass(a,P), e
# `evidence/probes/github-ruleset.py` mede Applies(P,r) contra o endpoint AUTORITATIVO
# (`GET /repos/{owner}/{repo}/rules/branches/{branch}` - o proprio GitHub resolvendo quais
# regras ativas se aplicam aquela ref).
#
# O QUE ESTA SUITE VERIFICA, E O QUE NAO VERIFICA
# ------------------------------------------------
# VERIFICA os TRES caminhos do probe, com o cliente de API (o binario `gh`) SUBSTITUIDO por um
# stub deterministico mais cedo no PATH - a mesma tecnica de tests/unit/regressao-gate.sh (casos
# G6/G9) para simular ferramentas ausentes ou com resposta controlada. NENHUMA rede real e usada.
#   V1 - regras aplicaveis e o contexto exigido esta entre elas, sem bypass -> PASS, exit 0.
#   V2 - resposta VAZIA do endpoint autoritativo (o defeito real: nenhuma regra ativa se aplica)
#        -> FAIL, exit 1. Sem este caso a suite nao discrimina nada: um probe que sempre
#        retornasse PASS passaria em V1 e V3 igualmente.
#   V3 - API indisponivel (gh falha, ou gh ausente do PATH) -> NOT_VERIFIED, exit 2. Nunca PASS
#        por omissao de sinal - mesma doutrina de evidence/hooks/verify-gate.sh.
#
# NAO VERIFICA o servidor real do GitHub a cada execucao (isso e o proprio probe, exercitado
# manualmente contra o repositorio e registrado na evidencia da claim). Esta suite mede o
# COMPORTAMENTO DE DECISAO do probe diante de cada forma de resposta - nao a configuracao atual
# do ruleset, que pode mudar sem que este arquivo mude.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
PROBE="$PWD/evidence/probes/github-ruleset.py"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

command -v python3 >/dev/null 2>&1 || { echo "NAO VERIFICADO: python3 ausente - o probe nao pode ser exercitado." >&2; exit 2; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- O STUB DO CLIENTE DE API ---
# Roteia pela FORMA do endpoint pedido (rules/branches/* vs rulesets/*), nao pelo CONTEUDO -
# um stub que decidisse pelo conteudo estaria testando o proprio stub, nao o probe. O
# comportamento por caminho vem de STUB_MODE, lido do ambiente pelo stub em tempo de execucao.
FAKEBIN="$T/bin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "api" ] || { echo "fake-gh: comando nao suportado: $*" >&2; exit 127; }
REQ="$2"
if [ "${STUB_MODE:-}" = "down" ]; then
  echo '{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest","status":"401"}'
  echo "gh: Bad credentials (HTTP 401)" >&2
  exit 1
fi
case "$REQ" in
  */rules/branches/*)
    case "${STUB_MODE:-}" in
      empty) echo '[]' ;;
      pass)
        cat <<'JSON'
[
  {"type":"deletion","ruleset_source_type":"Repository","ruleset_source":"stub/repo","ruleset_id":999},
  {"type":"non_fast_forward","ruleset_source_type":"Repository","ruleset_source":"stub/repo","ruleset_id":999},
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      *) echo "fake-gh: STUB_MODE nao reconhecido: ${STUB_MODE:-<vazio>}" >&2; exit 1 ;;
    esac
    ;;
  */rulesets/*)
    # marcador: prova QUAL caminho realmente chamou este endpoint. So o caminho PASS deveria.
    : > "${STUB_MARKER:-/dev/null}"
    echo '{"id":999,"enforcement":"active","bypass_actors":[],"current_user_can_bypass":"never"}'
    ;;
  *) echo "fake-gh: path nao stubado: $REQ" >&2; exit 1 ;;
esac
STUB
chmod +x "$FAKEBIN/gh"

rodar(){  # $1=STUB_MODE  $2=arquivo de marcador (rulesets chamado?)  stdout/stderr em $T/out $T/err
  STUB_MARKER="$2" STUB_MODE="$1" PATH="$FAKEBIN:$PATH" \
    python3 "$PROBE" --owner stub --repo repo --branch main --context verify-pr \
    >"$T/out" 2>"$T/err"
  echo $?
}

echo "== V1. regras aplicaveis e contexto presente, sem bypass -> PASS =="
MRK="$T/chamou-ruleset-v1"; rm -f "$MRK"
RC="$(rodar pass "$MRK")"
chk "exit code 0" "$RC" 0
chk "relata estado PASS" "$(grep -q '^estado: PASS$' "$T/out" && echo sim || echo nao)" "sim"
chk "  cita a formula satisfeita" "$(grep -q 'Gate(P,a,r) satisfeita' "$T/out" && echo sim || echo nao)" "sim"
chk "  resolveu bypass/strict via o endpoint de ruleset (nao so rules/branches)" \
    "$([ -f "$MRK" ] && echo sim || echo nao)" "sim"

echo "== V2. resposta VAZIA do endpoint autoritativo -> FAIL (o discriminador) =="
# Sem este caso a suite nao mede nada: um probe que sempre retornasse PASS passaria em V1 e V3
# igualmente, e so a forma "vazio -> deve reprovar" prova que o probe le a resposta de verdade.
MRK="$T/chamou-ruleset-v2"; rm -f "$MRK"
RC="$(rodar empty "$MRK")"
chk "exit code 1" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo e Applies(P,r) = False" "$(grep -q 'Applies(P,r) = False' "$T/out" && echo sim || echo nao)" "sim"
# ANTIVACUIDADE OPERACIONAL: sem regra aplicavel, o probe nem tenta resolver bypass_actors -
# se ele chamasse mesmo assim, o marcador provaria que o short-circuit nao existe.
chk "  NAO chama o endpoint de ruleset (nada aplicavel = nada a resolver)" \
    "$([ -f "$MRK" ] && echo chamou || echo nao-chamou)" "nao-chamou"

echo "== V3. API indisponivel -> NOT_VERIFIED, exit 2 (fail-closed, nunca PASS por omissao) =="
MRK="$T/chamou-ruleset-v3"; rm -f "$MRK"
RC="$(rodar down "$MRK")"
chk "exit code 2" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  stderr declara NAO VERIFICADO (canal que o operador le)" \
    "$(grep -q 'NAO VERIFICADO' "$T/err" && echo sim || echo nao)" "sim"
chk "  nao produz PASS nem FAIL por omissao de sinal" \
    "$(grep -qE '^estado: (PASS|FAIL)$' "$T/out" && echo vazou || echo contido)" "contido"
# Segunda forma da MESMA doutrina: 'gh' nem instalado (nao so gh falhando). PATH SEM NENHUM
# diretorio (nem sequer um substituto de gh) - basta que 'gh' nao resolva. O interprete e
# invocado pelo CAMINHO ABSOLUTO (sys.executable): um PATH vazio nao impede o exec de um
# binario ja localizado, so a busca por comandos NAO qualificados como 'gh' dentro do probe.
PYBIN="$(python3 -c 'import sys; print(sys.executable)')"
NOBIN="$T/bin-sem-gh"; mkdir -p "$NOBIN"   # existe e esta vazio: PATH valido, sem 'gh' nele
RC2=$(PATH="$NOBIN" "$PYBIN" "$PROBE" --owner stub --repo repo --branch main --context verify-pr \
      >"$T/out2" 2>"$T/err2"; echo $?)
chk "  'gh' ausente do PATH tambem e NOT_VERIFIED (mesma doutrina, outra causa)" "$RC2" 2
chk "  e nomeia a dependencia ausente" "$(grep -q "'gh'" "$T/out2" && echo sim || echo nao)" "sim"

echo
printf '================ PASS=%s  FAIL=%s ================\n' "$P" "$F"
# CONTAGEM INVARIANTE: um caso que parasse de rodar aqui sumiria em silencio, e V2 - o unico
# caso negativo real desta suite - e precisamente o que nao pode desaparecer sem sinal.
EXPECTED=14
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "fronteira viva verde ($P/$EXPECTED)" || echo "fronteira viva VERMELHA ($F falhas)"
exit "$F"
