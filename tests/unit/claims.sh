#!/usr/bin/env bash
# CLAIM LEDGER - a suite do validador (evidence/validate-claims.py).
#
# O caso L1 sozinho nao vale nada: um validador que aprovasse QUALQUER coisa passaria nele. O
# valor desta suite esta nos casos NEGATIVOS - L2 a L8 - que exigem reprovacao. Foi precisamente
# a ausencia de negativo que deixou o oraculo da ancora do contrato de subagente sem poder de
# decisao medido por versoes inteiras (ver docs/adr/0023).
#
# L9 e L10 cobrem as duas formas de o validador deixar de medir sem reprovar:
#   L9  - dependencia de ORACULO ausente (pyyaml) -> exit 2, NAO VERIFICADO;
#   L10 - a EXTRACAO do inventario quebra e devolve vazio. Sem a autochecagem isso reprovaria
#         tudo (falso vermelho) ou, com regex frouxa demais, aprovaria tudo (falso verde).
#
# L13 a L17 sao o SCHEMA v2, e existem por um defeito que a auditoria externa encontrou: o
# validador ancorava a evidencia em (caminho, commit) - um NOME - e um nome pode passar a
# designar outro conteudo. L13 reproduz o caso real (C-016), e os demais fecham as saidas:
#   L13 - blob_sha que nao casa com o conteudo atual REPROVA;
#   L14 - omitir blob_sha nao volta ao comportamento v1 em silencio;
#   L15 - faixa de linhas e validada contra o conteudo ANCORADO, nao contra o arquivo atual;
#   L16 - prefixo curto de SHA reprova (identidade ambigua nao ancora);
#   L17 - `ci` exige execucao identificavel, e nao a URL do workflow, igual em toda claim.
# Cada um vem com o CONTROLE POSITIVO ao lado: sem ele, um validador que reprovasse tudo
# passaria em todos os negativos.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
V="$PWD/evidence/validate-claims.py"
REPO="$PWD"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# DEPENDENCIA DE ORACULO: sem pyyaml o validador nao decide nada, e "nao reprovou" seria
# indistinguivel de "nao foi verificado". Reprova a suite em vez de virar SKIP silencioso.
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "NAO VERIFICADO: pyyaml ausente - o validador sob teste nao pode operar." >&2
  exit 2
fi

# FIXTURES TEMPORARIAS injetadas NO REPOSITORIO REAL (nao em $T) pelos casos D6 abaixo - mesma
# tecnica de tests/mutation/*.sh (edita/injeta no lugar, protegido pelo lock desta suite,
# restaurado por trap). Precisam viver dentro de tests/unit/ e tests/mutation/ porque
# `inventario()` so varre esses dois diretorios.
D6_FIX_MUT="$REPO/tests/mutation/_fixture_d6_tmp.sh"
D6_FIX_UNIT="$REPO/tests/unit/_fixture_d6_tmp.sh"
# Par de fixtures do caso A1 abaixo (onda 6): DUAS invocacoes do MESMO ID de mutante em DOIS
# arquivos de tests/mutation/ - a mesma tecnica do par acima, mas precisa de DOIS arquivos
# simultaneos (o par acima reusa D6_FIX_MUT sozinho porque so um lado da colisao vem de fixture).
D6_FIX_MUT_A="$REPO/tests/mutation/_fixture_d6a_tmp.sh"
D6_FIX_MUT_B="$REPO/tests/mutation/_fixture_d6b_tmp.sh"
T="$(mktemp -d)"
trap 'rm -rf "$T"; rm -f "$D6_FIX_MUT" "$D6_FIX_UNIT" "$D6_FIX_MUT_A" "$D6_FIX_MUT_B"' EXIT
# SHA COMPLETO: o schema v2 recusa prefixo. `rev-parse HEAD` ja devolve 40 hex; o fallback
# tambem tem de ter 40, senao o fixture reprovaria por FORMA e os casos mediriam outra coisa.
SHA="$(git -C "$REPO" rev-parse HEAD 2>/dev/null || echo 0000000000000000000000000000000000000000)"
# Um commit real deste repositorio para `ci.head_sha`. O validador confere offline que o
# head_sha citado e commit daqui; usar um valor inventado faria todo fixture reprovar por ci.
CI_SHA="$SHA"

# Molde de claim VALIDA. Cada caso negativo altera UM campo, para que a reprovacao seja
# atribuivel aquele campo e nao a um documento genericamente malformado.
molde(){ cat <<EOF
claim_id: $1
claim: "alegacao de teste"
type: empirical-invariant
scope:
  subject_snapshot: "${3:-$SHA}"
  platforms: [local-linux]
evidence:
  regression: [${2:-G1}]
  ci:
    run_id: 30924006484
    head_sha: "$CI_SHA"
    workflow: verify-pr
warrant: "molde de teste"
limitations: ["fixture"]
status: supported-in-tested-domain
EOF
}
# roda o validador sobre um diretorio de claims descartavel; ecoa so o exit code
val(){ python3 "$V" "$REPO" "$1" >/dev/null 2>&1; echo $?; }

echo "== L1. o ledger REAL do repositorio e valido =="
chk "evidence/claims/ valida" "$(python3 "$V" "$REPO" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)" 0

echo "== L2. citar regressao INEXISTENTE reprova (a regra central) =="
D="$T/l2"; mkdir -p "$D"; molde C-001 G999 > "$D/C-001.yaml"
chk "regressao G999 nao existe em tests/ -> reprova" "$(val "$D")" 1
D="$T/l2b"; mkdir -p "$D"; molde C-001 G1 > "$D/C-001.yaml"
chk "  e o MESMO molde com G1 (que existe) passa" "$(val "$D")" 0

echo "== L3. citar mutante INEXISTENTE reprova =="
# A PRIMEIRA VERSAO DESTE CASO PASSOU PELO MOTIVO ERRADO. O fixture era montado concatenando
# uma linha ao molde, o que produzia YAML INVALIDO; o validador reprovava no parser e o caso
# ficava verde sem nunca exercitar a resolucao de mutante. Verde por motivo errado e a mesma
# familia do verde vacuo, e so apareceu porque o traceback do parser vazou para a saida.
# Defesa: o par negativo/positivo abaixo difere em UM identificador. Se o positivo passar e o
# negativo reprovar, a diferenca so pode ter vindo da resolucao.
mut_fixture(){ # $1=destino  $2=id de mutante
python3 - "$1" "$2" "$SHA" <<'PY'
import sys, yaml
d = {"claim_id":"C-001","claim":"alegacao de teste","type":"empirical-invariant",
     "scope":{"subject_snapshot":sys.argv[3],"platforms":["local-linux"]},
     "evidence":{"regression":["G1"],"mutants":[sys.argv[2]],"ci":{"run_id":30924006484,"head_sha":sys.argv[-1],"workflow":"verify-pr"}},
     "warrant":"molde de teste","limitations":["fixture"],
     "status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(sys.argv[1],"w"), allow_unicode=True, sort_keys=False)
PY
}
D="$T/l3"; mkdir -p "$D"; mut_fixture "$D/C-001.yaml" M999
chk "o fixture e YAML VALIDO (senao o caso mediria o parser)" \
    "$(python3 -c "import yaml,sys; yaml.safe_load(open(sys.argv[1])); print('sim')" "$D/C-001.yaml" 2>/dev/null || echo nao)" "sim"
chk "  mutante M999 nao existe -> reprova" "$(val "$D")" 1
D="$T/l3b"; mkdir -p "$D"; mut_fixture "$D/C-001.yaml" M1
chk "  o MESMO fixture com M1 (que existe) passa" "$(val "$D")" 0

echo "== L4. alegacao SEM nenhuma referencia de evidencia reprova =="
D="$T/l4"; mkdir -p "$D"
python3 - "$D/C-001.yaml" "$SHA" <<'PY'
import sys, yaml
d = {"claim_id":"C-001","claim":"sem lastro","type":"empirical-invariant",
     "scope":{"subject_snapshot":sys.argv[2],"platforms":["local-linux"]},
     "evidence":{"ci":{"run_id":30924006484,"head_sha":sys.argv[-1],"workflow":"verify-pr"}},
     "warrant":"nenhum","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(sys.argv[1],"w"), allow_unicode=True, sort_keys=False)
PY
chk "sem regression, mutants nem observation -> reprova" "$(val "$D")" 1

echo "== L5. scope.subject_snapshot inexistente reprova =="
D="$T/l5"; mkdir -p "$D"; molde C-001 G1 "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef" > "$D/C-001.yaml"
chk "commit que nao existe no repo -> reprova" "$(val "$D")" 1
D="$T/l5b"; mkdir -p "$D"; molde C-001 G1 "--upload-pack=touch /tmp/PWN_CLAIMS" > "$D/C-001.yaml"
rm -f /tmp/PWN_CLAIMS
chk "  valor com cara de OPCAO nao chega ao git" "$(val "$D")" 1
chk "  e nao executa nada" "$([ -f /tmp/PWN_CLAIMS ] && echo nao || echo sim)" "sim"

echo "== L6. observation apontando para arquivo inexistente reprova =="
D="$T/l6"; mkdir -p "$D"
python3 - "$D/C-001.yaml" "$SHA" <<'PY'
import sys, yaml
d = {"claim_id":"C-001","claim":"observacao fantasma","type":"runtime-observation",
     "scope":{"subject_snapshot":sys.argv[2],"platforms":["local-linux"]},
     "evidence":{"observation":{"command":"echo","recorded":"evidence/observations/nao-existe.md"},
                 "ci":{"run_id":30924006484,"head_sha":sys.argv[-1],"workflow":"verify-pr"}},
     "warrant":"nenhum","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(sys.argv[1],"w"), allow_unicode=True, sort_keys=False)
PY
chk "recorded aponta para arquivo ausente -> reprova" "$(val "$D")" 1

echo "== L7. claim_id duplicado reprova =="
D="$T/l7"; mkdir -p "$D"; molde C-001 G1 > "$D/C-001.yaml"; molde C-001 G1 > "$D/C-002.yaml"
chk "dois arquivos com o mesmo claim_id -> reprova" "$(val "$D")" 1

echo "== L8. limitations vazio reprova =="
D="$T/l8"; mkdir -p "$D"
python3 - "$D/C-001.yaml" "$SHA" <<'PY'
import sys, yaml
d = {"claim_id":"C-001","claim":"sem limites","type":"empirical-invariant",
     "scope":{"subject_snapshot":sys.argv[2],"platforms":["local-linux"]},
     "evidence":{"regression":["G1"],"ci":{"run_id":30924006484,"head_sha":sys.argv[-1],"workflow":"verify-pr"}},
     "warrant":"nenhum","limitations":[],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(sys.argv[1],"w"), allow_unicode=True, sort_keys=False)
PY
chk "toda alegacao tem alcance finito -> lista vazia reprova" "$(val "$D")" 1

echo "== L9. pyyaml ausente e NAO VERIFICADO (exit 2), nao aprovacao =="
# Mesma tecnica de S5: um modulo que lanca ImportError precede o real no PYTHONPATH.
SB="$T/sabotagem"; mkdir -p "$SB"; printf 'raise ImportError("indisponivel por fixture")\n' > "$SB/yaml.py"
rc=$(PYTHONPATH="$SB" python3 "$V" "$REPO" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)
chk "sem parser, o validador declara NAO VERIFICADO" "$rc" 2

echo "== L11. observation com caminho ABSOLUTO ou '..' reprova =="
# ACHADO DE AUDITORIA: `os.path.join(raiz, x)` DESCARTA `raiz` quando `x` e absoluto. Medido:
# uma claim cujo unico lastro era `recorded: /etc/passwd` era APROVADA, e o validador imprimia
# "ledger valido: toda evidencia citada existe em tests/" - frase literalmente falsa. O dano
# nao e a travessia em si: e a alegacao passar a ter lastro FORA do repositorio enquanto o
# programa afirma ter resolvido a evidencia contra a suite.
# $1=destino  $2=recorded  $3=blob_sha (default: o blob REAL de $2)  $4/$5=faixa opcional
obs_fixture(){
  local blob="${3:-}"
  [ -n "$blob" ] || blob="$(git -C "$REPO" hash-object -- "$REPO/$2" 2>/dev/null || echo \
      0000000000000000000000000000000000000000)"
python3 - "$1" "$2" "$blob" "${4:-}" "${5:-}" "$SHA" <<'PY2'
import sys, yaml
dest, rec, blob, ls, le, sha = sys.argv[1:7]
obs = {"command": "echo", "recorded": rec, "blob_sha": blob}
if ls:
    obs["line_start"], obs["line_end"] = int(ls), int(le)
d = {"claim_id":"C-001","claim":"lastro fora do repo","type":"runtime-observation",
     "scope":{"subject_snapshot":sha,"platforms":["local-linux"]},
     "evidence":{"observation":obs,
                 "ci":{"run_id":30924006484,"head_sha":sha,"workflow":"verify-pr"}},
     "warrant":"fixture","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(dest,"w"), allow_unicode=True, sort_keys=False)
PY2
}
D="$T/l11"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "/etc/passwd"
chk "recorded absoluto (/etc/passwd) reprova" "$(val "$D")" 1
D="$T/l11b"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "../../../../etc/hostname"
chk "  recorded com '..' reprova" "$(val "$D")" 1
# CONTROLE: sem ele, um validador que reprovasse toda observation passaria nos dois acima.
D="$T/l11c"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "docs/HANDOFF.md"
chk "  e um caminho relativo VALIDO dentro do repo passa" "$(val "$D")" 0

echo "== L13. blob_sha que NAO casa com o conteudo atual reprova (o defeito de C-016) =="
# ESTE E O CASO QUE A AUDITORIA EXTERNA COMPROU. Reproducao do defeito real, nao de um sintoma:
# C-016 declarava `scope.commit: c3ffe52` e seu warrant descrevia DOIS controles de push; no
# snapshot c3ffe52 a observacao citada continha apenas o primeiro.
#     $ git show c3ffe52:evidence/observations/...fronteira-externa... | grep -c 'Adendo\|MERGED'
#     0
# O validador v1 conferia `cat-file -e <commit>:<caminho>` - que o ARQUIVO existia. Existia. O
# CONTEUDO citado, nao. Ancorar em (caminho, commit) endereca um NOME, e um nome pode passar a
# designar outro conteudo. Ancorar em blob endereca o CONTEUDO, e nao pode.
ALVO="evidence/observations/2026-08-04-fronteira-externa-e-contrato-no-runtime.md"
BLOB_ANTIGO="$(git -C "$REPO" rev-parse "c3ffe52:$ALVO" 2>/dev/null || echo '')"
BLOB_ATUAL="$(git -C "$REPO" hash-object -- "$REPO/$ALVO" 2>/dev/null || echo '')"
if [ -z "$BLOB_ANTIGO" ] || [ -z "$BLOB_ATUAL" ]; then
  echo "  SKIP  snapshot c3ffe52 indisponivel - o caso nao pode ser exercitado"
else
  # PRECONDICAO EXPLICITA: se os dois blobs fossem iguais, o caso mediria zero e ficaria verde.
  chk "o conteudo de ENTAO difere do conteudo de HOJE (senao o caso e vacuo)" \
      "$([ "$BLOB_ANTIGO" != "$BLOB_ATUAL" ] && echo sim || echo nao)" "sim"
  D="$T/l13"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "$ALVO" "$BLOB_ANTIGO"
  chk "  ancorada no conteudo de ENTAO -> reprova" "$(val "$D")" 1
  D="$T/l13b"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "$ALVO" "$BLOB_ATUAL"
  chk "  a MESMA claim ancorada no conteudo ATUAL passa (o campo decide)" "$(val "$D")" 0
fi

echo "== L14. observation SEM blob_sha reprova - o nome do arquivo nao e ancora =="
# Sem este caso, bastaria omitir o campo para voltar ao comportamento v1 sem nenhum sinal.
D="$T/l14"; mkdir -p "$D"
python3 - "$D/C-001.yaml" "$SHA" <<'PY'
import sys, yaml
d = {"claim_id":"C-001","claim":"sem ancora de conteudo","type":"runtime-observation",
     "scope":{"subject_snapshot":sys.argv[2],"platforms":["local-linux"]},
     "evidence":{"observation":{"command":"echo","recorded":"docs/HANDOFF.md"},
                 "ci":{"run_id":30924006484,"head_sha":sys.argv[2],"workflow":"verify-pr"}},
     "warrant":"fixture","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(sys.argv[1],"w"), allow_unicode=True, sort_keys=False)
PY
chk "observation sem blob_sha -> reprova" "$(val "$D")" 1

echo "== L15. faixa de linhas fora do conteudo ancorado reprova =="
# Citar a linha 99999 de um arquivo de 200 linhas e uma citacao que nao resolve. O oraculo e o
# conteudo ANCORADO (o blob), nao o arquivo atual - senao a faixa passaria a ser validada contra
# um conteudo diferente daquele que a claim cita.
NLINHAS="$(git -C "$REPO" cat-file blob "$(git -C "$REPO" hash-object -- "$REPO/docs/HANDOFF.md")" | wc -l)"
D="$T/l15"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "docs/HANDOFF.md" "" 1 "$((NLINHAS + 500))"
chk "line_end alem do fim do conteudo -> reprova" "$(val "$D")" 1
D="$T/l15b"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "docs/HANDOFF.md" "" 1 "$NLINHAS"
chk "  a MESMA faixa dentro do conteudo passa" "$(val "$D")" 0
D="$T/l15c"; mkdir -p "$D"; obs_fixture "$D/C-001.yaml" "docs/HANDOFF.md" "" 9 3
chk "  faixa invertida (start > end) reprova" "$(val "$D")" 1

echo "== L16. SHA de prefixo curto reprova - identidade ambigua nao ancora =="
# v1 aceitava de 7 a 40 hex e as 16 claims usavam 7. Prefixo colide por construcao, e a colisao
# e o modo de falha silencioso: o objeto errado resolve e o validador aprova.
CURTO="$(printf '%s' "$SHA" | cut -c1-7)"
D="$T/l16"; mkdir -p "$D"; molde C-001 G1 "$CURTO" > "$D/C-001.yaml"
chk "subject_snapshot com 7 hex -> reprova" "$(val "$D")" 1
D="$T/l16b"; mkdir -p "$D"; molde C-001 G1 "$SHA" > "$D/C-001.yaml"
chk "  o MESMO commit com 40 hex passa (o comprimento decide, nao o objeto)" "$(val "$D")" 0

echo "== L17. evidence.ci exige execucao identificavel, nao URL de workflow =="
# v1 tinha `ci_run: <URL do workflow>` - a MESMA string em toda claim, e portanto sem poder de
# identificacao. Nao dizia qual execucao, sobre qual commit, com qual resultado.
ci_fixture(){ # $1=destino  $2=run_id  $3=head_sha
python3 - "$1" "$2" "$3" "$SHA" <<'PY3'
import sys, yaml
dest, run_id, head, sha = sys.argv[1:5]
# `workflow` sempre presente e VALIDO: estes casos medem run_id e head_sha, e deixar o
# workflow de fora faria a reprovacao ter duas causas e a atribuicao virar adivinhacao.
ci = {"workflow": "verify-pr"}
if run_id: ci["run_id"] = run_id
if head: ci["head_sha"] = head
d = {"claim_id":"C-001","claim":"ci","type":"empirical-invariant",
     "scope":{"subject_snapshot":sha,"platforms":["local-linux"]},
     "evidence":{"regression":["G1"],"ci":ci},
     "warrant":"fixture","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(dest,"w"), allow_unicode=True, sort_keys=False)
PY3
}
D="$T/l17"; mkdir -p "$D"; ci_fixture "$D/C-001.yaml" "30924006484" ""
chk "ci sem head_sha -> reprova" "$(val "$D")" 1
D="$T/l17b"; mkdir -p "$D"; ci_fixture "$D/C-001.yaml" "" "$SHA"
chk "  ci sem run_id -> reprova" "$(val "$D")" 1
D="$T/l17c"; mkdir -p "$D"
ci_fixture "$D/C-001.yaml" "30924006484" "deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
chk "  head_sha que nao e commit deste repo -> reprova" "$(val "$D")" 1
D="$T/l17d"; mkdir -p "$D"; ci_fixture "$D/C-001.yaml" "30924006484" "$SHA"
chk "  run_id numerico + head_sha real passa" "$(val "$D")" 0

echo "== L18. evidence.ci.workflow e resolvido contra o SNAPSHOT, nao e decorativo =="
# Achado da revisao independente do PR #5: `workflow` era escrito e nunca validado - qualquer
# string passava. Campo com aparencia de rastro e sem poder de discriminacao e a versao menor do
# defeito que este ledger inteiro persegue.
# RESOLVIDO CONTRA O SNAPSHOT, e nao contra o worktree: `verify` existia em c3ffe52 e nao existe
# mais hoje (virou verify-pr/verify-push). As claims daquele snapshot o citam CORRETAMENTE.
wf_fixture(){ # $1=destino  $2=nome do workflow  $3=subject_snapshot
python3 - "$1" "$2" "$3" <<'PY4'
import sys, yaml
dest, wf, sha = sys.argv[1:4]
d = {"claim_id":"C-001","claim":"workflow","type":"empirical-invariant",
     "scope":{"subject_snapshot":sha,"platforms":["local-linux"]},
     "evidence":{"regression":["G1"],
                 "ci":{"run_id":30924006484,"head_sha":sha,"workflow":wf}},
     "warrant":"fixture","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(dest,"w"), allow_unicode=True, sort_keys=False)
PY4
}
ANTIGO="$(git -C "$REPO" rev-parse c3ffe52 2>/dev/null || echo '')"
if [ -z "$ANTIGO" ]; then
  echo "  SKIP  snapshot c3ffe52 indisponivel"
else
  D="$T/l18"; mkdir -p "$D"; wf_fixture "$D/C-001.yaml" "workflow-que-nunca-existiu" "$ANTIGO"
  chk "workflow inexistente no snapshot -> reprova" "$(val "$D")" 1
  D="$T/l18b"; mkdir -p "$D"; wf_fixture "$D/C-001.yaml" "verify" "$ANTIGO"
  chk "  e 'verify', que existia NAQUELE snapshot, passa" "$(val "$D")" 0
  # O CONTROLE QUE PROVA A RESOLUCAO POR SNAPSHOT: `verify-pr` existe HOJE e NAO existia em
  # c3ffe52. Se o validador resolvesse contra o worktree, este caso passaria.
  D="$T/l18c"; mkdir -p "$D"; wf_fixture "$D/C-001.yaml" "verify-pr" "$ANTIGO"
  chk "  e 'verify-pr' (existe hoje, NAO existia la) reprova" "$(val "$D")" 1
fi

echo "== L10. inventario vazio e NAO VERIFICADO, nao ledger valido =="
# Autochecagem: se o contrato de extracao deixar de casar com tests/, o validador precisa
# gritar. Sem isto ele reprovaria tudo, ou - com regex frouxa - aprovaria tudo.
FAKE="$T/repo-sem-testes"; mkdir -p "$FAKE/tests/unit" "$FAKE/tests/mutation"
rc=$(python3 "$V" "$FAKE" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)
chk "extracao vazia -> exit 2, nunca 0" "$rc" 2

echo "== L12. a evidencia e resolvida contra o SNAPSHOT declarado, nao contra o worktree =="
# PORTAO FINAL, 2026-08-04. `scope.commit` era DECORATIVO: o validador conferia so que o objeto
# git existia, e resolvia a evidencia contra a arvore de trabalho. Medido: as 16 claims
# declaravam um commit em que os mutantes MC6/MC7 e as duas observacoes NAO EXISTIAM, e o
# validador imprimia "toda evidencia citada existe" - verdadeiro sobre o worktree e FALSO sobre
# o escopo que cada claim declara. Alegacao cujo lastro nao existe no snapshot que ela nomeia
# nao esta ancorada: esta datada errado, que e a forma silenciosa de nao estar ancorada.
# A ANCORA E A RAIZ DO REPOSITORIO, e nao uma DISTANCIA em commits.
# A primeira versao deste caso usava HEAD~6 e a CI o reprovou: localmente HEAD~6 caia antes de
# a suite de concorrencia existir; com UM commit a mais, passou a cair depois, a claim resolveu,
# e o caso media zero. Um teste ancorado em distancia de historico mede a profundidade do
# historico, nao a propriedade - e o resultado muda sozinho a cada commit.
# A raiz e estavel por construcao: nenhuma evidencia desta sessao existe la, hoje ou nunca.
ANTIGO="$(git -C "$REPO" rev-list --max-parents=0 HEAD 2>/dev/null | tail -1)"
if [ -z "$ANTIGO" ]; then
  echo "  SKIP  historico curto demais para exercitar a resolucao por snapshot"
else
  D="$T/l12"; mkdir -p "$D"
  # a MESMA claim, mudando SO o snapshot: se o resultado nao mudar, a resolucao ignora o campo.
  cp "$REPO/evidence/claims/C-011.yaml" "$D/C-011.yaml"
  chk "no snapshot corrente a claim resolve" "$(val "$REPO/evidence/claims")" 0
  # PRECONDICAO EXPLICITA: sem ela, se a evidencia por acaso ja existisse no snapshot antigo,
  # o caso passaria a medir nada e nao haveria sinal. Foi assim que a versao anterior quebrou.
  chk "  a evidencia citada NAO existe no snapshot antigo (senao o caso e vacuo)" \
      "$(git -C "$REPO" show "$ANTIGO:tests/unit/concorrencia.sh" 2>/dev/null | grep -c '^echo .== C1' | tr -d ' ')" "0"
  python3 - "$D/C-011.yaml" "$ANTIGO" <<'PY3'
import sys, yaml
p, sha = sys.argv[1], sys.argv[2]
raw = open(p).read()
head = "\n".join(l for l in raw.split("\n") if l.startswith("#"))
d = yaml.safe_load(raw); d["scope"]["subject_snapshot"] = sha
open(p, "w").write(head + "\n")
with open(p, "a") as fh:
    yaml.safe_dump(d, fh, allow_unicode=True, sort_keys=False, width=100)
PY3
  chk "  a MESMA claim num snapshot anterior REPROVA (o campo decide)" "$(val "$D")" 1
fi

echo "== L-FRESCOR: ancora obsoleta reprova conforme o status =="
# Defeito medido em 2026-08-11. A isencao de frescor cobria TODO status nao-ativo, e
# `not-verified` caiu nela. Ao renumerar C-018->C-019 a observacao foi editada, o blob_sha ficou
# apontando para o conteudo pre-edicao, e o validador saiu 0. `not-verified` nao e registro
# historico: e alegacao ABERTA, que sera relida. `refuted`/`superseded` sao terminais e a isencao
# ali permanece correta - sem ela seria impossivel preservar o registro de uma alegacao derrubada.
# A ancora falsa precisa EXISTIR e estar ERRADA - o validador tem duas recusas distintas
# ("nao tem lastro" para sha inexistente, "obsoleta" para sha valido porem defasado), e so a
# segunda e isenta por status terminal. `git hash-object README.md` calcula o hash do ARQUIVO
# DE TRABALHO: com README.md modificado e nao commitado, o objeto nao existe no banco e o
# validador recusava pelo motivo errado, derrubando os dois casos de isencao. Fragilidade
# pre-existente, descoberta na onda 15 porque esta onda edita o README. `HEAD:README.md` e o
# blob COMMITADO - existe sempre, e nunca e o da observacao citada por C-018.
FALSO="$(git -C "$REPO" rev-parse HEAD:README.md)"
frescor(){ # $1=status  -> exit code do validador com a ancora quebrada
  local d="$T/fresc-$1"; mkdir -p "$d"
  python3 - "$REPO/evidence/claims/C-018.yaml" "$d/C-018.yaml" "$1" "$FALSO" <<'PY2'
import sys, yaml
src, dst, status, falso = sys.argv[1:5]
d = yaml.safe_load(open(src))
d["status"] = status
d["evidence"]["observation"]["blob_sha"] = falso
d["evidence"]["observation"].pop("line_start", None)
d["evidence"]["observation"].pop("line_end", None)
yaml.safe_dump(d, open(dst, "w"), allow_unicode=True, sort_keys=False, width=100)
PY2
  val "$d"
}
chk "ancora obsoleta em claim ATIVA reprova" "$(frescor supported-in-tested-domain)" 1
chk "  ancora obsoleta em 'not-verified' TAMBEM reprova (alegacao aberta)" "$(frescor not-verified)" 1
chk "  'refuted' segue isenta (registro historico terminal)" "$(frescor refuted)" 0
chk "  'superseded' segue isenta (registro historico terminal)" "$(frescor superseded)" 0

# ESCREVE UMA FIXTURE TEMPORARIA a partir de um conteudo com `\n` ESCAPADO (duas letras, nao
# quebra de linha real), NUNCA como heredoc ou string multi-linha: qualquer forma que reproduza
# o conteudo com quebras de linha REAIS apareceria, ela mesma, como linhas literais dentro DESTE
# arquivo (tests/unit/claims.sh) - e `inventario()` varre o TEXTO BRUTO de todo *.sh sob tests/.
# Medido ao tentar (onda 5): a primeira versao deste caso usava heredoc, e a linha
# `echo "== G1. ..."` do CONTEUDO da fixture virou, ela mesma, uma linha real de
# tests/unit/claims.sh - RE_CASO casou AQUI, duplicando G1 contra tests/unit/regressao-gate.sh, e
# todo caso POSTERIOR do arquivo saiu NAO VERIFICADO por um motivo que nao tinha nada a ver com
# o que o caso queria provar. Mantendo o conteudo inteiro numa SO linha fisica do arquivo-fonte
# (`\n` como texto, nunca como byte de quebra), nenhuma linha DESTE arquivo comeca por
# `echo "=="`/`mutante`; `printf '%b'` so interpreta o escape ao ESCREVER o arquivo de saida.
escreve_fixture(){ printf '%b' "$1" > "$2"; }

echo "== L-D6-FANTASMA: mencao em COMENTARIO nao conta mais como mutante invocado =="
# ONDA 5, D6 (CRITICO). Ate esta correcao, `RE_MUT` aceitava QUALQUER linha de comentario
# `# <ID>[-: ]` em tests/mutation/*.sh como se fosse invocacao - K10 e L6 (IDs de REGRESSAO
# reais) eram inventariados como "mutante" so por aparecerem perto do inicio de um comentario.
# Este e o caso discriminante exigido pela delegacao. TESTA `inventario()` DIRETAMENTE (nao via
# claim/CLI): uma claim com `scope.subject_snapshot` valido SEMPRE resolve contra o SNAPSHOT
# (`inventario_no_commit`, git tree de um commit JA existente), nunca contra arquivo solto no
# worktree - por desenho (ver docstring de `inventario_no_commit`). Um fixture NAO commitado
# seria invisivel por esse caminho, e o caso mediria "commit nao encontrado", nao a extracao.
# `inventario()` em si nao usa git - le arquivos soltos - entao uma raiz FAKE e suficiente e nao
# toca o repositorio real.
D="$T/l_d6_fantasma"; mkdir -p "$D/tests/unit" "$D/tests/mutation"
escreve_fixture '#!/usr/bin/env bash\necho "== Z1. regressao minima, so para a autochecagem nao ficar vazia =="\n' \
  "$D/tests/unit/regressao.sh"
escreve_fixture '#!/usr/bin/env bash\nmutante ZZ1 "mutante de verdade, invocado" "alvo-fixture" true\n# ZZ9 fantasma: aparece SO neste comentario, nunca como mutante ZZ9 - nao pode contar.\n' \
  "$D/tests/mutation/mutacao.sh"
inv_tem(){ # $1=raiz  $2=ID  -> "sim"/"nao" conforme $2 esteja no set de MUTANTES extraido
python3 - "$1" "$2" <<'PY'
import sys
sys.path.insert(0, "evidence")
import importlib
vc = importlib.import_module("validate-claims")
_, mutantes, _ = vc.inventario(sys.argv[1])
print("sim" if sys.argv[2] in mutantes else "nao")
PY
}
chk "invocacao real ('mutante ZZ1 ...') entra no inventario de mutantes" "$(inv_tem "$D" ZZ1)" "sim"
chk "  mencao em comentario ('# ZZ9 ...') NAO entra - fantasma fechado" "$(inv_tem "$D" ZZ9)" "nao"
rm -f "$D6_FIX_MUT"

echo "== L-D6-COLISAO: ID de mutante que reusa um ID de regressao ja existente vira NAO VERIFICADO =="
# Segunda guarda pedida pela delegacao (D6): os espacos de nome regressao/mutante sao disjuntos
# "de proposito" (comentario de RE_EVID_ID) - uma intersecao nao-vazia e resolucao ambigua, a
# MESMA classe de defeito que os fantasmas K10/L6 produziam. G1 e um ID de regressao REAL
# (tests/unit/regressao-gate.sh); o fixture abaixo o reusa como mutante.
escreve_fixture '#!/usr/bin/env bash\nmutante G1 "reusa de proposito o ID de regressao G1 de tests/unit/regressao-gate.sh" "alvo-fixture" true\n' \
  "$D6_FIX_MUT"
rc="$(python3 "$V" "$REPO" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)"
chk "mutante que colide com um ID de regressao ja existente -> NAO VERIFICADO (exit 2)" "$rc" 2
rm -f "$D6_FIX_MUT"
rc="$(python3 "$V" "$REPO" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)"
chk "  controle: sem a colisao, o ledger REAL volta a validar" "$rc" 0

echo "== L-D6-DUPLICADO: o mesmo ID de regressao em DOIS arquivos de tests/unit/ vira NAO VERIFICADO =="
# Terceira guarda pedida pela delegacao (D6/D7): um ID de regressao duplicado entre arquivos
# resolveria em silencio (o inventario funde tudo num set plano) - a mesma ambiguidade que
# tests/unit/claims.sh e tests/unit/literatura.sh tinham de fato ate a onda 5 renomear o
# prefixo de literatura.sh para 'LT' (D7). G1 e reusado de novo aqui, desta vez no espaco de
# REGRESSAO.
escreve_fixture '#!/usr/bin/env bash\necho "== G1. reusa de proposito o ID de regressao G1 de tests/unit/regressao-gate.sh =="\n' \
  "$D6_FIX_UNIT"
rc="$(python3 "$V" "$REPO" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)"
chk "regressao G1 declarada em DOIS arquivos -> NAO VERIFICADO (exit 2)" "$rc" 2
rm -f "$D6_FIX_UNIT"
rc="$(python3 "$V" "$REPO" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)"
chk "  controle: sem a duplicidade, o ledger REAL volta a validar" "$rc" 0

echo "== L-D6-DUPLICADO-MUTANTE: o mesmo ID de mutante em DOIS arquivos de tests/mutation/ vira NAO VERIFICADO =="
# Extensao pedida pela delegacao (onda 6, A1): `_contrato_extracao_ok` checava a duplicidade
# ENTRE ARQUIVOS so no espaco de REGRESSAO (caso anterior); o espaco de MUTANTE tinha a MESMA
# classe de ambiguidade, ja EXERCITADA por claims reais antes desta correcao (M1..M10 reusado
# entre tests/mutation/run.sh e .../schedule.sh; MC1..MC7 entre capabilities.sh/
# conformidade.sh/contrato.sh) - ver o inventario de renomeacao no docstring de
# `_contrato_extracao_ok`. Mesma tecnica dos dois casos acima, agora com DOIS arquivos de
# mutation reusando o MESMO ID de mutante.
escreve_fixture '#!/usr/bin/env bash\nmutante ZZD1 "reusa de proposito o mesmo ID de mutante em dois arquivos" "alvo-fixture" true\n' \
  "$D6_FIX_MUT_A"
escreve_fixture '#!/usr/bin/env bash\nmutante ZZD1 "o MESMO ID de mutante, agora no segundo arquivo" "alvo-fixture" true\n' \
  "$D6_FIX_MUT_B"
rc="$(python3 "$V" "$REPO" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)"
chk "mutante ZZD1 declarado em DOIS arquivos de tests/mutation/ -> NAO VERIFICADO (exit 2)" "$rc" 2
rm -f "$D6_FIX_MUT_B"
rc="$(python3 "$V" "$REPO" "$REPO/evidence/claims" >/dev/null 2>&1; echo $?)"
chk "  controle: com so UM arquivo declarando ZZD1, o ledger REAL volta a validar" "$rc" 0
rm -f "$D6_FIX_MUT_A"

echo "== L-D6-CASO-ANCORADO: cabecalho 'echo == <ID>.' em tests/mutation/*.sh SO conta com ANCORA DE APLICACAO =="
# TERCEIRA FORMA de mutante fantasma (onda 6b, achado do portao final). A correcao anterior
# tratava o cabecalho `echo "== <ID>. ..."` de tests/mutation/install.sh como invocacao por si
# so - a justificativa era uma afirmacao sobre o CONTEUDO ATUAL de install.sh ("o mutante e
# aplicado e morto logo abaixo"), nao uma invariante que a regex impunha. Contraexemplo
# reproduzido aqui tal como medido pelo portao final: um cabecalho SOZINHO dentro de um bloco
# `if false; then ... fi` - nenhuma mutacao aplicada, nenhum oraculo invocado, o bloco nem
# executa - e a MESMA classe de defeito dos fantasmas K10/L6 (L-D6-FANTASMA acima), so que pela
# forma RE_CASO em vez de comentario solto.
D="$T/l_d6_caso_ancorado"; mkdir -p "$D/tests/mutation"
escreve_fixture '#!/usr/bin/env bash\nif false; then\necho "== ZQ7. mutante que nunca existiu =="\nfi\necho "== ZQ8. mutante com mutacao aplicada e oraculo invocado =="\nsed -i "s/a/b/" "$ORIG"\nout="$(bash "$REG" 2>&1)"; rc=$?\n' \
  "$D/tests/mutation/instalador_fixture.sh"
chk "cabecalho SOZINHO em bloco morto (sem sed, sem oraculo) NAO entra" "$(inv_tem "$D" ZQ7)" "nao"
chk "  o MESMO arquivo, cabecalho com sed -i + oraculo invocado no bloco, entra" "$(inv_tem "$D" ZQ8)" "sim"

echo "== L-SNAPSHOT-AMBIGUO: claim ancorada num snapshot historico com mutante CITADO ambiguo la reprova =="
# RESIDUO DE AMBIGUIDADE EM SNAPSHOT HISTORICO (onda 6b). `_contrato_extracao_ok` so confere o
# inventario do WORKTREE; a resolucao de CADA claim roda contra o inventario do SEU
# scope.subject_snapshot (inventario_no_commit). Uma claim ancorada num commit ANTERIOR a uma
# desambiguacao de IDs ainda resolveria contra um inventario ambiguo NAQUELE commit, sem que a
# checagem do worktree visse. 904b027 (pai de 36d8304, que renomeou M1..M10 de schedule.sh para
# MS1..MS10) e um snapshot REAL onde `M1` estava declarado tanto em tests/mutation/run.sh quanto
# em .../schedule.sh - o worktree de hoje ja nao tem essa ambiguidade (D6_FIX_MUT/ZZD1 acima
# testa a mesma garantia so no worktree; este caso testa que ela TAMBEM vale por snapshot).
AMBIGUO="$(git -C "$REPO" rev-parse 904b027 2>/dev/null || echo '')"
if [ -z "$AMBIGUO" ]; then
  echo "  SKIP  commit 904b027 indisponivel - o caso nao pode ser exercitado"
else
  chk "PRECONDICAO: M1 estava de fato em DOIS arquivos naquele snapshot (senao o caso e vacuo)" \
      "$(git -C "$REPO" show "$AMBIGUO:tests/mutation/run.sh" 2>/dev/null | grep -c '^mutante M1 ')-$(git -C "$REPO" show "$AMBIGUO:tests/mutation/schedule.sh" 2>/dev/null | grep -c '^mutante M1 ')" \
      "1-1"
  D="$T/l_snap_amb"; mkdir -p "$D"
  python3 - "$D/C-001.yaml" "$AMBIGUO" "$SHA" <<'PY'
import sys, yaml
dest, amb, head = sys.argv[1:4]
d = {"claim_id":"C-001","claim":"cita mutante ambiguo no snapshot historico","type":"empirical-invariant",
     "scope":{"subject_snapshot":amb,"platforms":["local-linux"]},
     "evidence":{"mutants":["M1"],"ci":{"run_id":30924006484,"head_sha":head,"workflow":"verify-pr"}},
     "warrant":"fixture","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(dest,"w"), allow_unicode=True, sort_keys=False)
PY
  chk "mutante M1 citado, AMBIGUO naquele snapshot -> reprova mesmo com o worktree hoje limpo" \
      "$(val "$D")" 1
  # CONTROLE: o MESMO snapshot, citando um ID que NAO era ambiguo la - sem ele um validador que
  # reprovasse toda claim ancorada em 904b027 passaria no caso acima pelo motivo errado.
  D="$T/l_snap_amb_ctrl"; mkdir -p "$D"
  python3 - "$D/C-001.yaml" "$AMBIGUO" "$SHA" <<'PY'
import sys, yaml
dest, amb, head = sys.argv[1:4]
d = {"claim_id":"C-001","claim":"cita regressao NAO ambigua no mesmo snapshot","type":"empirical-invariant",
     "scope":{"subject_snapshot":amb,"platforms":["local-linux"]},
     "evidence":{"regression":["G1"],"ci":{"run_id":30924006484,"head_sha":head,"workflow":"verify-pr"}},
     "warrant":"fixture","limitations":["fixture"],"status":"supported-in-tested-domain"}
yaml.safe_dump(d, open(dest,"w"), allow_unicode=True, sort_keys=False)
PY
  chk "  o MESMO snapshot, citando G1 (nao ambiguo la) passa - a checagem discrimina por ID" \
      "$(val "$D")" 0
fi

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=54
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "claim ledger verde ($P/$EXPECTED)" || echo "claim ledger VERMELHO"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
