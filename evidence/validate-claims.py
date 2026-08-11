#!/usr/bin/env python3
"""Validador do CLAIM LEDGER (evidence/claims/*.yaml).

POR QUE ESTE ARQUIVO EXISTE
---------------------------
Um ledger de alegacoes que apenas ARMAZENA texto e pior do que nao ter ledger: da a forma da
evidencia sem a substancia, que e precisamente o defeito que este repositorio persegue. O que
torna o ledger util nao e o formato - e ele ser FALSIFICAVEL.

Regra central, e a razao de o validador existir:

    toda referencia a evidencia e RESOLVIDA contra a suite real.
    Citar uma regressao ou um mutante que nao existe REPROVA.

O inventario de evidencia NAO e digitado aqui. E DERIVADO de tests/ a cada execucao. Uma lista
mantida a mao seria uma segunda copia da verdade, e duas copias divergem em silencio - foi
assim que este projeto comecou (README afirmando "28 assercoes" com a suite em 29).

CONTRATO DE EXTRACAO (o que conta como evidencia existente)
----------------------------------------------------------
  regressao : `echo "== <ID>. ..."` em tests/unit/*.sh
  mutante   : `mutante <ID> ...` no INICIO da linha (a chamada real da funcao `mutante()` do
              arnes de mutacao), em tests/mutation/*.sh

Os dois espacos sao lidos de diretorios DISTINTOS de proposito: sem isso, um comentario
qualquer contendo "G12" num runner de mutacao passaria a valer como mutante, e a resolucao
deixaria de discriminar.

MUTANTES FANTASMAS - defeito MEDIDO em 2026-08-11 (onda 5, D6). A versao anterior aceitava
TAMBEM `# <ID>[-: ]...` - qualquer linha de COMENTARIO comecando por um ID - como prova de
mutante. Isso aceitava MENCAO como se fosse INVOCACAO: um comentario como
"# K10 planta o caso EXATO..." (explicando outro caso, sem nunca chamar `mutante K10`) inflava
o inventario com um ID que a suite de mutacao nunca executa. Medido: inventariado=56,
invocado de fato=54, dois fantasmas (K10, L6) - e os dois sao IDs de REGRESSAO reais em
tests/unit/, entao a mesma "prova" tambem colidia com o espaco que este contrato declara
disjunto ha duas linhas. Uma claim podia citar `mutants: [K10, L6]` e passar: exercicio de
exploracao medido, com controle (`ZZ9`, que nao aparece em lugar nenhum, era rejeitado). O
CONTRATO agora exige a INVOCACAO de verdade (`mutante <ID> ...`, a chamada da funcao de mesmo
nome que cada arnes de tests/mutation/*.sh define) - mencionar um ID num comentario nao basta,
e nunca deveria ter bastado.

SCHEMA v2 - POR QUE O ENDERECO DA EVIDENCIA PASSOU A SER O CONTEUDO
------------------------------------------------------------------
Defeito MEDIDO em 2026-08-04, em auditoria externa. C-016 declarava `scope.commit: c3ffe52` e
seu `warrant` descrevia DOIS controles de push. No snapshot c3ffe52 a observacao citada continha
apenas o primeiro:

    $ git show c3ffe52:evidence/observations/...fronteira-externa... | grep -c 'Adendo\\|MERGED'
    0

O validador v1 conferia `git cat-file -e <commit>:<caminho>` - ou seja, que o ARQUIVO existia
naquele snapshot. Existia. O CONTEUDO citado, nao. A sequencia que passava:

    arquivo existia no snapshot
    + conteudo foi ampliado depois
    + a claim continuou apontando para o snapshot antigo
    + o validador aprovava

Isso viola o principio que o ledger inteiro existe para sustentar: `Evidence = Claim.Evidence`.
Ancorar em (caminho, commit) endereca um NOME. Um nome pode passar a designar outro conteudo.

v2 ancora em `blob_sha`: o hash do conteudo exato. Um endereco content-addressed nao pode
designar outro conteudo - se o conteudo muda, o endereco muda, e a claim fica visivelmente
desancorada ate ser reescrita. A reescrita e o ponto: obriga a reler se a alegacao ainda vale.

POR QUE NAO EXISTE `claim_revision`
-----------------------------------
A auditoria propos separar `subject_snapshot` (o artefato avaliado) de `claim_revision` (onde a
claim foi escrita). O primeiro esta implementado. O segundo, nao, e por impossibilidade: o SHA
do commit que CONTEM a claim nao existe enquanto a claim esta sendo escrita - seria um campo
auto-referente, preenchido a mao depois, e portanto nao verificavel. A revisao em que cada claim
foi escrita ja e recuperavel, e de forma nao falsificavel, por `git log --follow` sobre o proprio
arquivo. Um campo auto-declarado seria mais fraco que o dado que o git ja mantem.

Este e tambem o motivo de a evidencia ancorar em blob e nao em commit: o blob e calculavel ANTES
do commit (`git hash-object`), o commit nao. Content-addressing dissolve o problema do ovo e da
galinha em vez de contorna-lo.

O QUE ESTE VALIDADOR NAO FAZ - limites declarados
------------------------------------------------
  - Nao verifica que a evidencia SUSTENTA a alegacao. Ele confere que a evidencia EXISTE, que
    o `warrant` foi escrito e que os limites foram declarados. A ligacao entre evidencia e
    tese e argumento humano, e nenhum schema a valida.
  - Nao detecta duplicacao de evidencia dentro do texto da alegacao.
  - Nao contata a rede. De `evidence.ci` ele confere a FORMA (`run_id` inteiro positivo) e o que
    e checavel offline (`head_sha` e um commit DESTE repositorio). O CONCLUSION daquela execucao
    permanece NAO VERIFICADO aqui - seguir a URL numa fronteira de evidencia criaria uma
    dependencia de rede que, falhando aberto, seria pior que a ausencia da checagem.
  - Nao verifica que `blob_sha` seja alcancavel a partir de `subject_snapshot`. Nao deve: foi
    exatamente essa exigencia implicita que produziu o defeito acima. A evidencia de uma alegacao
    pode legitimamente ser registrada DEPOIS do artefato que ela avalia.
  - `git hash-object` nao aplica filtros de `.gitattributes`. Este repositorio nao tem
    `.gitattributes`; num repo com filtro de conteudo (CRLF, clean/smudge) a comparacao entre o
    blob declarado e o arquivo da arvore de trabalho poderia divergir sem que o conteudo tenha
    mudado.
"""
import os
import re
import subprocess
import sys

EXIT_OK, EXIT_VIOLACAO, EXIT_NAO_VERIFICADO = 0, 1, 2

try:
    import yaml
except ImportError:
    # DEPENDENCIA DE ORACULO ausente, nao variacao de ambiente: sem parser nao ha como decidir
    # se o ledger e valido, e "nao reprovou" seria indistinguivel de "nao foi verificado".
    sys.stderr.write(
        "NAO VERIFICADO: pyyaml ausente. O ledger nao pode ser validado neste ambiente.\n"
        "Instale a versao pinada (ver .github/workflows/verify-pr.yml).\n")
    sys.exit(EXIT_NAO_VERIFICADO)

TIPOS = {"empirical-invariant", "security-property", "runtime-observation", "method-rule"}
STATUS = {"supported-in-tested-domain", "refuted", "superseded", "not-verified"}
# `supported-in-tested-domain` e o unico status ATIVO: e o que afirma algo hoje.
STATUS_ATIVO = "supported-in-tested-domain"
# EXIGENCIA DE FRESCOR: quais status precisam que o blob ancorado ainda case com a arvore.
#
# `refuted` e `superseded` sao TERMINAIS - registro historico. O conteudo citado pode ter mudado
# desde entao, e exigir que ainda case tornaria impossivel preservar o registro de uma alegacao
# derrubada. A isencao ali e correta.
#
# `not-verified` NAO e registro historico: e alegacao ABERTA, que sera reavaliada quando o oraculo
# existir. Isenta-la do frescor foi defeito medido em 2026-08-11: ao renumerar C-018->C-019 a
# observacao foi editada, o blob_sha ficou apontando para o conteudo pre-edicao, e o validador
# saiu 0. Uma claim aberta desancorada e pior que uma fechada: ela ainda sera lida como pendencia
# viva, e a faixa `line_start/line_end` e validada contra o blob ANCORADO - com a ancora obsoleta,
# a citacao de linha tambem deixa de significar qualquer coisa.
EXIGEM_FRESCOR = frozenset({STATUS_ATIVO, "not-verified"})
OBRIGATORIOS = ("claim_id", "claim", "type", "scope", "evidence", "warrant",
                "limitations", "status")
RE_CLAIM_ID = re.compile(r"^C-[0-9]{3}$")
# Espacos de nome disjuntos de proposito: `C-001` (alegacao) nunca colide com `C1` (caso de
# regressao da suite de concorrencia). Sem esta separacao a resolucao seria ambigua.
RE_EVID_ID = re.compile(r"^[A-Z]{1,3}[0-9]{1,3}[a-z]?$")


RE_CASO = re.compile(r"""^echo\s+['"]==\s+([A-Z]{1,3}[0-9]{1,3}[a-z]?)\.""")
# SO invocacao real, nunca mencao em comentario - ver "MUTANTES FANTASMAS" no docstring do
# modulo. A forma anterior aceitava `#\s*<ID>[-: ]` e qualquer linha de COMENTARIO que comecasse
# por um ID virava "mutante", inventariando K10 e L6 (IDs de REGRESSAO reais, nunca invocados
# como mutante) - dois fantasmas medidos. `RE_MUT` cobre a chamada da funcao `mutante()` do
# arnes compartilhado (a maioria dos arquivos de tests/mutation/); `RE_CASO` (o MESMO padrao
# usado para regressao) cobre `tests/mutation/install.sh`, que nao usa aquele arnes e numera seus
# mutantes com o cabecalho `echo "== <ID>. ..."` - convencao DIFERENTE, mas igualmente uma
# INVOCACAO real (o mutante e aplicado e morto logo abaixo do echo, nao apenas mencionado): exigir
# so `RE_MUT` faria MI1..MI5 desaparecerem do inventario, e a claim C-007 (que cita MI1, um
# mutante real) passaria a reprovar por um falso NEGATIVO simetrico ao problema que esta correcao
# fecha. As duas formas sao ANCORADAS (chamada de funcao / cabecalho `echo "==`), nunca
# comentario solto - nenhuma delas reabre a classe de fantasma.
RE_MUT = re.compile(r"^mutante\s+([A-Z]{1,3}[0-9]{1,3})\b\s")
REGEXES_MUTANTE = (RE_MUT, RE_CASO)


def _extrai(texto, regexes, strip):
    """`regexes`: um `re.Pattern` unico, ou uma tupla de padroes tentados em ordem (a primeira
    que casar decide) - usado para aceitar as DUAS formas de invocacao de mutante (ver
    REGEXES_MUTANTE) sem duplicar o loop de extracao."""
    if not isinstance(regexes, tuple):
        regexes = (regexes,)
    achados = set()
    for linha in texto.splitlines():
        alvo = linha.strip() if strip else linha
        for rgx in regexes:
            m = rgx.match(alvo)
            if m:
                achados.add(m.group(1))
                break
    return achados


def _contrato_extracao_ok(por_arquivo_regressao, por_arquivo_mutante):
    """As DUAS garantias estruturais de que a resolucao por ID nao e ambigua (onda 5, D6):

    1. Nenhum ID de REGRESSAO aparece em mais de um arquivo de tests/unit/. `inventario()` funde
       tudo num set plano por design (`Evidence = Claim.Evidence` nao precisa saber DE QUE
       ARQUIVO veio um ID) - mas um set plano tambem APAGA a duplicidade em silencio: se dois
       arquivos declaram o mesmo ID, o set resolve para "existe" sem dizer qual dos dois
       documentos a claim realmente cita. Medido: `tests/unit/claims.sh` e
       `tests/unit/literatura.sh` usavam o MESMO prefixo `L` (`L1`..`L18` vs `L1`..`L22`) ate
       esta correcao renomear o segundo para `LT` - nenhuma claim citava um ID `L*`, entao a
       ambiguidade nunca produziu um falso-verde real, mas a garantia estava falsa mesmo assim.
       ESCOPO DELIBERADO: so o espaco de REGRESSAO e checado aqui. O espaco de MUTANTE tem a
       MESMA classe de duplicidade, ja hoje, entre `tests/mutation/run.sh` e `.../schedule.sh`
       (M1..M10) e entre `capabilities.sh`/`conformidade.sh`/`contrato.sh` (MC1..MC7) - e, ao
       contrario do caso acima, esta duplicidade E CITADA por claims REAIS (C-001..C-010, C-017,
       C-018). Bloquear nesta correcao quebraria o ledger inteiro por um achado que exige decidir,
       claim a claim, qual arquivo cada citacao pretendia - fora do escopo desta entrega (D6/D7).
       Registrado como risco separado; nao verificado por este validador ainda.
    2. Os dois espacos de nome (regressao, mutante) sao disjuntos - ver comentario de RE_EVID_ID.
       Uma intersecao nao-vazia e a MESMA classe de defeito do item 1 (resolucao ambigua), so que
       entre espacos em vez de dentro de um so; foi exatamente essa intersecao que os dois
       mutantes fantasmas (K10, L6) produziam antes da correcao de RE_MUT acima. Este lado E
       checado incondicionalmente: independe da duplicidade interna do espaco de mutante (item 1),
       porque uniao de conjuntos nao amplifica colisao entre espacos DIFERENTES.

    Devolve a lista de problemas encontrados; vazia significa contrato integro.
    """
    problemas = []

    dono_regressao = {}
    for nome, ids in por_arquivo_regressao.items():
        for i in ids:
            dono_regressao.setdefault(i, set()).add(nome)
    for i in sorted(dono_regressao):
        arqs = dono_regressao[i]
        if len(arqs) > 1:
            problemas.append(
                f"regressao '{i}' declarada em mais de um arquivo: {sorted(arqs)} - "
                f"resolucao ambigua (o inventario funde tudo num set plano)")

    regressoes = set().union(*por_arquivo_regressao.values()) if por_arquivo_regressao else set()
    mutantes = set().union(*por_arquivo_mutante.values()) if por_arquivo_mutante else set()
    colisao = regressoes & mutantes
    if colisao:
        problemas.append(
            f"ID presente nos DOIS espacos de nome (regressao E mutante), que este contrato "
            f"declara disjuntos de proposito: {sorted(colisao)} - uma claim que cite este ID "
            f"resolveria para os dois ao mesmo tempo, e a resolucao deixaria de discriminar")
    return problemas


def inventario(raiz):
    """Inventario do WORKTREE, por arquivo. Nunca de lista digitada: uma lista mantida a mao
    seria uma segunda copia da verdade, e duas copias divergem em silencio.

    Devolve `(regressoes, mutantes, por_arquivo)`: os dois primeiros sao os sets planos que o
    resto do modulo consome; `por_arquivo` e `{"regression": {nome: set(ids)}, "mutant": {...}}`
    - a granularidade que `_contrato_extracao_ok` precisa para detectar ID duplicado ENTRE
    arquivos, que o set plano por si so apagaria em silencio.
    """
    regressoes, mutantes = set(), set()
    por_arquivo = {"regression": {}, "mutant": {}}
    for sub, chave, rgx, strip in (("unit", "regression", RE_CASO, False),
                                   ("mutation", "mutant", REGEXES_MUTANTE, True)):
        d = os.path.join(raiz, "tests", sub)
        if not os.path.isdir(d):
            continue
        for nome in sorted(os.listdir(d)):
            if nome.endswith(".sh"):
                with open(os.path.join(d, nome), encoding="utf-8", errors="replace") as fh:
                    achados = _extrai(fh.read(), rgx, strip)
                por_arquivo[chave][nome] = achados
                if chave == "regression":
                    regressoes |= achados
                else:
                    mutantes |= achados
    return regressoes, mutantes, por_arquivo


_CACHE_SNAP = {}


def inventario_no_commit(raiz, commit):
    """Inventario derivado do SNAPSHOT QUE A CLAIM DECLARA, e nao do worktree.

    POR QUE ISTO EXISTE (portao final, 2026-08-04). `scope.commit` era DECORATIVO: o validador
    conferia apenas que o objeto git existia, e resolvia a evidencia contra o worktree. Medido:
    as 16 claims declaravam `1319931`, e nesse snapshot os mutantes MC6/MC7 e os dois arquivos
    de observacao de C-015/C-016 NAO EXISTIAM. A frase impressa - "toda evidencia citada existe
    em tests/" - era verdadeira sobre o worktree e FALSA sobre o escopo que cada claim declara.
    Uma alegacao cujo lastro nao existe no snapshot que ela propria nomeia nao esta ancorada:
    esta datada errado, que e a forma silenciosa de nao estar ancorada.

    Devolve None quando o snapshot nao pode ser lido (git ausente): nao afirmar nem negar.
    """
    if commit in _CACHE_SNAP:
        return _CACHE_SNAP[commit]
    try:
        r = subprocess.run(["git", "-C", raiz, "ls-tree", "-r", "--name-only", commit,
                            "tests/unit/", "tests/mutation/"],
                           capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            _CACHE_SNAP[commit] = None
            return None
        regressoes, mutantes = set(), set()
        for caminho in r.stdout.splitlines():
            if not caminho.endswith(".sh"):
                continue
            g = subprocess.run(["git", "-C", raiz, "show", f"{commit}:{caminho}"],
                               capture_output=True, text=True, timeout=30)
            if g.returncode != 0:
                continue
            if caminho.startswith("tests/unit/"):
                regressoes |= _extrai(g.stdout, RE_CASO, False)
            else:
                mutantes |= _extrai(g.stdout, REGEXES_MUTANTE, True)
        _CACHE_SNAP[commit] = (regressoes, mutantes)
        return _CACHE_SNAP[commit]
    except (OSError, subprocess.SubprocessError):
        _CACHE_SNAP[commit] = None
        return None


def tipo_do_objeto(raiz, sha):
    """'blob', 'commit', ... ou None se o objeto nao existe / git indisponivel."""
    try:
        r = subprocess.run(["git", "-C", raiz, "cat-file", "-t", sha],
                           capture_output=True, text=True, timeout=20)
        return r.stdout.strip() if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def blob_do_arquivo(raiz, caminho):
    """Blob sha1 do arquivo COMO ESTA na arvore de trabalho. None = indecidivel.

    `--` antes do caminho: um arquivo chamado `-x` seria lido como opcao. O caminho vem de um
    arquivo do repositorio, que num cenario de repo hostil e entrada nao confiavel.
    """
    try:
        r = subprocess.run(["git", "-C", raiz, "hash-object", "--", caminho],
                           capture_output=True, text=True, timeout=20)
        return r.stdout.strip() if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


def linhas_do_blob(raiz, sha):
    """Quantas linhas tem o conteudo daquele blob? None = indecidivel."""
    try:
        r = subprocess.run(["git", "-C", raiz, "cat-file", "blob", sha],
                           capture_output=True, text=True, timeout=30)
        return len(r.stdout.splitlines()) if r.returncode == 0 else None
    except (OSError, subprocess.SubprocessError):
        return None


# SHA COMPLETO, sempre. v1 aceitava de 7 a 40 e o ledger inteiro usava 7 - incoerente com a
# decisao de identificar evidencia por sha256 completo em toda outra fronteira deste repositorio,
# e um prefixo curto e ambiguo por construcao: colide, e a colisao e o modo de falha silencioso.
# Minusculo obrigatorio: `git rev-parse` emite minusculo, e aceitar as duas grafias faria o
# MESMO objeto ter duas representacoes no ledger.
RE_SHA = re.compile(r"^[0-9a-f]{40}$")


def commit_existe(raiz, sha):
    """Existe o commit? None = nao foi possivel decidir (git ausente).

    O valor vem de um ARQUIVO DO REPOSITORIO, que num cenario de repo hostil e entrada nao
    confiavel. Nao ha shell aqui (argv em lista), entao nao ha injecao de comando; o risco
    residual e de OPCAO: um valor comecando por '-' seria lido pelo git como flag, e nao como
    objeto. A validacao de forma ANTES da chamada fecha isso e nao depende de o git tratar
    '--' bem em `cat-file`, que nao trata.
    """
    if not RE_SHA.match(str(sha)):
        return False
    try:
        r = subprocess.run(["git", "-C", raiz, "cat-file", "-e", f"{sha}^{{commit}}"],
                           capture_output=True, timeout=20)
        return r.returncode == 0
    except (OSError, subprocess.SubprocessError):
        return None  # git indisponivel: nao afirmar nem negar


def _valida_blob(doc, obs, rec, raiz, arquivo):
    """O CONTEUDO citado e o conteudo que a claim ancorou? (v2, o coracao da correcao de C4)

    v1 conferia que o ARQUIVO existia no snapshot declarado. Existia - e o conteudo citado nao.
    Aqui o endereco e o proprio conteudo: se o arquivo mudar, `blob_sha` deixa de casar e a
    claim fica visivelmente desancorada ate ser reescrita.
    """
    e = []
    def erro(msg):
        e.append(f"{os.path.basename(arquivo)}: {msg}")

    bs = str(obs["blob_sha"])
    if not RE_SHA.match(bs):
        erro(f"evidence.observation.blob_sha '{bs}' nao e um SHA de 40 hex minusculos")
        return e

    tipo = tipo_do_objeto(raiz, bs)
    if tipo is None:
        # Nao distinguimos "git ausente" de "objeto inexistente" aqui: `commit_existe` ja
        # reprovou com a mensagem de oraculo ausente se o git nao estiver disponivel, e um
        # objeto que nao existe e reprovacao legitima nos dois casos.
        erro(f"evidence.observation.blob_sha '{bs[:12]}...' nao existe neste repositorio "
             f"(ou git indisponivel) - a evidencia citada nao tem lastro")
        return e
    if tipo != "blob":
        erro(f"evidence.observation.blob_sha aponta para um objeto '{tipo}', nao um blob")
        return e

    atual = blob_do_arquivo(raiz, rec)
    if atual is None:
        erro(f"nao foi possivel calcular o blob de '{rec}' - NAO VERIFICADO")
    elif atual != bs:
        # A CLAIM ESTA DESANCORADA. Nao e necessariamente falsa: e que o lastro citado nao e
        # mais o conteudo do arquivo, e ninguem releu se ela continua valendo. Foi exatamente
        # esta situacao que passou despercebida em C-016.
        if str(doc.get("status")) in EXIGEM_FRESCOR:
            erro(f"evidence.observation.blob_sha NAO casa com o conteudo atual de '{rec}': "
                 f"declarado {bs[:12]}..., atual {atual[:12]}.... O conteudo citado mudou "
                 f"desde que a alegacao foi ancorada - releia a alegacao e reancore.")
        # `refuted`/`superseded`: TERMINAIS, registro historico. A divergencia e esperada e o blob
        # ja foi provado existir acima. `not-verified` NAO entra aqui - ver EXIGEM_FRESCOR.

    # LINE RANGE: opcional, mas se um extremo existe o outro tambem, e ambos precisam cair
    # dentro do conteudo ANCORADO - nao do arquivo atual. Citar linha 900 de um arquivo de 200
    # linhas e uma citacao que nao resolve, e o ledger nao deve aprova-la.
    ls, le = obs.get("line_start"), obs.get("line_end")
    if (ls is None) != (le is None):
        erro("evidence.observation: 'line_start' e 'line_end' vem em par ou nenhum dos dois")
    elif ls is not None:
        if not isinstance(ls, int) or not isinstance(le, int) or isinstance(ls, bool) \
                or isinstance(le, bool):
            erro("evidence.observation: line_start/line_end devem ser inteiros")
        elif ls < 1 or le < ls:
            erro(f"evidence.observation: faixa invalida ({ls}..{le}); "
                 f"exige 1 <= line_start <= line_end")
        else:
            n = linhas_do_blob(raiz, bs)
            if n is None:
                erro(f"nao foi possivel ler o conteudo do blob {bs[:12]}... - faixa NAO VERIFICADA")
            elif le > n:
                erro(f"evidence.observation: line_end={le} passa do fim do conteudo ancorado "
                     f"({n} linhas)")
    return e


RE_RUN_ID = re.compile(r"^[0-9]{1,20}$")
_CACHE_WF = {}


def workflows_no_commit(raiz, commit):
    """Nomes de workflow declarados NAQUELE snapshot. None = indecidivel.

    POR QUE ISTO EXISTE (revisao independente do PR #5). `ci.workflow` era escrito mas nao
    validado: `workflow: workflow-que-nunca-existiu` passava. Campo com aparencia de rastro e
    sem poder de discriminacao e a versao menor do defeito que este ledger inteiro persegue.

    O nome e resolvido contra o SNAPSHOT, e nao contra o worktree, porque o workflow pode ter
    sido renomeado depois - e foi: `verify` virou `verify-pr`/`verify-push` em 8f7b543. Uma
    claim sobre c3ffe52 cita corretamente `verify`, que existia la e nao existe hoje.
    """
    if commit in _CACHE_WF:
        return _CACHE_WF[commit]
    try:
        r = subprocess.run(["git", "-C", raiz, "ls-tree", "-r", "--name-only", commit,
                            ".github/workflows/"], capture_output=True, text=True, timeout=30)
        if r.returncode != 0:
            _CACHE_WF[commit] = None
            return None
        nomes = set()
        for caminho in r.stdout.splitlines():
            if not caminho.endswith((".yml", ".yaml")):
                continue
            g = subprocess.run(["git", "-C", raiz, "show", f"{commit}:{caminho}"],
                               capture_output=True, text=True, timeout=30)
            if g.returncode != 0:
                continue
            try:
                doc = yaml.safe_load(g.stdout)
            except yaml.YAMLError:
                continue
            if isinstance(doc, dict) and doc.get("name"):
                nomes.add(str(doc["name"]))
        _CACHE_WF[commit] = nomes
        return nomes
    except (OSError, subprocess.SubprocessError):
        _CACHE_WF[commit] = None
        return None


def _valida_ci(ci, raiz, arquivo, sujeito=None):
    """`ci_run` (v1) era a URL do WORKFLOW - a mesma para toda claim, e portanto sem poder de
    identificacao: nao dizia QUAL execucao, sobre QUAL commit, com QUAL resultado. Uma referencia
    que nao discrimina nada e decoracao com forma de rastro.

    v2 exige `run_id` e `head_sha`. Nada aqui contata a rede; o que se confere e a FORMA e o que
    e checavel offline - que `head_sha` seja um commit DESTE repositorio. O `conclusion` daquela
    execucao permanece NAO VERIFICADO por este programa, e isso esta declarado no docstring.
    """
    e = []
    def erro(msg):
        e.append(f"{os.path.basename(arquivo)}: {msg}")

    if not isinstance(ci, dict):
        erro("evidence.ci deve ser um mapeamento com 'run_id' e 'head_sha' "
             "(v1 usava 'ci_run', uma URL de workflow que nao identificava execucao alguma)")
        return e
    for campo in ("run_id", "head_sha"):
        if not ci.get(campo):
            erro(f"evidence.ci.{campo} ausente")
    if e:
        return e
    if not RE_RUN_ID.match(str(ci["run_id"])):
        erro(f"evidence.ci.run_id '{ci['run_id']}' nao e um identificador numerico de execucao")
    hs = str(ci["head_sha"])
    if not RE_SHA.match(hs):
        erro(f"evidence.ci.head_sha '{hs}' nao e um SHA de 40 hex minusculos")
    else:
        ok = commit_existe(raiz, hs)
        if ok is False:
            erro(f"evidence.ci.head_sha '{hs[:12]}...' nao e um commit deste repositorio")

    # `workflow` deixou de ser decorativo: e resolvido contra os workflows que existiam NO
    # SNAPSHOT da claim. Resolver contra o worktree seria errado - `verify` existia em c3ffe52
    # e nao existe hoje, e as claims daquele snapshot o citam corretamente.
    wf = ci.get("workflow")
    if not wf:
        erro("evidence.ci.workflow ausente - sem ele nao se sabe QUAL verificacao rodou")
    elif sujeito:
        nomes = workflows_no_commit(raiz, sujeito)
        if nomes is None:
            erro("nao foi possivel ler os workflows do snapshot - "
                 "evidence.ci.workflow NAO VERIFICADO")
        elif str(wf) not in nomes:
            erro(f"evidence.ci.workflow '{wf}' nao existe no snapshot declarado "
                 f"({sujeito[:12]}...). Workflows la: {sorted(nomes) or 'nenhum'}")
    return e


def valida(doc, arquivo, regressoes, mutantes, raiz, vistos):
    e = []
    def erro(msg):
        e.append(f"{os.path.basename(arquivo)}: {msg}")

    if not isinstance(doc, dict):
        erro("o arquivo nao contem um mapeamento YAML no topo")
        return e

    for campo in OBRIGATORIOS:
        if campo not in doc or doc[campo] in (None, "", [], {}):
            erro(f"campo obrigatorio ausente ou vazio: '{campo}'")
    if e:
        return e

    cid = str(doc["claim_id"])
    if not RE_CLAIM_ID.match(cid):
        erro(f"claim_id '{cid}' fora do formato C-NNN")
    if cid in vistos:
        erro(f"claim_id '{cid}' duplicado (ja usado em {vistos[cid]})")
    else:
        vistos[cid] = os.path.basename(arquivo)
    esperado = f"{cid}.yaml"
    if os.path.basename(arquivo) != esperado:
        erro(f"nome do arquivo deveria ser '{esperado}' para casar com claim_id")

    if doc["type"] not in TIPOS:
        erro(f"type '{doc['type']}' fora do vocabulario {sorted(TIPOS)}")
    if doc["status"] not in STATUS:
        erro(f"status '{doc['status']}' fora do vocabulario {sorted(STATUS)}")

    escopo = doc.get("scope") or {}
    snap = None
    # `subject_snapshot` (v2) e o commit do ARTEFATO AVALIADO. O nome anterior, `commit`, nao
    # dizia commit DE QUE, e a ambiguidade era substantiva: a evidencia de uma alegacao pode ser
    # registrada depois do artefato que ela avalia, e o campo unico forcava os dois a coincidir.
    if not isinstance(escopo, dict) or not escopo.get("subject_snapshot"):
        erro("scope.subject_snapshot ausente - uma alegacao sem snapshot nao e verificavel")
    else:
        sujeito = str(escopo["subject_snapshot"])
        if not RE_SHA.match(sujeito):
            erro(f"scope.subject_snapshot '{sujeito}' nao e um SHA de 40 hex minusculos "
                 f"(prefixo curto e ambiguo por construcao)")
        else:
            ok = commit_existe(raiz, sujeito)
            if ok is False:
                erro(f"scope.subject_snapshot '{sujeito}' nao existe neste repositorio")
            elif ok is True:
                # A EVIDENCIA DE SUITE E RESOLVIDA CONTRA O SNAPSHOT DECLARADO, nao contra o
                # worktree. `RE_SHA` ja validou a forma antes de qualquer chamada ao git.
                snap = inventario_no_commit(raiz, sujeito)
                if snap is None:
                    erro("nao foi possivel ler o snapshot de scope.subject_snapshot - "
                         "evidencia NAO VERIFICADA contra ele")
                else:
                    regressoes, mutantes = snap
            elif ok is None:
                # ASSIMETRIA CORRIGIDA: `pyyaml` ausente ja saia 2 (NAO VERIFICADO), mas `git`
                # ausente devolvia None e o programa seguia imprimindo "ledger valido". Duas
                # dependencias de oraculo, dois tratamentos - e o silencioso era justamente o que
                # deixava TODO o snapshot sem resolucao enquanto o texto afirmava resolucao.
                erro("git indisponivel: scope.subject_snapshot NAO VERIFICADO "
                     "(dependencia de oraculo ausente, nao aprovacao)")
    if not escopo.get("platforms"):
        erro("scope.platforms ausente - alegacao sem dominio testado nao tem alcance definido")

    # `runtime` (v2, opcional): a VERSAO do sistema observado, quando a alegacao e sobre o
    # comportamento de um programa e nao sobre o repositorio. Existe porque C-015 declarava
    # `github-ubuntu-24.04` no escopo enquanto a precedencia de hooks foi medida contra um
    # Claude Code LOCAL - o runner de CI valida o repositorio, nao reproduz o runtime. Sem um
    # campo para a versao, essa informacao so cabia na prosa, e prosa nao e resolvida.
    rt = escopo.get("runtime")
    if rt is not None:
        if not isinstance(rt, dict) or not rt:
            erro("scope.runtime deve ser um mapeamento nao vazio (ex.: {claude_code: 2.1.220})")
        else:
            for k, v in rt.items():
                if v in (None, "", [], {}):
                    erro(f"scope.runtime.{k} vazio - versao nao declarada nao e versao")

    ev = doc.get("evidence") or {}
    if not isinstance(ev, dict):
        erro("evidence deve ser um mapeamento")
        return e

    refs = 0
    for chave, universo, rotulo in (("regression", regressoes, "regressao"),
                                    ("mutants", mutantes, "mutante")):
        vals = ev.get(chave) or []
        if isinstance(vals, str):
            erro(f"evidence.{chave} deve ser lista, nao string")
            continue
        for v in vals:
            v = str(v)
            refs += 1
            if not RE_EVID_ID.match(v):
                erro(f"evidence.{chave}: '{v}' fora do formato de identificador")
            elif v not in universo:
                # A REGRA CENTRAL. Sem ela o ledger seria prosa com aparencia de rastro.
                erro(f"evidence.{chave} cita {rotulo} INEXISTENTE: '{v}' "
                     f"(nao encontrado em tests/)")

    obs = ev.get("observation")
    if obs is not None:
        faltando = [k for k in ("command", "recorded", "blob_sha") if not obs.get(k)] \
            if isinstance(obs, dict) else ["command", "recorded", "blob_sha"]
        if faltando:
            erro(f"evidence.observation exige {faltando} "
                 f"(v2: 'blob_sha' ancora o CONTEUDO, nao so o nome do arquivo)")
        else:
            refs += 1
            rec = str(obs["recorded"])
            # CONFINAMENTO (auditoria de 2026-08-04). `os.path.join(raiz, x)` DESCARTA `raiz`
            # quando `x` e absoluto. Medido: uma claim cujo unico lastro era
            # `recorded: /etc/passwd` era aprovada, e o validador imprimia
            # "ledger valido: toda evidencia citada existe em tests/" - frase literalmente
            # falsa. O dano nao e a travessia: e a alegacao passar a ter lastro FORA do
            # repositorio enquanto o programa afirma que a evidencia foi resolvida.
            if os.path.isabs(rec) or ".." in rec.split("/"):
                erro(f"evidence.observation.recorded precisa ser caminho relativo dentro do "
                     f"repositorio, sem '..': '{rec}'")
            else:
                alvo = os.path.realpath(os.path.join(raiz, rec))
                base = os.path.realpath(raiz)
                if not (alvo == base or alvo.startswith(base + os.sep)):
                    erro(f"evidence.observation.recorded escapa do repositorio: '{rec}'")
                elif not os.path.isfile(alvo):
                    erro(f"evidence.observation.recorded aponta para arquivo inexistente: "
                         f"'{rec}'")
                else:
                    e.extend(_valida_blob(doc, obs, rec, raiz, arquivo))

    ci = ev.get("ci")
    if ci is not None:
        e.extend(_valida_ci(ci, raiz, arquivo,
                            str(escopo.get("subject_snapshot") or "") if isinstance(escopo, dict) else ""))

    if refs == 0:
        erro("nenhuma referencia de evidencia (regression, mutants ou observation). "
             "Uma alegacao sem lastro nao entra no ledger.")

    if not isinstance(doc.get("limitations"), list) or not doc["limitations"]:
        erro("limitations deve ser uma lista nao vazia - toda alegacao tem alcance finito")

    ce = doc.get("counterexamples")
    if ce is not None:
        if not isinstance(ce, list):
            erro("counterexamples deve ser lista")
        else:
            for i, c in enumerate(ce):
                if not isinstance(c, dict) or not c.get("commit") or not c.get("result"):
                    erro(f"counterexamples[{i}] exige 'commit' e 'result'")
    return e


def main(argv):
    raiz = os.path.abspath(argv[1]) if len(argv) > 1 else os.path.abspath(
        os.path.join(os.path.dirname(__file__), ".."))
    cdir = argv[2] if len(argv) > 2 else os.path.join(raiz, "evidence", "claims")

    regressoes, mutantes, por_arquivo = inventario(raiz)
    # AUTOCHECAGEM: inventario vazio significa que a extracao quebrou. Sem isto o validador
    # reprovaria TUDO (falso vermelho) ou, se a regex passasse a casar demais, aprovaria tudo
    # (falso verde). Em ambos os casos ele deixaria de medir o que diz medir.
    if not regressoes or not mutantes:
        sys.stderr.write(
            f"NAO VERIFICADO: extracao de inventario vazia "
            f"(regressoes={len(regressoes)}, mutantes={len(mutantes)}). "
            f"O contrato de extracao nao casa com tests/ - corrija antes de confiar no ledger.\n")
        return EXIT_NAO_VERIFICADO

    # AUTOCHECAGEM (onda 5, D6): ID duplicado entre arquivos do mesmo espaco de nome, ou
    # colisao entre os dois espacos (regressao, mutante) que este contrato declara disjuntos -
    # ver `_contrato_extracao_ok`. Mesma familia de defeito da checagem de vazio acima: a
    # extracao nao casa mais com o contrato, e "nao reprovou" seria indistinguivel de "resolveu
    # sem ambiguidade" quando na verdade nao resolveu.
    problemas_contrato = _contrato_extracao_ok(por_arquivo["regression"], por_arquivo["mutant"])
    if problemas_contrato:
        sys.stderr.write(
            "NAO VERIFICADO: contrato de extracao violado - a resolucao por ID deixou de ser "
            "nao-ambigua:\n" + "\n".join(f"  - {p}" for p in problemas_contrato) + "\n")
        return EXIT_NAO_VERIFICADO

    if not os.path.isdir(cdir):
        sys.stderr.write(f"NAO VERIFICADO: diretorio de claims inexistente: {cdir}\n")
        return EXIT_NAO_VERIFICADO

    arquivos = sorted(f for f in os.listdir(cdir) if f.endswith((".yaml", ".yml")))
    if not arquivos:
        sys.stderr.write(f"NAO VERIFICADO: nenhuma claim em {cdir}\n")
        return EXIT_NAO_VERIFICADO

    erros, vistos = [], {}
    for nome in arquivos:
        caminho = os.path.join(cdir, nome)
        try:
            with open(caminho, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except yaml.YAMLError as exc:
            erros.append(f"{nome}: YAML invalido: {exc}")
            continue
        erros.extend(valida(doc, caminho, regressoes, mutantes, raiz, vistos))

    print(f"inventario do worktree: {len(regressoes)} regressoes, {len(mutantes)} mutantes "
          f"(cada claim e resolvida contra o SEU scope.subject_snapshot, nao contra este)")
    print(f"claims lidas: {len(arquivos)}")
    if erros:
        print(f"\nVIOLACOES ({len(erros)}):")
        for x in erros:
            print(f"  - {x}")
        return EXIT_VIOLACAO
    # A FRASE E O RELATORIO. Duas versoes anteriores imprimiram uma afirmacao mais forte do que
    # o programa verificava - "existe em tests/" quando resolvia contra o worktree, e depois
    # "existe no SNAPSHOT" quando conferia o nome do arquivo e nao o conteudo. Esta enumera
    # exatamente o que foi conferido, e o que nao foi fica no docstring.
    print("ledger valido: evidencia de suite resolvida contra o subject_snapshot de cada claim; "
          "conteudo de observacao ancorado por blob_sha; ci.head_sha e commit deste repositorio.")
    print("NAO verificado aqui: o resultado das execucoes de CI citadas (exigiria rede).")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv))
