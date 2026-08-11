#!/usr/bin/env bash
# CAMADA DE QUALIDADE DE EVIDENCIA PARA LITERATURA - a suite do validador
# (evidence/validate-literature.py).
#
# O caso L1 sozinho nao vale nada: um validador que aprovasse QUALQUER coisa passaria nele. O
# valor desta suite esta nos casos NEGATIVOS, cada um mutando UM campo do MOLDE (base.py) para
# que a reprovacao seja atribuivel aquele campo, nunca a um documento genericamente malformado
# - mesma disciplina de tests/unit/claims.sh.
#
# Os TRES requisitos da delegacao viram tres grupos de caso:
#   L3-L7   - campos obrigatorios presentes (raiz, study_quality, applicability, findings);
#   L8-L9   - inference_strength e provenance dentro dos vocabularios FECHADOS;
#   L12-L16 - toda afirmacao numerica com fonte declarada, pelos DOIS mecanismos do validador:
#             findings[].source (estrutural) e o marcador 'fonte'/'verificad' no resto do texto.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
V="$PWD/evidence/validate-literature.py"
REPO="$PWD"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# DEPENDENCIA DE ORACULO: sem pyyaml o validador nao decide nada, e "nao reprovou" seria
# indistinguivel de "nao foi verificado". Reprova a suite em vez de virar SKIP silencioso.
if ! python3 -c "import yaml" >/dev/null 2>&1; then
  echo "NAO VERIFICADO: pyyaml ausente - o validador sob teste nao pode operar." >&2
  exit 2
fi

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
val(){ python3 "$V" "$REPO" "$1" >/dev/null 2>&1; echo $?; }

# MOLDE: um documento MINIMO e VALIDO, reutilizado por todo caso negativo abaixo. Cada caso
# importa `doc()` e muda UM campo antes de gravar - se o molde sozinho nao validasse, nenhum
# caso negativo teria controle (foi exatamente a falta de controle que deixou L2 de
# tests/unit/claims.sh medir o parser, nao o validador, na primeira versao daquele arquivo).
cat > "$T/base.py" <<'PY'
def doc():
    return {
        "literature_id": "arxiv-0000.00000",
        "citation": "Fixture, F. Fixture Paper for Testing. arXiv:0000.00000, 2026 preprint.",
        "identifier": "arXiv:0000.00000",
        "url": "https://arxiv.org/abs/0000.00000",
        "provenance": "preprint",
        "study_quality": {
            "benchmark": "fixture-bench",
            "n": "10 tarefas fixture (fonte: fixture)",
            "models": "modelo fixture",
            "scaffold": "scaffold fixture",
            "oracle": "verificador fixture",
            "baseline": "50.0% fixture (fonte: fixture)",
            "trials_repeated": "[nao verificado]",
            "uncertainty_reported": "[nao verificado]",
            "code_data_available": "[nao verificado]",
            "replicated": False,
        },
        "applicability": {
            "domain_similarity": "baixa",
            "scaffold_similarity": "baixa",
            "oracle_similarity": "media",
        },
        "inference_strength": "EXTRAPOLATED",
        "inference_rationale": "fixture sem numero solto - ver findings para o dado bruto",
        "findings": [
            {"metric": "fixture_metric", "value": "50%", "source": "fixture"},
        ],
        "limitations": ["fixture sem alcance real"],
    }
PY

echo "== L1. a camada REAL de evidence/literature/ e valida =="
chk "evidence/literature/ valida" "$(val "$REPO/evidence/literature")" 0

echo "== L2. o MOLDE, sozinho, e valido (controle geral dos negativos abaixo) =="
D="$T/l2"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
yaml.safe_dump(doc(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "molde sem mutacao passa" "$(val "$D")" 0

echo "== L3. campo obrigatorio de raiz ausente reprova =="
D="$T/l3"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); del d["citation"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "'citation' ausente -> reprova" "$(val "$D")" 1

echo "== L4. literature_id fora do padrao reprova; controle: id valido passa =="
D="$T/l4"; mkdir -p "$D"
python3 - "$D/BAD ID.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["literature_id"] = "BAD ID"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "literature_id com maiuscula/espaco -> reprova" "$(val "$D")" 1
D="$T/l4b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
yaml.safe_dump(doc(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  o MESMO molde com id valido passa" "$(val "$T/l4b")" 0

echo "== L5. nome do arquivo que nao bate com literature_id reprova =="
D="$T/l5"; mkdir -p "$D"
python3 - "$D/nome-errado.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
yaml.safe_dump(doc(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "arquivo 'nome-errado.yaml' com literature_id 'arxiv-0000.00000' -> reprova" "$(val "$D")" 1

echo "== L6. literature_id duplicado entre dois arquivos reprova, com a violacao NOMEADA =="
# SOBREDETERMINACAO ESTRUTURAL, nao so desta fixture: se dois arquivos no MESMO diretorio
# declaram o MESMO literature_id, o nome de arquivo de cada um so pode casar com o proprio id
# (regra de L5) se os dois arquivos tiverem o MESMO nome - impossivel no mesmo diretorio (o
# sistema de arquivos nao aceita dois arquivos com nomes identicos). Logo, TODO fixture de
# duplicidade dispara tambem a violacao de nome de arquivo em pelo menos um dos dois documentos
# - nao ha como construir um caso onde SO a duplicidade falhe. Um caso que afira apenas o exit
# code (!=0) e por isso estruturalmente incapaz de discriminar um mutante que remova a guarda de
# duplicidade: o exit code continua 1, vindo so da violacao de nome. Por isso este caso confere
# tambem a MENSAGEM (mesma tecnica de F2/F3/F5 de tests/unit/schedule.sh): a palavra 'duplicado'
# tem de aparecer na saida, o que so acontece se a guarda de duplicidade de fato executou.
D="$T/l6"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
yaml.safe_dump(doc(), open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
python3 - "$D/arxiv-0000.00001.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
OUT6="$(python3 "$V" "$REPO" "$D" 2>&1)"; RC6=$?
chk "dois arquivos com o mesmo literature_id -> reprova" "$RC6" 1
printf '%s' "$OUT6" | grep -qF "duplicado"
chk "  a violacao de duplicidade e NOMEADA na mensagem (nao so o mismatch de nome de arquivo)" $? 0

echo "== L7. findings vazio reprova; study_quality/applicability incompletos reprovam =="
D="$T/l7a"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["findings"] = []
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "findings=[] -> reprova" "$(val "$D")" 1
D="$T/l7b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); del d["study_quality"]["oracle"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "study_quality.oracle ausente -> reprova" "$(val "$D")" 1
D="$T/l7c"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); del d["applicability"]["oracle_similarity"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "applicability.oracle_similarity ausente -> reprova" "$(val "$D")" 1
D="$T/l7d"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["limitations"] = []
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "limitations=[] -> reprova" "$(val "$D")" 1

echo "== L8. inference_strength fora do vocabulario fechado reprova; controle: valor valido passa =="
D="$T/l8"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["inference_strength"] = "PROBABLY"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "inference_strength='PROBABLY' -> reprova" "$(val "$D")" 1
D="$T/l8b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["inference_strength"] = "DIRECT"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  'DIRECT' (no vocabulario fechado) passa" "$(val "$T/l8b")" 0

echo "== L9. provenance fora do vocabulario fechado reprova; controle: valor valido passa =="
D="$T/l9"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["provenance"] = "trust_me_bro"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "provenance='trust_me_bro' -> reprova" "$(val "$D")" 1
D="$T/l9b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["provenance"] = "peer_reviewed"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  'peer_reviewed' (no vocabulario fechado) passa" "$(val "$T/l9b")" 0

echo "== L10. findings[].metric fora de snake_case reprova =="
D="$T/l10"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["findings"][0]["metric"] = "Not Snake Case"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "metric='Not Snake Case' -> reprova" "$(val "$D")" 1

echo "== L11. findings[] sem 'source' reprova - o campo estrutural E a fonte declarada =="
D="$T/l11"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); del d["findings"][0]["source"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "findings[0] sem 'source' -> reprova" "$(val "$D")" 1

echo "== L12. numero solto em inference_rationale SEM marcador de fonte reprova =="
# ESTE E O CASO CENTRAL DO TERCEIRO REQUISITO DA DELEGACAO: "toda afirmacao numerica com fonte
# declarada". Um numero podia entrar pela prosa argumentativa sem nunca passar por findings -
# foi exatamente a rota do defeito original da secao 6.1 do README (ver docstring do validador).
D="$T/l12"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["inference_rationale"] = "o estudo mostra um ganho de 47 por cento sem contexto"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "'47 por cento' solto, sem marcador -> reprova" "$(val "$D")" 1
D="$T/l12b"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
d["inference_rationale"] = "ganho de 47 por cento (fonte: findings acima)"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  o MESMO numero com marcador 'fonte' no texto passa" "$(val "$T/l12b")" 0

echo "== L13. numero solto em limitations[] SEM marcador de fonte reprova =="
D="$T/l13"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["limitations"] = ["so 12 instancias foram observadas"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "'12 instancias' solto, sem marcador -> reprova" "$(val "$D")" 1

echo "== L14. numero solto em study_quality.* SEM marcador de fonte reprova =="
D="$T/l14"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc(); d["study_quality"]["baseline"] = "91 por cento sem marcador nenhum aqui"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "study_quality.baseline com numero sem marcador -> reprova" "$(val "$D")" 1

echo "== L15. numero DENTRO de findings[].value NAO exige o marcador de texto =="
# A fonte de um numero em findings[] e o campo estrutural 'source' (L11 ja cobre a ausencia
# dele). Exigir TAMBEM o marcador textual dentro de findings seria redundante e obrigaria
# prosa artificial em todo 'value' - o desenho deste validador separa os dois mecanismos por
# regiao do documento (ver docstring: 3a cobre findings, 3b cobre o resto).
D="$T/l15"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
d["findings"][0]["value"] = "39/49 sem a palavra-marcador"
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "findings[].value com numero e SEM marcador de texto ainda passa (source cobre)" "$(val "$D")" 0

echo "== L16. numero em campo BIBLIOGRAFICO (citation/identifier/url/cited_in) nao exige marcador =="
# citation/identifier/url/cited_in sao ENDERECO (onde o paper esta, onde e citado), nao
# afirmacao empirica sobre o que o paper mediu - por isso ficam fora da varredura 3b.
D="$T/l16"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
d["cited_in"] = ["docs/adr/0099-fixture.md"]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "cited_in com digito (numero de ADR) sem marcador ainda passa" "$(val "$D")" 0

echo "== L17. diretorio de literatura inexistente e NAO VERIFICADO (exit 2), nao aprovacao =="
chk "diretorio ausente -> exit 2" "$(python3 "$V" "$REPO" "$T/nao-existe" >/dev/null 2>&1; echo $?)" 2

echo "== L18. diretorio de literatura VAZIO (sem yaml) e NAO VERIFICADO (exit 2) =="
D="$T/l18-vazio"; mkdir -p "$D"
chk "diretorio sem entradas -> exit 2" "$(python3 "$V" "$REPO" "$D" >/dev/null 2>&1; echo $?)" 2

echo "== L19. pyyaml ausente e NAO VERIFICADO (exit 2), nao aprovacao =="
# Mesma tecnica usada em tests/unit/claims.sh L9: um modulo que lanca ImportError precede o
# real no PYTHONPATH.
SB="$T/sabotagem"; mkdir -p "$SB"; printf 'raise ImportError("indisponivel por fixture")\n' > "$SB/yaml.py"
rc=$(PYTHONPATH="$SB" python3 "$V" "$REPO" "$REPO/evidence/literature" >/dev/null 2>&1; echo $?)
chk "sem parser, o validador declara NAO VERIFICADO" "$rc" 2

echo "== L20. YAML sintaticamente invalido reprova, nao trava a suite inteira =="
D="$T/l20"; mkdir -p "$D"
printf 'literature_id: [nao fecha\n' > "$D/arxiv-0000.00000.yaml"
chk "YAML quebrado -> reprova (nao exit 0, nao crash)" "$(val "$D")" 1

echo "== L21. CONTRADICAO INTERNA: citacao retratada numa secao reaparece verbatim noutra =="
# ESCOPO DECLARADO (ver evidence/validate-literature.py, docstring, secao de LIMITES): este
# caso cobre so reaparicao LITERAL da string retratada. Nao existe, neste validador, deteccao
# de PARAFRASE (a mesma alegacao reescrita com outras palavras) - isso exigiria compreensao de
# linguagem que uma varredura de string nao tem como fazer honestamente. O mutante abaixo e
# construido para o que o mecanismo REALMENTE cobre: a mesma citacao entre aspas, retratada num
# campo ("... NAO existe no texto ...") e repetida verbatim, sem retratacao, noutro campo.
D="$T/l21"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
d["study_quality"]["scaffold"] = (
    'A frase "does not evaluate alternative agent frameworks" NAO existe no texto completo - '
    'era citacao inventada (fonte: verificado nesta sessao).'
)
d["limitations"] = [
    'O artigo declara "does not evaluate alternative agent frameworks" como limite central.'
]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
OUT21="$(python3 "$V" "$REPO" "$D" 2>&1)"; RC21=$?
chk "citacao retratada reaparece verbatim em limitations -> reprova" "$RC21" 1
printf '%s' "$OUT21" | grep -qF "contradicao interna"
chk "  a violacao e NOMEADA como contradicao interna (nao generica)" $? 0

echo "== L22. controle de L21: a MESMA retratacao, SEM a citacao reaparecer alhures, passa =="
D="$T/l22"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
d = doc()
d["study_quality"]["scaffold"] = (
    'A frase "does not evaluate alternative agent frameworks" NAO existe no texto completo - '
    'era citacao inventada (fonte: verificado nesta sessao).'
)
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  retratacao isolada, sem reaparicao verbatim, passa (controle de L21)" "$(val "$D")" 0

echo "== L23-L26. REGRESSAO: FP e FN medidos por revisao independente em REGRA 5 =="
# Par controlado, formato exigido pela delegacao: reproduz a FORMA REAL do campo `citation` de
# arxiv-2602.06547.yaml (titulo CORRETO citado numa frase, titulo INCORRETO retratado na frase
# seguinte, marcador "nao existe na" colado no titulo incorreto) e prova as duas pontas:
#   L23 - o titulo CORRETO, reusado alhures como fato legitimo, PASSA (era o falso positivo:
#         antes da janela de proximidade, QUALQUER aspa do campo `citation` virava "retratada").
#   L24 - controle: o titulo FABRICADO (o que de fato esta retratado), reusado alhures como
#         fato, continua REPROVANDO - prova que a correcao nao apagou a deteccao real.
#   L25 - o mesmo reuso do titulo fabricado, mas dentro de uma frase que contem a palavra
#         "inventario" (raiz "invent-", sem relacao com fabricacao) REPROVA - era o falso
#         negativo: o marcador antigo (`\binvent\w*`, sem fronteira de palavra) casava
#         "inventario" e o campo inteiro virava isento, calando a reafirmacao.
#   L26 - controle par de L25: a MESMA frase com "resumo" no lugar de "inventario" - mesmo
#         veredito (reprova). O par L25/L26 prova que uma palavra IRRELEVANTE nao muda mais o
#         resultado (antes: INVENTARIO->passa/calava, RESUMO->reprova/pegava - a mesma
#         fabricacao, dois vereditos, so pela presenca acidental de uma raiz de palavra).
D="$T/l23base"; mkdir -p "$D"
cat > "$T/l23_citation.py" <<'PY'
CITATION = (
    'Fixture, F. "Correct Fixture Title About Testing Methodology" : A Study. '
    'arXiv:0000.00000, 2026 preprint. Titulo conferido nesta sessao contra a fonte primaria, '
    'texto completo lido do zero - o titulo usado antes desta correcao '
    '("Fabricated Fixture Title Nobody Wrote") nao existe na fonte.'
)
CORRETO = "Correct Fixture Title About Testing Methodology"
FABRICADO = "Fabricated Fixture Title Nobody Wrote"
PY

D="$T/l23"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
from l23_citation import CITATION, CORRETO
d = doc()
d["citation"] = CITATION
d["limitations"] = [f'O titulo real do estudo, "{CORRETO}", descreve o achado central.']
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "L23 titulo CORRETO reusado em limitations -> passa (fix do falso positivo)" "$(val "$D")" 0

D="$T/l24"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
from l23_citation import CITATION, FABRICADO
d = doc()
d["citation"] = CITATION
d["limitations"] = [
    f'O estudo descreve seu achado central como "{FABRICADO}", conforme o resumo original.'
]
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  L24 controle: titulo FABRICADO reusado como fato -> reprova (deteccao real preservada)" "$(val "$D")" 1

D="$T/l25"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
from l23_citation import CITATION, FABRICADO
d = doc()
d["citation"] = CITATION
d["limitations"] = [f'Ver o inventario deste estudo, "{FABRICADO}", para a metodologia completa.']
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "L25 'inventario' (raiz invent- irrelevante) nao desliga mais a deteccao -> reprova" "$(val "$D")" 1

D="$T/l26"; mkdir -p "$D"
python3 - "$D/arxiv-0000.00000.yaml" <<PY
import sys, yaml
sys.path.insert(0, "$T")
from base import doc
from l23_citation import CITATION, FABRICADO
d = doc()
d["citation"] = CITATION
d["limitations"] = [f'Ver o resumo deste estudo, "{FABRICADO}", para a metodologia completa.']
yaml.safe_dump(d, open(sys.argv[1], "w"), allow_unicode=True, sort_keys=False)
PY
chk "  L26 par de L25 ('resumo' no lugar de 'inventario') -> mesmo veredito (reprova)" "$(val "$D")" 1

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=35
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "camada de literatura verde ($P/$EXPECTED)" || echo "camada de literatura VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
