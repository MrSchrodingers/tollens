#!/usr/bin/env bash
# CADEIA DE SUPRIMENTOS do gate externo. Toda dependencia que a CI executa precisa ser pinada.
#
# Existe porque eu reintroduzi o defeito depois de corrigi-lo: numa rodada pinei checkout, ruff,
# pandas e openpyxl; na seguinte adicionei `pymupdf` sem versao. Terceira ocorrencia da mesma
# classe na mesma sessao (adaptador .NET declarado errado, pandas nao declarado, pymupdf nao
# pinado). Regra enunciada nao e regra executada - por isso ela vira teste.
#
# Tag e MUTAVEL: `actions/checkout@v4` pode apontar para outro commit amanha. Numa fronteira que
# decide se um artefato atravessa, a entrada precisa ser identificavel, nao apenas nomeada.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
# WF parametrizavel SO para teste de propriedade (tests/unit/propriedades.sh), que precisa
# alimentar o detector com variantes de formatacao. Em uso normal e o diretorio real.
WF="${SUPPLY_CHAIN_WF_DIR:-.github/workflows}"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

echo "== S1. toda action e pinada por SHA completo, nunca por tag =="
# DEFEITO MEDIDO (2026-08-04, tests/unit/propriedades.sh): o recorte era `${line#*uses: }`, com
# UM espaco literal. Com `uses:  actions/checkout@v4` (dois espacos) o prefixo casava ate o
# primeiro espaco, sobrava " actions/..." comecando por espaco, e `${ref%% *}` devolvia string
# VAZIA - que nao casa nenhum padrao do `case`, e a action nao pinada passava batida.
# Um detector de seguranca que depende do numero de espacos nao e detector.
BAD=""
while IFS= read -r line; do
  ref="${line#*uses:}"
  ref="${ref#"${ref%%[![:space:]]*}"}"   # descarta espaco inicial, quantos forem
  ref="${ref%% *}"
  case "$ref" in
    */*@[0-9a-f]*) sha="${ref##*@}"
      [ "${#sha}" -eq 40 ] || BAD="$BAD $ref" ;;
    */*@*) BAD="$BAD $ref" ;;
  esac
done < <(grep -h "uses:" "$WF"/*.yml 2>/dev/null)
chk "nenhuma action por tag ou SHA curto" "${BAD:-nenhuma}" "nenhuma"

echo "== S2. todo pacote pip tem versao exata =="
# DEFEITO MEDIDO (2026-08-04): o filtro era `grep "^'"`, isto e, so enxergava tokens iniciados
# por ASPA SIMPLES. Medido: `pip install requests` e `pip install "requests"` PASSAVAM - um
# pacote sem pinagem atravessava o gate inteiro apenas por nao estar entre aspas simples.
# Era a propria classe que S2 existe para impedir (o `pymupdf` sem versao), sobrevivendo a
# regra por diferenca de formatacao.
#
# Agora a tokenizacao e do COMANDO, nao do aspecto: tudo depois de `pip install` vira token,
# aspas de qualquer tipo sao removidas, flags e continuacao de linha sao descartadas, e o que
# resta e especificacao de pacote e precisa de `==`.
# A REGRA CRESCEU NA ONDA 10, exatamente como o limite abaixo previa que teria de crescer.
#
# O texto anterior dizia, verbatim: "`-r requirements.txt` faria o caminho ser lido como pacote.
# Este workflow nao usa essa forma; se passar a usar, o caso reprova e a regra tera de crescer -
# reprovar por forma nao prevista e o comportamento correto numa fronteira de evidencia."
# A onda 10 passou a usar essa forma, e S2 reprovou com `got=install/requirements-ci.txt`. O
# detector acertou; o que faltava era o caso.
#
# E a forma nova nao e equivalente a antiga: `==` inline pinava so a VERSAO DE TOPO. O fecho
# transitivo (numpy, python-dateutil, pytz, six, tzdata, et-xmlfile) entrava livre e sem hash.
# Entao S2 nao apenas aceita `-r`: ele passa a exigir MAIS quando a forma e `-r`, porque um
# arquivo de requisitos sem hash seria um retrocesso disfarcado de melhoria.
BAD=""; REQS=""; SEM_HASH=""; SEM_FLAG=""
while IFS= read -r line; do
  rest="${line#*pip install}"
  case "$rest" in *--require-hashes*) tem_flag=sim ;; *) tem_flag=nao ;; esac
  # `read -ra` divide por IFS sem expandir glob; `for tok in $rest` expandiria `*` contra o
  # diretorio corrente e poderia inventar tokens.
  read -ra toks <<<"$rest"
  esperando_arquivo=nao
  for tok in "${toks[@]}"; do
    tok="${tok%\"}"; tok="${tok#\"}"; tok="${tok%\'}"; tok="${tok#\'}"
    if [ "$esperando_arquivo" = sim ]; then
      esperando_arquivo=nao
      REQS="$REQS $tok"
      [ "$tem_flag" = sim ] || SEM_FLAG="$SEM_FLAG $tok"
      continue
    fi
    case "$tok" in
      -r|--requirement) esperando_arquivo=sim; continue ;;
      -r*) REQS="$REQS ${tok#-r}"; [ "$tem_flag" = sim ] || SEM_FLAG="$SEM_FLAG ${tok#-r}"; continue ;;
      ""|"\\"|-*) continue ;;
      *==*) ;;
      *) BAD="$BAD $tok" ;;
    esac
  done
done < <(grep -h "pip install" "$WF"/*.yml 2>/dev/null)
# O ROTULO DESTA LINHA E CONTRATO, nao prosa. `tests/unit/propriedades.sh:62` casa a substring
# 'nenhum pacote pip sem' para extrair o veredito ao alimentar este detector com variantes de
# formatacao. Na onda 10 eu o renomeei para "...pip inline sem ==" e as 9 propriedades passaram
# a reportar `got=` VAZIO - veredito nenhum, nao veredito errado. Acoplamento por string, sem
# ninguem o declarar; fica declarado aqui.
chk "nenhum pacote pip sem ==" "${BAD:-nenhum}" "nenhum"
chk "  todo -r vem com --require-hashes no MESMO comando" "${SEM_FLAG:-nenhum}" "nenhum"

# Cada arquivo de requisitos referenciado precisa existir e ter hash para TODO pacote. Sem esta
# parte, `-r` seria um buraco: o detector veria uma flag e nao o conteudo.
for req in $REQS; do
  if [ ! -f "$req" ]; then SEM_HASH="$SEM_HASH ${req}(inexistente)"; continue
  fi
  falt="$(awk '
    /^[[:space:]]*#/ {next}
    /^[[:space:]]*$/ {next}
    /^[a-zA-Z0-9._-]+==/ { if (pkg != "" && !viu) print pkg; pkg=$1; sub(/==.*/,"",pkg); viu=0 }
    /--hash=sha256:/ { viu=1 }
    END { if (pkg != "" && !viu) print pkg }
  ' "$req" | tr '\n' ' ')"
  [ -n "$falt" ] && SEM_HASH="$SEM_HASH ${req}:[${falt% }]"
done
chk "  todo pacote do fecho tem ao menos um --hash" "${SEM_HASH:-nenhum}" "nenhum"
# ANTIVACUIDADE: um arquivo de requisitos vazio satisfaria as duas assercoes acima sem conter
# nada. A pinagem de topo esta hoje NO ARQUIVO, nao no comando, entao a substancia esta aqui.
#
# CONDICIONADA A EXISTIR `-r`, e isso nao e afrouxamento. Quando a CI pina inline, N_PKG=0 e o
# estado CORRETO, e a substancia e conferida pela primeira assercao de S2. Exigir pacote em
# arquivo que ninguem referencia reprovaria uma CI correta - foi o que aconteceu ao rodar
# tests/unit/propriedades.sh, que alimenta este detector com fixtures sem `-r`. Com `-r`
# presente a exigencia volta a valer integralmente, que e onde ela discrimina.
N_PKG=0
for req in $REQS; do
  [ -f "$req" ] && N_PKG=$((N_PKG + $(grep -cE '^[a-zA-Z0-9._-]+==' "$req")))
done
if [ -z "${REQS// /}" ]; then
  SUBSTANCIA=sim   # nao ha arquivo de requisitos: a pinagem inline responde por S2
elif [ "$N_PKG" -ge 7 ]; then
  SUBSTANCIA=sim
else
  SUBSTANCIA=nao
fi
chk "  e havia pacote a conferir (nao vacuo)" "$SUBSTANCIA" "sim"

echo "== S3. o runner e uma imagem nomeada, nao 'latest' =="
chk "runs-on nao usa -latest" \
    "$(grep -h "runs-on:" "$WF"/*.yml | grep -c -- "-latest" | tr -d ' ')" "0"

echo "== S4. dependencia de sistema NAO pinada e DECLARADA, nao silenciosa =="
# TERMINOLOGIA: isto compra AUDITABILIDADE, nao reprodutibilidade. `ubuntu-24.04` fixa a familia
# da imagem, nao seu digest, e `apt-get update` consulta o estado corrente do repositorio: duas
# execucoes em datas diferentes podem instalar versoes diferentes. Registrar as versoes permite
# saber DEPOIS o que rodou; nao torna o build hermetico. Hermeticidade exigiria container por
# digest ou snapshot de repositorio apt - fase posterior.
# apt no runner nao tem pinagem estavel: fixar a versao quebra quando a imagem atualiza. O
# honesto e registrar a excecao no proprio workflow, para que ela seja uma decisao visivel e
# nao um esquecimento indistinguivel dos outros.
if grep -qE "apt-get.*install" "$WF"/*.yml 2>/dev/null; then
  chk "a excecao do apt esta justificada por escrito" \
      "$(awk '/- name:/{blk=""} {blk=blk $0 "\n"} /apt-get.*install/{print blk; exit}' "$WF"/*.yml | grep -qi "EXCECAO DECLARADA" && echo sim || echo nao)" "sim"
fi

echo "== S5. a CI instala versao COMPATIVEL com o que os adaptadores declaram =="
# Antes so conferia o NOME: `pandas>=2.2` declarado com `pandas==1.5.0` instalado passava,
# porque o constraint era removido com sed antes de comparar. Presenca nao e compatibilidade.
# PRE-REQUISITO DE ORACULO, nao capacidade opcional: sem `packaging` esta assercao nao pode
# ser avaliada, e a suite inteira precisa reprovar. Ausencia de oraculo e NAO VERIFICADO.
if ! python3 -c "import packaging.requirements" 2>/dev/null; then
  echo "  DEPENDENCIA DE ORACULO AUSENTE: python3-packaging."
  echo "  Sem ela S5 nao pode comparar versao instalada com specifier declarado."
  echo "  Estado: NAO VERIFICADO - a suite nao foi realizada."
  exit 2
fi
S5="$(python3 - <<'PY'
import glob, json, os, re, sys
from packaging.requirements import Requirement
from packaging.version import Version

# O QUE A CI INSTALA, lido das DUAS formas. Ate a onda 10 so existia a inline (`'pandas==2.2.3'`
# no comando); agora existe tambem `-r install/requirements-ci.txt`. Ler so a primeira faria S5
# reportar "declarado, NAO instalado pela CI" para pacotes que a CI instala de fato - falso
# positivo que empurraria alguem a afrouxar a regra em vez de ler o arquivo certo.
inst = {}
def anota(nome, versao):
    inst[nome.lower()] = versao

for wf in glob.glob(".github/workflows/*.yml"):
    texto = open(wf).read()
    for line in texto.splitlines():
        if "pip install" not in line: continue
        for tok in re.findall(r"'([^']+)'", line):
            if "==" in tok:
                n, v = tok.split("==", 1); anota(n, v)
        # `-r arquivo` e `-r=arquivo`, com ou sem aspas
        for req in re.findall(r"(?:-r|--requirement)[=\s]+['\"]?([^'\"\s]+)", line):
            if not os.path.isfile(req): continue
            for rl in open(req):
                rl = rl.strip()
                if not rl or rl.startswith("#") or rl.startswith("--"): continue
                m = re.match(r"^([A-Za-z0-9._-]+)==([^\s\\;]+)", rl)
                if m: anota(m.group(1), m.group(2))
prob = []
for a in glob.glob("execution/adapters/documents/*.json"):
    for raw in (json.load(open(a)).get("requires") or {}).get("python_packages", []):
        r = Requirement(raw); n = r.name.lower()
        if n not in inst: prob.append(f"{r.name}: declarado, NAO instalado pela CI"); continue
        if r.specifier and not r.specifier.contains(Version(inst[n]), prereleases=True):
            prob.append(f"{r.name}: CI instala {inst[n]}, incompativel com '{r.specifier}'")
print("OK" if not prob else "; ".join(prob))
PY
)"
chk "versao instalada satisfaz o specifier declarado" "$S5" "OK"

echo "== S6. a dependencia do proprio ORACULO tambem e pinada na CI =="
# Sem isto, S5 e obrigatorio localmente e indefinido no ambiente remoto - a garantia teria uma
# fronteira onde nao se aplica, que e o mesmo defeito com outra forma.
# A busca cobre as duas formas: token inline no comando, ou linha no arquivo de requisitos que o
# comando referencia. Procurar so a primeira dava `nao` para uma CI que pina corretamente.
S6=nao
grep -h "pip install" "$WF"/*.yml | grep -q "'packaging==" && S6=sim
for req in $REQS; do
  [ -f "$req" ] && grep -qE '^packaging==' "$req" && S6=sim
done
chk "packaging pinado na CI (inline ou no arquivo de requisitos)" "$S6" "sim"

echo
echo "================ PASS=$P  FAIL=$F ================"
EXPECTED=9   # invariante FIXO: nenhum caso pode sumir reduzindo o esperado
# Subiu de 6 para 9 na onda 10: S2 ganhou tres assercoes (a flag --require-hashes acompanha todo
# -r; todo pacote do fecho tem hash; e a antivacuidade de que havia pacote a conferir). Subir
# este numero sem as assercoes correspondentes seria o defeito que ele existe para pegar.
if [ "$P" -ne "$EXPECTED" ]; then echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED"; exit 1; fi
[ "$F" -eq 0 ] && echo "cadeia de suprimentos verde ($P/$EXPECTED)" || echo "cadeia de suprimentos VERMELHA"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
