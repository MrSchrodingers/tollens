#!/usr/bin/env bash
# TESTES DE PROPRIEDADE. Cada caso afirma uma propriedade que deve valer para uma FAMILIA de
# entradas geradas, nao para um exemplo escolhido a mao.
#
# POR QUE, neste repositorio especificamente. Os testes por exemplo daqui ja falharam duas vezes
# da mesma maneira: o exemplo casava com a implementacao, e a implementacao reconhecia a FORMA
# do exemplo em vez da propriedade. Foi assim que:
#   - o oraculo da ancora do contrato reconhecia `exit code 0` mas nao ``exit code `0` ``;
#   - a primeira versao de S2 tinha `\[\]` dentro da classe de caracteres, o que a invalidava,
#     e o `pymupdf` sem pinagem entrou por baixo dela.
# Um caso por exemplo prova que a implementacao aceita AQUELE exemplo. A propriedade e o que se
# queria garantir.
#
# ACHADOS NA PRIMEIRA EXECUCAO (2026-08-04) - dois detectores de seguranca furados:
#   S2 so enxergava tokens iniciados por ASPA SIMPLES. `pip install requests` e
#      `pip install "requests"` PASSAVAM: pacote sem pinagem atravessava o gate por diferenca
#      de formatacao. Era a propria classe que S2 existe para impedir.
#   S1 recortava por `${line#*uses: }`, com UM espaco literal. `uses:  a/b@v1` (dois espacos)
#      produzia string vazia e a action nao pinada passava batida.
# Nenhum dos dois seria encontrado por mais um caso por exemplo escrito por quem escreveu o
# detector - o exemplo herdaria a mesma suposicao de formatacao.
#
# DETERMINISMO: a semente e FIXA. Um teste de propriedade que muda de resultado entre execucoes
# transforma o gate em ruido, e ruido faz o operador desligar o gate. A semente e impressa; para
# explorar mais, `PROP_SEED=<n> PROP_ITER=<n> bash tests/unit/propriedades.sh`.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
REPO="$PWD"
SEED="${PROP_SEED:-20260804}"
ITER="${PROP_ITER:-6}"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }
echo "semente=$SEED  iteracoes=$ITER"

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/wf"

# ---------------------------------------------------------------------------------------------
# Roda a suite de cadeia de suprimentos sobre um workflow SINTETICO. E uma COPIA do workflow
# real com UMA linha trocada: assim S3..S6 continuam valendo e a reprovacao e atribuivel a
# linha alterada, e nao a um arquivo genericamente incompleto.
sc_caso(){ # $1=linha nova  $2=pip|act  -> ecoa PASS/FAIL do caso correspondente
  # O workflow exigido pelo ruleset e a copia de referencia. `verify-push.yml` roda os MESMOS
  # passos (garantido por FE3 em tests/unit/fronteira-externa.sh), entao medir sobre um dos dois
  # mede os dois - e S1..S6 varrem o diretorio inteiro em uso normal, de todo modo.
  cp "$REPO/.github/workflows/verify-pr.yml" "$T/wf/verify-pr.yml"
  python3 - "$T/wf/verify-pr.yml" "$1" "$2" <<'PY'
import re, sys
p, novo, tipo = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
pat, ind = ((r"^ *python3 -m pip install .*$", " " * 10) if tipo == "pip"
            else (r"^ *- uses: actions/checkout@.*$", " " * 6))
s2 = re.sub(pat, ind + novo, s, count=1, flags=re.M)
if s2 == s:
    sys.exit("ANCORA NAO CASOU - o caso mediria o workflow original")
open(p, "w").write(s2)
PY
  [ $? -eq 0 ] || { echo ANCORA; return; }
  local key out
  key=$([ "$2" = pip ] && echo 'nenhum pacote pip sem' || echo 'nenhuma action por tag')
  out="$(SUPPLY_CHAIN_WF_DIR="$T/wf" bash "$REPO/tests/unit/supply-chain.sh" 2>&1)"
  printf '%s' "$out" | grep -E "$key" | sed 's/^ *//' | cut -c1-4
}

echo "== PB1. o detector de pinagem pip nao depende de FORMATACAO =="
# Toda variante abaixo declara `requests` SEM versao exata. A propriedade: qualquer que seja a
# forma de escrever, o detector reprova.
i=0
for v in "requests" "'requests'" '"requests"' "'requests>=2.0'" "requests[socks]" "'requests~=2.0'"; do
  r="$(sc_caso "python3 -m pip install --quiet $v" pip)"
  chk "sem pinagem reprova: $v" "$r" "FAIL"; i=$((i+1))
done
# CONTROLES. Sem eles um detector que reprovasse SEMPRE passaria em todos os casos acima, e a
# suite mediria "reprova" em vez de "discrimina".
for v in "'requests==2.32.3'" 'requests==2.32.3' '"requests==2.32.3"'; do
  r="$(sc_caso "python3 -m pip install --quiet $v" pip)"
  chk "  pinado passa: $v" "$r" "PASS"
done

echo "== PB2. o detector de action nao pinada nao depende de FORMATACAO =="
SHA40="11d5960a326750d5838078e36cf38b85af677262"
for v in "- uses: actions/checkout@v4" \
         "- uses:  actions/checkout@v4" \
         "- uses:   actions/checkout@v4" \
         "- uses: actions/checkout@11d5960" \
         "- uses: actions/checkout@v4  # comentario"; do
  r="$(sc_caso "$v" act)"
  chk "nao pinada reprova: ${v#- }" "$r" "FAIL"
done
for v in "- uses: actions/checkout@$SHA40" "- uses:  actions/checkout@$SHA40"; do
  r="$(sc_caso "$v" act)"
  chk "  pinada por SHA de 40 passa: ${v#- }" "$r" "PASS"
done

echo "== PB3. nome de arquivo hostil e VALOR, nunca comando =="
# D1 diz que placeholders sao substituidos por VALOR e que nada e re-parseado. A propriedade:
# para QUALQUER nome de arquivo, nenhum efeito lateral do nome ocorre. O corpus cobre as formas
# que produziriam execucao se em algum ponto houvesse `sh -c` ou re-parse.
DT="$REPO/execution/document-tools/doctool.sh"
if ! command -v jq >/dev/null 2>&1; then
  echo "NAO VERIFICADO: jq ausente - doctool nao opera." >&2; exit 2
fi
HOSTIS_OK=0; HOSTIS_BAD=""
# O MARCADOR E RELATIVO, de proposito. A primeira versao deste caso embutia o caminho ABSOLUTO
# do marcador dentro do nome do arquivo - e nome de arquivo nao pode conter '/'. Resultado:
# 5 dos 10 nomes nem chegavam a ser criados, e a assercao "nenhum efeito lateral" seria
# verdadeira sobre arquivos que nunca existiram. E a forma vacua outra vez, agora no teste que
# eu estava escrevendo para caca-la. O discriminador de exercicio abaixo e o que a denuncia.
mkdir -p "$T/docs"
n=0
while IFS= read -r nome; do
  n=$((n+1))
  rm -f "$T/docs/PWNED_PROP" "$REPO/PWNED_PROP" "$T/PWNED_PROP"
  f="$T/docs/$nome"
  printf 'coluna_a,coluna_b\n1,2\n3,4\n' > "$f" 2>/dev/null || { HOSTIS_BAD="$HOSTIS_BAD [nao-criavel:$nome]"; continue; }
  ( cd "$T/docs" && DOC_ADAPTERS_DIR="$REPO/execution/adapters/documents" \
      timeout 60 bash "$DT" probe "$f" >/dev/null 2>&1 )
  # procura o marcador nos tres lugares onde uma execucao acidental o deixaria: o cwd do
  # doctool, a raiz do repositorio e o temporario da suite.
  if [ -e "$T/docs/PWNED_PROP" ] || [ -e "$REPO/PWNED_PROP" ] || [ -e "$T/PWNED_PROP" ]; then
    HOSTIS_BAD="$HOSTIS_BAD [EXECUTOU:$nome]"
  else
    HOSTIS_OK=$((HOSTIS_OK+1))
  fi
  rm -f "$f" "$T/docs/PWNED_PROP" "$REPO/PWNED_PROP" "$T/PWNED_PROP"
done <<'EOF'
$(touch PWNED_PROP).csv
`touch PWNED_PROP`.csv
; touch PWNED_PROP; .csv
| touch PWNED_PROP .csv
&& touch PWNED_PROP .csv
$(printf PWNED_PROP > PWNED_PROP).csv
nome com espacos.csv
--flag-parecida.csv
'aspas'simples.csv
"aspas"duplas.csv
EOF
chk "nenhum dos $n nomes hostis produziu efeito lateral" "${HOSTIS_BAD:-nenhum}" "nenhum"
# DISCRIMINADOR: sem esta assercao, um doctool que abortasse em TODO nome hostil (sem nunca
# processar nada) daria o mesmo resultado acima, e o caso seria vacuamente verdadeiro.
chk "  e o corpus foi de fato exercitado ($HOSTIS_OK/$n)" \
    "$([ "$HOSTIS_OK" -eq "$n" ] && echo sim || echo nao)" "sim"

echo "== PB4. a identidade do manifesto e INJETIVA sobre conteudo =="
# Propriedade: alterar UM byte de QUALQUER componente rastreado muda o manifesto. Se nao mudar,
# a identidade nao identifica - e foi assim que o repositorio pode divergir de ~/.claude em
# silencio por meses (ADR 0022).
CP="$T/repo"; mkdir -p "$CP"
tar -C "$REPO" -cf - --exclude=.git --exclude=.mypy_cache --exclude=.ruff_cache . 2>/dev/null | tar -C "$CP" -xf -
( cd "$CP" && bash install/manifest.sh "$T/base.lock" >/dev/null 2>&1 )
chk "manifesto de referencia gerado" "$([ -s "$T/base.lock" ] && echo sim || echo nao)" "sim"
MUDOU=0; IGUAL=""
ALVOS="$(cut -f2 "$T/base.lock" | grep -v '^#' | head -200)"
python3 - "$T/base.lock" "$SEED" "$ITER" > "$T/escolhidos" <<'PY'
import random, sys
lock, seed, it = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
alvos = [l.split("\t")[1] for l in open(lock) if not l.startswith("#") and "\t" in l]
r = random.Random(seed)
# amostra SEM reposicao: repetir o mesmo arquivo inflaria a contagem sem ampliar a cobertura
for a in r.sample(alvos, min(it, len(alvos))):
    print(a)
PY
while IFS= read -r rel; do
  alvo="$CP/$rel"
  [ -f "$alvo" ] || { alvo="$(find "$CP/$rel" -type f 2>/dev/null | head -1)"; }
  [ -f "$alvo" ] || continue
  cp "$alvo" "$T/bkp"
  printf '\n# byte de mutacao de propriedade\n' >> "$alvo"
  ( cd "$CP" && bash install/manifest.sh "$T/mut.lock" >/dev/null 2>&1 )
  if cmp -s "$T/base.lock" "$T/mut.lock"; then IGUAL="$IGUAL [$rel]"; else MUDOU=$((MUDOU+1)); fi
  cp "$T/bkp" "$alvo"
done < "$T/escolhidos"
ESCOLHIDOS=$(wc -l < "$T/escolhidos")
chk "toda mutacao de 1 componente mudou o manifesto ($MUDOU/$ESCOLHIDOS)" "${IGUAL:-nenhum}" "nenhum"
chk "  e houve mutacao a exercitar (nao vacuo)" \
    "$([ "$MUDOU" -ge 1 ] && echo sim || echo nao)" "sim"
( cd "$CP" && bash install/manifest.sh "$T/rest.lock" >/dev/null 2>&1 )
chk "  restaurado, o manifesto volta a ser identico" \
    "$(cmp -s "$T/base.lock" "$T/rest.lock" && echo sim || echo nao)" "sim"

echo "== PB5. MONOTONICIDADE DA OBSERVABILIDADE: menos informacao nunca melhora o veredito =="
# INVARIANTE:  Information(x') subconjunto de Information(x)  =>  Verdict(x') nao e MELHOR que
# Verdict(x).  Um verificador que observa MENOS da MESMA realidade pode empatar ou piorar o
# veredito; nunca pode aprovar mais.
#
# DE ONDE VEM. Na onda 8, `evidence/probes/github-ruleset.py` tratava
# `current_user_can_bypass`='never' como medicao suficiente de not Bypass(a,P) quando
# `bypass_actors` nao vinha na resposta da API. Medido e registrado em docs/adr/0029 ("O NONO
# DEGRAU"): para o MESMO ruleset, a visao ADMIN (campo visivel, contendo OrganizationAdmin) saia
# FAIL exit=1, e a visao de token de CI (o MESMO ruleset, campo omitido por falta de acesso de
# escrita) saia PASS_PARCIAL exit=0. Reduzir o privilegio do observador AUMENTAVA a aprovacao.
# Aquilo foi corrigido NAQUELE probe (EXIT[PASS_PARCIAL] voltou a 2). O que nao existia era o
# INVARIANTE: nada impedia a mesma forma de reaparecer em outro verificador. Este caso mede a
# FAMILIA - verificadores REAIS, cada um sob dois regimes de observabilidade, vereditos
# comparados entre si.
#
# A ORDEM USADA, e por que NAO e a ordem total PASS > NOT_VERIFIED > FAIL:
#   PASS(0) e o UNICO topo. FAIL(1) e NOT_VERIFIED(2) ficam estritamente abaixo dele e sao
#   INCOMPARAVEIS ENTRE SI. Duas razoes, ambas conferiveis neste repositorio:
#   (a) SEMANTICA DO CONSUMIDOR. `.github/workflows/verify-pr.yml` roda cada verificador como um
#       passo sem `continue-on-error`: exit 0 autoriza, 1 e 2 barram IGUALMENTE. A unica
#       distincao que o consumidor faz - logo, a unica coisa que "melhor" pode significar aqui -
#       e autorizar contra nao autorizar.
#   (b) A ordem total classificaria como VIOLACAO o comportamento DELIBERADO do probe: visao
#       admin -> FAIL; visao de CI (menos observabilidade sobre o MESMO ruleset) -> NOT_VERIFIED.
#       ADR 0029 escolheu exatamente isso como CORRETO ("sob um token sem acesso de escrita ao
#       ruleset, `bypass_actors` nao e observavel ... e o veredito e NAO VERIFICADO - nunca
#       verde"). Uma propriedade que reprova a correcao que o repositorio adotou nao esta medindo
#       este invariante; esta medindo outra coisa.
#   Epistemicamente, tambem: FAIL afirma uma violacao MEDIDA, NOT_VERIFIED afirma AUSENCIA de
#   medicao - nao estao no mesmo eixo. Perder observabilidade pode converter violacao medida em
#   lacuna, e isso e honesto. O que nao pode e converter qualquer um dos dois em APROVACAO.
#
# O QUE ESTE CASO NAO AFIRMA. A comparacao e a relacao de ordem, nao "degradado != 0": um par com
# regime cheio PASS e degradado PASS passa. LIMITE DECLARADO: hoje nenhum par real tem os dois
# regimes em PASS, entao esse ramo da comparacao nao e exercitado por par real.
#
# TRES DISCRIMINADORES, sem os quais o caso seria vacuo:
#   1. nenhum par INERTE - se o regime degradado devolve o mesmo exit do cheio, a degradacao pode
#      nao ter mordido e o par nao mede nada. Foi o que aconteceu na primeira tentativa deste
#      caso: remover o diretorio de `jq` do PATH nao remove `jq`, porque `/bin` e link para
#      `/usr/bin` e continua no PATH - o "regime degradado" era o regime cheio com outro nome.
#   2. ao menos um par cujo regime CHEIO aprova - sem isso, nenhum par teria a oportunidade de
#      produzir o falso sucesso que o invariante existe para barrar.
#   3. ao menos um par cujo regime CHEIO mede VIOLACAO - e a situacao em que a cegueira tem o que
#      esconder, e e a forma exata do defeito historico.
#
# VALIDADO POR MUTACAO (2026-08-12), porque propriedade que nao mata mutante nao mede nada:
#   MUTANTE 1 - par sintetico "verificador que aprova quando cego" (cheio=FAIL, degradado=PASS)
#     acrescentado a tabela: a propriedade REPROVOU so aquele par, nomeando-o
#     ("got=sim want=nao"), PASS=31 FAIL=1, exit 1. Removido em seguida.
#   MUTANTE 2 - o DEFEITO HISTORICO restaurado no codigo real: uma COPIA do probe com
#     `EXIT[PASS_PARCIAL]` de volta a 0 (a decisao da onda 8), com `PROBE_MO` apontado para ela.
#     O par do ruleset SUJO virou FAIL -> PASS e a propriedade REPROVOU, exit 1. Revertido.
#     Nenhum arquivo de producao foi alterado nas duas medicoes.
#
# O QUE ISTO ACRESCENTA ao que ja existia. Os dois regimes ja eram medidos, em separado, por
# casos POR EXEMPLO: tests/unit/claims.sh:84 afirma que o ledger real valida (exit 0) e :169 que
# sem parser o veredito e 2; tests/unit/fronteira-viva.sh (V4/V44) mede as duas visoes de token.
# O que nao existia era a RELACAO entre eles - nenhum caso comparava os dois vereditos, e por
# isso nenhum caso reprovaria um verificador NOVO que aprovasse ao ver menos.
PB5T="$T/pb5"; mkdir -p "$PB5T"
# O interpretador REAL, nao o shim. `python3` pode ser um shim (pyenv) que depende do PATH para
# resolver o interpretador; como o regime degradado do par B esvazia o PATH de proposito, o shim
# sairia 127 - um exit que nao e veredito nenhum. Medido nesta maquina antes de escrever o caso;
# o ramo ANOMALO de `mo_veredito` existe para nunca deixar isso passar por "veredito".
PY3R="$(python3 -c 'import sys; print(sys.executable)' 2>/dev/null)"
[ -x "$PY3R" ] || PY3R="$(command -v python3)"
PROBE_MO="$REPO/evidence/probes/github-ruleset.py"

# STUB DO CLIENTE DE API - a mesma tecnica de tests/unit/fronteira-viva.sh: o BINARIO `gh` e
# substituido mais cedo no PATH, nao ha rede. As tres visoes descrevem A MESMA REALIDADE de
# servidor sob privilegios de token diferentes; `rules/branches` e IDENTICA nas tres, e so a
# resposta de `rulesets/{id}` muda - que e precisamente o que o privilegio do token altera.
GHBIN="$PB5T/bin"; mkdir -p "$GHBIN"
cat > "$GHBIN/gh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "api" ] || { echo "stub-gh: comando nao suportado: $*" >&2; exit 127; }
case "$2" in
  */rules/branches/*)
    cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":true,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
    ;;
  */rulesets/*)
    case "${VISAO:-}" in
      # SUJO, visao ADMIN: o ruleset 999 TEM bypass concedido a OrganizationAdmin, e o token com
      # escrita no ruleset enxerga a lista.
      admin-sujo)
        echo '{"id":999,"enforcement":"active","current_user_can_bypass":"never",
               "bypass_actors":[{"actor_type":"OrganizationAdmin","actor_id":1,"bypass_mode":"always"}]}' ;;
      # O MESMO ruleset 999, MESMA realidade, visao de token sem acesso de escrita: a API OMITE
      # `bypass_actors`. Information(x') e estritamente menor; nada no servidor mudou.
      ci-sujo)
        echo '{"id":999,"enforcement":"active","current_user_can_bypass":"never"}' ;;
      # LIMPO, visao ADMIN: nenhum ator com bypass - o unico regime cheio que aprova.
      admin-limpo)
        echo '{"id":999,"enforcement":"active","current_user_can_bypass":"never","bypass_actors":[]}' ;;
      *) echo "stub-gh: VISAO nao reconhecida: ${VISAO:-<vazio>}" >&2; exit 1 ;;
    esac ;;
  *) echo "stub-gh: path nao stubado: $2" >&2; exit 1 ;;
esac
STUB
chmod +x "$GHBIN/gh"
SEMBIN="$PB5T/bin-vazio"; mkdir -p "$SEMBIN"
MO_SAB="$PB5T/sabotagem"; mkdir -p "$MO_SAB"
# Parser da evidencia indisponivel - mesma tecnica de tests/unit/claims.sh (L9): um modulo que
# lanca ImportError precede o real no PYTHONPATH. O ledger no disco e o MESMO; o que se perde e
# a capacidade de le-lo.
printf 'raise ImportError("parser indisponivel por fixture")\n' > "$MO_SAB/yaml.py"
MO_WF="$PB5T/wf"; mkdir -p "$MO_WF"; cp "$REPO"/.github/workflows/*.yml "$MO_WF/"

mo_probe(){ VISAO="$1" PATH="$GHBIN:$PATH" "$PY3R" "$PROBE_MO" \
    --owner stub --repo repo --branch main --context verify-pr >"$PB5T/saida" 2>&1; }
mo_probe_admin_sujo(){  mo_probe admin-sujo; }
mo_probe_ci_sujo(){     mo_probe ci-sujo; }
mo_probe_admin_limpo(){ mo_probe admin-limpo; }
# Regime degradado ao extremo: `gh` nao existe no PATH. Nenhuma observacao do servidor.
mo_probe_sem_gh(){ PATH="$SEMBIN" "$PY3R" "$PROBE_MO" \
    --owner stub --repo repo --branch main --context verify-pr >"$PB5T/saida" 2>&1; }
mo_claims(){      "$PY3R" "$REPO/evidence/validate-claims.py" "$REPO" "$REPO/evidence/claims" >"$PB5T/saida" 2>&1; }
mo_claims_cego(){ PYTHONPATH="$MO_SAB" "$PY3R" "$REPO/evidence/validate-claims.py" "$REPO" "$REPO/evidence/claims" >"$PB5T/saida" 2>&1; }
mo_lit(){         "$PY3R" "$REPO/evidence/validate-literature.py" "$REPO" "$REPO/evidence/literature" >"$PB5T/saida" 2>&1; }
mo_lit_cego(){    PYTHONPATH="$MO_SAB" "$PY3R" "$REPO/evidence/validate-literature.py" "$REPO" "$REPO/evidence/literature" >"$PB5T/saida" 2>&1; }
mo_cap(){         "$PY3R" "$REPO/evidence/runtime-probes/declared-capabilities.py" --repo-only >"$PB5T/saida" 2>&1; }
mo_cap_cego(){    PYTHONPATH="$MO_SAB" "$PY3R" "$REPO/evidence/runtime-probes/declared-capabilities.py" --repo-only >"$PB5T/saida" 2>&1; }
# Degradacao de FILESYSTEM: os MESMOS workflows, um deles ilegivel. Assume execucao sem root -
# a mesma suposicao que tests/unit/capabilities.sh (K18) ja faz, e o discriminador de inercia
# denuncia se ela nao valer no ambiente.
mo_sc(){ chmod 644 "$MO_WF"/*.yml 2>/dev/null
         SUPPLY_CHAIN_WF_DIR="$MO_WF" bash "$REPO/tests/unit/supply-chain.sh" >"$PB5T/saida" 2>&1; }
mo_sc_cego(){ local rc
  chmod 000 "$MO_WF/verify-pr.yml" 2>/dev/null
  SUPPLY_CHAIN_WF_DIR="$MO_WF" bash "$REPO/tests/unit/supply-chain.sh" >"$PB5T/saida" 2>&1; rc=$?
  chmod 644 "$MO_WF/verify-pr.yml" 2>/dev/null; return $rc; }

mo_veredito(){ case "$1" in 0) echo PASS ;; 1) echo FAIL ;; 2) echo NOT_VERIFIED ;;
                            *) echo "ANOMALO($1)" ;; esac; }
mo_melhor(){ # $1=exit degradado  $2=exit cheio -> "sim" se o DEGRADADO e estritamente melhor
  # PASS e o unico topo; FAIL e NOT_VERIFIED nao se ordenam entre si (justificativa acima).
  # Exit fora de {0,1,2} nao e veredito: nao ha o que ordenar, e a comparacao vira anomalia -
  # nunca "nao violou por omissao".
  case "$1" in 0|1|2) ;; *) echo "anomalia(degradado=$1)"; return ;; esac
  case "$2" in 0|1|2) ;; *) echo "anomalia(cheio=$2)";     return ;; esac
  if [ "$1" = 0 ] && [ "$2" != 0 ]; then echo sim; else echo nao; fi; }

MO_NOMES=(); MO_C=(); MO_D=(); MO_DEG=()
mo_par(){ # $1=rotulo  $2=descricao da degradacao  $3=fn regime CHEIO  $4=fn regime DEGRADADO
  local rc_c rc_d
  "$3"; rc_c=$?
  "$4"; rc_d=$?
  MO_NOMES+=("$1"); MO_DEG+=("$2"); MO_C+=("$rc_c"); MO_D+=("$rc_d"); }

mo_par "probe github-ruleset (ruleset SUJO)" \
       "visao de token sem escrita: API omite bypass_actors" \
       mo_probe_admin_sujo mo_probe_ci_sujo
mo_par "probe github-ruleset (ruleset LIMPO)" \
       "gh ausente do PATH: nenhuma observacao do servidor" \
       mo_probe_admin_limpo mo_probe_sem_gh
mo_par "validate-claims.py (ledger real)" \
       "parser YAML indisponivel: ledger existe, nao pode ser lido" \
       mo_claims mo_claims_cego
mo_par "validate-literature.py (corpus real)" \
       "parser YAML indisponivel: corpus existe, nao pode ser lido" \
       mo_lit mo_lit_cego
mo_par "declared-capabilities.py --repo-only" \
       "parser YAML indisponivel: projecoes existem, nao podem ser lidas" \
       mo_cap mo_cap_cego
mo_par "supply-chain.sh (workflows reais)" \
       "um workflow ilegivel por permissao (chmod 000)" \
       mo_sc mo_sc_cego

echo "  VERIFICADORES EXERCITADOS (regime cheio -> regime degradado):"
i=0
while [ $i -lt ${#MO_NOMES[@]} ]; do
  printf '    %-42s %-12s -> %-12s  [%s]\n' "${MO_NOMES[$i]}" \
    "$(mo_veredito "${MO_C[$i]}")" "$(mo_veredito "${MO_D[$i]}")" "${MO_DEG[$i]}"
  i=$((i+1))
done
echo "  FORA DE COBERTURA, e por que (cobertura silenciosa e o mesmo que cobertura ausente):"
echo "    - probe github-ruleset contra a API VIVA: o regime CHEIO exige token com acesso de"
echo "      escrita ao ruleset (segredo) e rede. Nao simulado; aqui so o binario gh e stubado."
echo "    - evidence/cobertura.sh: o regime cheio custa uma execucao completa sob instrumentacao"
echo "      de cobertura (minutos). Fora por custo; CB7 ja cobre 'coverage ausente' por exemplo."
echo "    - tests/unit/managed-root-trust.sh e install/apply-managed.sh: o regime cheio exige"
echo "      root/sudo, que esta fora do que esta suite pode assumir."
echo "    - tests/unit/document-tools.sh: degradacao alcancavel (pandas/fitz/pdftotext ausentes),"
echo "      mas e a MESMA classe ja medida em tres pares (dependencia de oraculo ausente) e custa"
echo "      uma execucao completa da suite documental. Fora por redundancia e custo."
echo "    - hooks (execution/hooks/**, evidence/hooks/verify-gate.sh): nao emitem veredito de tres"
echo "      estados sobre realidade externa - ali exit 2 significa BLOQUEIO no contrato de hook,"
echo "      outro significado, e compara-los nesta ordem seria comparar coisas diferentes."

MO_INERTES=""; MO_TEM_PASS=nao; MO_TEM_FAIL=nao; MO_PIORARAM=""
i=0
while [ $i -lt ${#MO_NOMES[@]} ]; do
  chk "menos observabilidade nao melhorou: ${MO_NOMES[$i]} (cheio=$(mo_veredito "${MO_C[$i]}") degradado=$(mo_veredito "${MO_D[$i]}"))" \
      "$(mo_melhor "${MO_D[$i]}" "${MO_C[$i]}")" "nao"
  [ "${MO_C[$i]}" = "${MO_D[$i]}" ] && MO_INERTES="$MO_INERTES [${MO_NOMES[$i]}]"
  [ "${MO_C[$i]}" = 0 ] && MO_TEM_PASS=sim
  [ "${MO_C[$i]}" = 1 ] && MO_TEM_FAIL=sim
  [ "${MO_C[$i]}" = 0 ] && [ "${MO_D[$i]}" = 1 ] && MO_PIORARAM="$MO_PIORARAM [${MO_NOMES[$i]}]"
  i=$((i+1))
done
chk "  nenhum par INERTE: a degradacao mordeu nos ${#MO_NOMES[@]} pares" "${MO_INERTES:-nenhum}" "nenhum"
chk "  ha par cujo regime CHEIO aprova (o falso sucesso era alcancavel)" "$MO_TEM_PASS" "sim"
chk "  ha par cujo regime CHEIO mede VIOLACAO (a cegueira tinha o que esconder)" "$MO_TEM_FAIL" "sim"
# OBSERVACAO, nao assercao: PASS -> FAIL e permitido por este invariante (o degradado piorou),
# mas contradiz a doutrina de que falha AMBIENTAL vira NOT_VERIFIED e nao violacao (a decisao P5
# de tests/unit/capabilities.sh, K18). Fica REGISTRADO aqui em vez de adjudicado por este caso.
[ -n "$MO_PIORARAM" ] && echo "  OBSERVACAO: degradacao virou FAIL (nao NOT_VERIFIED) em:$MO_PIORARAM"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=31
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED (semente=$SEED). Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "propriedades verde ($P/$EXPECTED)" || echo "propriedades VERMELHA (semente=$SEED)"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
