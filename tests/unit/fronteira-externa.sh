#!/usr/bin/env bash
# FRONTEIRA EXTERNA - o contexto exigido pelo required check e UNICO por SHA.
#
# POR QUE ESTA SUITE EXISTE - defeito MEDIDO, nao inferido (2026-08-04).
#
# O workflow chamava-se `verify`, disparava em `push` e em `pull_request`, e tinha um unico job
# `verify`. Sobre o head do PR #4:
#
#   $ gh api repos/MrSchrodingers/tollens/commits/ef307bf.../check-runs \
#       --jq '.total_count, (.check_runs[] | "\(.name) | \(.conclusion) | id=\(.id)")'
#   2
#   verify | success | id=92057531104
#   verify | success | id=92057522494
#
# DOIS check-runs homonimos sobre o MESMO SHA. Um required status check e identificado por NOME.
# Qual dos dois a regra avalia quando eles DIVERGEM nao foi localizado na doc primaria - a
# limitacao esta registrada em C-016. A fronteira que esta arquitetura inteira existe para tornar
# inequivoca terminava, ela propria, ambigua.
#
# A PROPRIEDADE, E A VERSAO ERRADA DELA (revisao independente do PR #5)
# --------------------------------------------------------------------
# A primeira versao desta suite exigia `jobs_decisorios == 1`: exatamente UM job em todo o
# repositorio rodando em evento de PR. Isso e mais forte do que o necessario e errado como
# propriedade - acrescentar CodeQL, um lint separado ou validacao de Dependabot em
# `pull_request`, com contexto PROPRIO, e legitimo e reprovaria a suite. Um teste que proibe
# configuracao legitima nao protege a garantia: ele treina o operador a afrouxa-lo.
#
# A propriedade correta e sobre O CONTEXTO EXIGIDO, nao sobre a populacao de jobs de PR:
#
#     |{job : contexto(job) = contexto_exigido}| = 1
#     e esse job responde a evento que decide merge.
#
# e nao:
#
#     |{job : evento(job) e decisorio}| = 1.
#
# O QUE ESTA SUITE VERIFICA, E O QUE NAO VERIFICA
# ----------------------------------------------
# VERIFICA (estatico, sobre os arquivos do repositorio):
#   - exatamente um job produz o contexto que o cabecalho manda exigir;
#   - esse job responde a `pull_request` E a `merge_group` (sem o segundo, a fila de merge nunca
#     reporta o contexto exigido e nada sai dela);
#   - nenhum contexto e produzido por mais de um job;
#   - o job exigido e o de push tem CONTRATO DE EXECUCAO equivalente - nao apenas os mesmos
#     passos, mas o mesmo runner, permissoes, env, defaults, container, servicos, matriz e
#     timeout. Passos identicos executados sob autoridades diferentes nao sao a mesma
#     verificacao, e a primeira versao desta suite comparava so `steps`.
#
# NAO VERIFICA: que o GitHub nomeie o check-run com o nome do job. Isso e comportamento de
# plataforma, nao deste repositorio, e esta MEDIDO em
# `evidence/observations/2026-08-04-contexto-unico-do-required-check.md` (claim C-017), uma vez.
# Por isso os jobs declaram `name:` explicito e igual ao job id: as duas rotas possiveis de
# nomeacao levam ao mesmo string, e a premissa deixa de decidir o resultado.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
# Parametrizavel SO para a mutacao (tests/mutation/fronteira.sh), que precisa alimentar o
# detector com um diretorio de workflows mutado. Em uso normal e o diretorio real.
WF="${FRONTEIRA_WF_DIR:-.github/workflows}"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

# DEPENDENCIA DE ORACULO, nao variacao de ambiente: sem parser YAML nao ha como decidir se a
# fronteira e unica, e "nao reprovou" seria indistinguivel de "nao foi verificado". Mesmo
# tratamento que tests/unit/claims.sh da a pyyaml: exit 2.
if ! python3 -c 'import yaml' 2>/dev/null; then
  echo "NAO VERIFICADO: pyyaml ausente - a fronteira externa nao pode ser validada aqui." >&2
  echo "Instale a versao pinada (ver .github/workflows/verify-pr.yml)." >&2
  exit 2
fi

REL="$(python3 - "$WF" <<'PY'
import glob, os, sys, yaml
from collections import Counter

wfdir = sys.argv[1]
# Eventos que DECIDEM merge. `merge_group` entra: se a fila de merge nao avaliar o contexto
# exigido, nada sai dela. `push` NAO entra - push nao decide merge.
DECISORIOS = {"pull_request", "pull_request_target", "merge_group"}

# O CONTRATO DE EXECUCAO de um job. Comparar so `steps` deixaria passar dois jobs com os mesmos
# comandos rodando em runners, permissoes ou ambientes diferentes - "a mesma verificacao" seria
# uma afirmacao sobre os comandos, nao sobre a execucao.
CHAVES_JOB = ("runs-on", "container", "services", "env", "defaults", "strategy",
              "timeout-minutes", "continue-on-error", "steps")
CHAVES_WF = ("permissions", "env", "defaults")   # herdadas pelo job

def contrato(doc, job):
    c = {k: job.get(k) for k in CHAVES_JOB}
    c["_workflow"] = {k: doc.get(k) for k in CHAVES_WF}
    return yaml.safe_dump(c, sort_keys=True)

jobs = []
arquivos = sorted(glob.glob(os.path.join(wfdir, "*.yml")) +
                  glob.glob(os.path.join(wfdir, "*.yaml")))
for caminho in arquivos:
    with open(caminho, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh)
    if not isinstance(doc, dict):
        continue
    # PyYAML resolve a chave `on:` para o booleano True (YAML 1.1). Ler as duas formas nao e
    # tolerancia: e o unico jeito de nao medir vazio e chamar isso de aprovacao.
    gat = doc.get("on", doc.get(True)) or {}
    eventos = set(gat.keys()) if isinstance(gat, dict) else (
        set(gat) if isinstance(gat, list) else {str(gat)})
    for jid, job in (doc.get("jobs") or {}).items():
        if not isinstance(job, dict):
            continue
        jobs.append({"arquivo": os.path.basename(caminho), "id": jid,
                     "contexto": str(job.get("name", jid)), "eventos": eventos,
                     "contrato": contrato(doc, job),
                     "n_passos": len(job.get("steps") or [])})

# O contexto que o cabecalho manda configurar no ruleset. So o cabecalho: varrer o corpo faria
# qualquer mencao em comentario valer como declaracao.
declarado = "-"
for caminho in arquivos:
    with open(caminho, encoding="utf-8") as fh:
        for linha in fh:
            if not linha.lstrip().startswith("#"):
                break
            if "required status check" in linha and '"' in linha:
                declarado = linha.split('"')[1]
print("contexto_declarado\t%s" % declarado)

produtores = [j for j in jobs if j["contexto"] == declarado]
print("produtores_do_exigido\t%d" % len(produtores))

if len(produtores) == 1:
    ev = produtores[0]["eventos"]
    print("exigido_e_decisorio\t%s" % ("sim" if ev & DECISORIOS else "nao"))
    print("exigido_tem_pull_request\t%s" % ("sim" if "pull_request" in ev else "nao"))
    print("exigido_tem_merge_group\t%s" % ("sim" if "merge_group" in ev else "nao"))
    print("exigido_responde_push\t%s" % ("sim" if "push" in ev else "nao"))
else:
    for k in ("exigido_e_decisorio", "exigido_tem_pull_request",
              "exigido_tem_merge_group", "exigido_responde_push"):
        print("%s\tindeterminado" % k)

colisoes = sorted(n for n, c in Counter(j["contexto"] for j in jobs).items() if c > 1)
print("colisoes\t%s" % (",".join(colisoes) if colisoes else "-"))

# Equivalencia de CONTRATO, PAREADA POR PAPEL.
#
# A versao anterior definia o gemeo por exclusao ("responde a push e nao e o exigido") e exigia
# que houvesse exatamente UM. Isso codificava a topologia de um job por arquivo, nao a
# propriedade. Quando a onda 10 separou a fronteira viva em job proprio, dois defeitos
# apareceram de uma vez: o contador quebrou (got=2), e - pior, porque silencioso - o job NOVO do
# lado do PR nao respondia a `push`, logo nao era gemeo de ninguem e ESCAPAVA inteiramente da
# checagem de paridade. Um arquivo podia ganhar job que o outro nao tem, sem reprovar.
#
# O pareamento por PAPEL fecha os dois: cada job de cada arquivo recebe uma chave de papel, e a
# exigencia passa a ser BIJECAO entre os papeis dos dois arquivos, com contrato equivalente em
# cada par. Isso e estritamente mais forte que a versao anterior - ela verificava um par, esta
# verifica todos, e acusa job orfao nos dois sentidos.
def papel(nome):
    n = nome[len("verify-"):] if nome.startswith("verify-") else nome
    if n.endswith("-push"):
        n = n[:-len("-push")]
    return "estatico" if n in ("pr", "push") else n

por_arquivo = {}
for j in jobs:
    por_arquivo.setdefault(j["arquivo"], {}).setdefault(papel(j["contexto"]), []).append(j)

arq_pr   = next((a for a in por_arquivo if "pr" in a), None)
arq_push = next((a for a in por_arquivo if "push" in a), None)
papeis_pr   = por_arquivo.get(arq_pr, {})
papeis_push = por_arquivo.get(arq_push, {})

# Papel com mais de um job no mesmo arquivo torna o pareamento ambiguo - isso e falha, nao
# detalhe: um par indeterminado nunca poderia reprovar por divergencia de contrato.
ambiguo = sorted(p for d in (papeis_pr, papeis_push) for p, v in d.items() if len(v) != 1)
orfaos  = sorted(set(papeis_pr) ^ set(papeis_push))
pares   = [(papeis_pr[p][0], papeis_push[p][0])
           for p in sorted(set(papeis_pr) & set(papeis_push)) if p not in ambiguo]

divergentes = sorted(papel(a["contexto"]) for a, b in pares if a["contrato"] != b["contrato"])
print("papeis_pr\t%s" % (",".join(sorted(papeis_pr)) or "-"))
print("papeis_orfaos\t%s" % (",".join(orfaos) or "-"))
print("papeis_ambiguos\t%s" % (",".join(ambiguo) or "-"))
print("pares_comparados\t%d" % len(pares))
print("contratos_divergentes\t%s" % (",".join(divergentes) or "-"))
# ANTIVACUIDADE: soma dos passos EFETIVAMENTE comparados. Com `steps` vazio nos dois lados,
# "equivalente" seria verdadeiro e nada teria sido comparado.
print("n_passos\t%d" % sum(a["n_passos"] for a, _ in pares))
PY
)" || { echo "FAIL: o analisador da fronteira nao executou"; exit 1; }

campo(){ printf '%s\n' "$REL" | awk -F'\t' -v k="$1" '$1==k{print $2}'; }

echo "== FE1. exatamente UM job produz o contexto exigido =="
# Nao "um unico job de PR": um unico produtor DAQUELE contexto. Adicionar CodeQL em
# `pull_request` com nome proprio e legitimo e nao pode reprovar aqui.
chk "um unico produtor do contexto exigido" "$(campo produtores_do_exigido)" "1"
chk "  e o cabecalho declara um contexto (nao '-')" \
    "$([ "$(campo contexto_declarado)" != "-" ] && echo sim || echo nao)" "sim"

echo "== FE2. o contexto exigido e produzido em evento que DECIDE merge =="
chk "responde a evento decisorio" "$(campo exigido_e_decisorio)" "sim"
# `merge_group` sozinho ja satisfaz "decisorio", e sem `pull_request` NENHUM PR receberia o
# contexto exigido - a regra ficaria exigindo algo que so a fila produz. Medido: o mutante MF2
# SOBREVIVEU a primeira versao desta assercao, que se contentava com o conjunto decisorio.
chk "  inclui pull_request (senao nenhum PR recebe o contexto)" \
    "$(campo exigido_tem_pull_request)" "sim"
# Sem `merge_group`, a fila de merge nunca reporta o contexto exigido e nada sai dela.
chk "  inclui merge_group (senao a fila de merge trava)" "$(campo exigido_tem_merge_group)" "sim"
# Se o job exigido tambem respondesse a `push`, voltaria a haver dois check-runs com o MESMO
# nome sobre o mesmo SHA - o defeito original, por outro caminho.
chk "  e NAO responde a push (senao dois check-runs homonimos por SHA)" \
    "$(campo exigido_responde_push)" "nao"

echo "== FE3. nenhum contexto e produzido por mais de um job =="
chk "sem nome de job duplicado entre workflows" "$(campo colisoes)" "-"

echo "== FE4. TODO job do arquivo de PR tem gemeo de push com CONTRATO equivalente =="
# O preco de ter dois arquivos e a chance de divergirem. Este caso e o pagamento - e compara o
# contrato inteiro (runner, permissoes, env, defaults, container, servicos, matriz, timeout,
# passos), nao apenas `steps`: passos identicos sob autoridades diferentes nao sao a mesma
# verificacao. A versao anterior comparava so `steps`, e a afirmacao ficava mais estreita que
# a frase que a acompanhava.
#
# O pareamento e por PAPEL, nao por contagem. Ver o comentario no analisador: com um job por
# arquivo, "existe exatamente um gemeo" e "todo job tem gemeo" coincidiam; com dois, a primeira
# forma deixava o job novo do lado do PR sem nenhuma checagem de paridade.
chk "nenhum papel orfao entre os dois arquivos" "$(campo papeis_orfaos)" "-"
chk "  nenhum papel ambiguo (dois jobs mesmo papel no mesmo arquivo)" "$(campo papeis_ambiguos)" "-"
chk "  contrato de execucao equivalente em TODOS os pares" "$(campo contratos_divergentes)" "-"
# ANTIVACUIDADE em dois eixos: ao menos um par comparado, e substancia dentro dos pares.
NPARES="$(campo pares_comparados)"
chk "  e houve par a comparar (nao vacuo)" \
    "$([ "${NPARES:-0}" -ge 1 ] && echo sim || echo nao)" "sim"
NPASSOS="$(campo n_passos)"
chk "  e havia substancia a comparar (nao vacuo)" \
    "$([ "${NPASSOS:-0}" -ge 10 ] && echo sim || echo nao)" "sim"

echo "== FE5. o ruleset que o cabecalho manda configurar existe de fato =="
# DRIFT DOC/MECANISMO: o cabecalho anterior mandava exigir "verify" e o job produzia "verify" -
# casava, e ainda assim estava errado, porque DOIS jobs produziam esse nome. Casar o texto com o
# mecanismo so vale junto com FE1 e FE3; isolado, seria selo. FE1 ja cobra que o contexto
# declarado tenha exatamente um produtor; aqui a assercao e que ele tenha ALGUM.
chk "o contexto declarado e produzido por algum job" \
    "$([ "$(campo produtores_do_exigido)" -ge 1 ] && echo sim || echo nao)" "sim"

echo
printf '================ PASS=%s  FAIL=%s ================\n' "$P" "$F"
if [ "$F" -eq 0 ]; then echo "fronteira externa verde ($P/$P)"; exit 0
else echo "fronteira externa VERMELHA ($F falhas)"; exit 1; fi
