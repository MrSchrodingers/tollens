#!/usr/bin/env python3
"""Validador de CONFORMIDADE dos adaptadores de documento (execution/adapters/documents/*.json).

POR QUE ESTE ARQUIVO EXISTE
---------------------------
Defeito MEDIDO em 2026-08-12. `media.json` declarava `[id, class, extensions, strategy,
pipeline, gaps]` enquanto os outros tres declaravam `[id, class, version, extensions, probe,
rationale, untrusted_input, security, plans, gaps]`. O executor (`execution/document-tools/
doctool.sh`) itera `.plans[]` e le `.probe.command`; sobre um `.png` o resultado era:

    $ bash execution/document-tools/doctool.sh plans docs/brand/tollens-header-en.png
    jq: error (at .../media.json:15): Cannot iterate over null (null)     exit=5
    $ bash execution/document-tools/doctool.sh probe docs/brand/tollens-header-en.png
    {"adapter":"media","gap":{"kind":"tool_missing","tool":"null",...}}   exit=0

O adaptador tinha a FORMA de especificacao e nao respondia ao contrato do unico programa que o
consome. Nada no repositorio conferia isso: `tests/unit/supply-chain.sh` era o unico teste que
abria estes arquivos, e lia apenas `.requires.python_packages`; a CI conferia `jq -e .` (que o
arquivo forkado passava, por ser JSON valido). Um adaptador novo repetiria o defeito no mesmo
dia, e o sintoma apareceria no meio de uma sessao, como erro cru de jq.

O CONTRATO E DERIVADO DO CONSUMIDOR, NAO INVENTADO AQUI. Cada exigencia abaixo aponta para a
linha de `doctool.sh` que a torna necessaria - um schema que nao corresponda ao que o executor
le seria uma segunda copia da verdade, e duas copias divergem em silencio.

O QUE E VERIFICADO (tudo FORMA, nada de execucao)
-------------------------------------------------
  - JSON valido, objeto no topo, e o conjunto EXATO de chaves de topo: obrigatorias
    (id, class, version, extensions, probe, rationale, untrusted_input, security, plans) e
    opcionais (gaps, requires). Chave desconhecida REPROVA - foi por ADICAO de chave
    (`strategy`, `pipeline`) que o fork se instalou parecendo deliberado.
  - `id` casa com o nome do arquivo e e unico no registro; `class` e "document".
  - `version` no formato N.N.N (doctool.sh:61 le `.version // "0"`, entao a ausencia e
    silenciosa: o pack sairia com adapter_version "0" sem ninguem notar).
  - `extensions`: lista nao vazia de sufixos `.xxx` minusculos, sem repeticao dentro do
    arquivo NEM entre arquivos - a rota e decidida pelo PRIMEIRO adaptador cuja lista contem a
    extensao (doctool.sh:39-43, ordem de glob), logo duas listas sobrepostas tornam o
    roteamento dependente do nome do arquivo.
  - `probe`: `command` nao vazio, `args` lista de strings citando `$INPUT`, e `parse` em
    {raw, json, keyvalue} - as tres formas que doctool.sh:83-88 implementa. Um valor fora
    dessas cai no ramo `*` (raw) em silencio.
  - `plans`: lista nao vazia; cada plano com `id` unico, `intent` nao vazio dentro do
    vocabulario, `when` opcional, e `steps` nao vazio.
  - cada `step` com `op` no vocabulario que doctool.sh:121-130 trata, `command` nao vazio e
    `args` lista de strings.
  - TODO plano tem ao menos um step cujo `op` PRODUZ saida (locate, outline, profile, query,
    render). Um plano so de `extract` roda, escreve em diretorio descartavel e devolve
    `claims: []` - beco sem saida com aparencia de sucesso (exit 0).
  - step com `op: render` escreve em `$WORK/page*.png`: doctool.sh:126 publica o artefato com
    esse glob literal e nenhum outro. Um render que escreva com outro nome produz pack sem
    claim e sem gap.
  - PLACEHOLDERS: todo `$NOME` que aparecer em qualquer `args` precisa estar em
    {$INPUT, $WORK, $TOOLS, $TERM, $PAGE} - o conjunto que doctool.sh:51-52 substitui. Esta e a
    checagem que pega o defeito literal do fork: o `pipeline` de media.json usava `$IN`, `$OUT`
    e `$OUT_PATTERN`, que jamais foram substituidos por nada e chegariam ao comando como texto.
  - todo plano cita `$INPUT` em algum step - um plano que nunca nomeia a entrada nao processa
    o arquivo pedido.
  - `gaps` (opcional): cada entrada com `needs`, `available` booleano e `declare` nao vazio
    (`detect` opcional). Lacuna sem texto de declaracao e lacuna contornada.
  - `requires` (opcional): `python_packages` lista nao vazia de strings e `declare_if_missing`
    nao vazio - o formato que tests/unit/supply-chain.sh (S5) consome.

O QUE ESTE VALIDADOR NAO FAZ - limites declarados, para que ninguem leia garantia maior
----------------------------------------------------------------------------------------
  - NAO verifica que os comandos declarados EXISTEM nesta maquina (`ffprobe`, `pandoc`,
    `pdftotext`...). Isso e propriedade do ambiente, nao do arquivo, e o executor ja declara
    `gap: tool_missing` em tempo de execucao. Um adaptador que cite um binario inexistente
    passa aqui.
  - NAO EXECUTA nenhum plano. Nao prova que o plano produz o que promete, que o excerto e util,
    que a reducao reduz, nem que o comando faz o que o nome do `op` sugere. Conformidade de
    FORMA nao e evidencia de comportamento: quem mede comportamento e
    tests/unit/document-tools.sh, ponta a ponta contra arquivos reais.
  - NAO avalia `when`. O executor tambem nao: `when` e documentacao exibida por
    `doctool.sh plans` (linha 92), nunca uma condicao aplicada. Um `when` falso nao e detectado
    aqui nem em lugar nenhum.
  - NAO le a prosa. `rationale` e `security` precisam existir e nao estar vazios; se dizem a
    verdade sobre o adaptador e argumento humano, e nenhum schema o valida.
  - NAO confere para ONDE um step escreve (invariante D5 do executor, diretorio de trabalho
    descartavel), exceto o caso de `render` acima, que e conferido por acoplamento ao glob do
    publicador - nao por politica de escrita.
  - NAO valida os adaptadores de CODIGO (execution/adapters/code/*.json). Contrato diferente
    (analyzer/test/audit/security_lint, ver execution/adapters/README.md), consumidor
    diferente, conferido hoje pelo passo "adaptadores sao JSON valido e declaram efeitos" da
    CI. Estender este programa aquele registro e decisao separada.
  - NAO usa `packaging`: `requires.python_packages` e conferido como lista de strings nao
    vazias, nao como specifier PEP 508 resolvivel. Quem compara versao declarada com versao
    instalada e tests/unit/supply-chain.sh (S5), que carrega essa dependencia de oraculo.
"""
import json
import os
import re
import sys

EXIT_OK, EXIT_VIOLACAO, EXIT_NAO_VERIFICADO = 0, 1, 2

# Chaves de topo. O conjunto e EXATO nos dois sentidos: falta reprova, e sobra tambem - foi por
# sobra (`strategy`, `pipeline`) que o fork de media.json se apresentou como desenho proprio.
TOPO_OBRIGATORIO = ("id", "class", "version", "extensions", "probe", "rationale",
                    "untrusted_input", "security", "plans")
TOPO_OPCIONAL = ("gaps", "requires")

PLANO_OBRIGATORIO = ("id", "intent", "steps")
PLANO_OPCIONAL = ("when",)
STEP_OBRIGATORIO = ("op", "command", "args")

# Vocabularios FECHADOS, derivados do consumidor e dos adaptadores ja conformes.
CLASSE = "document"
PARSE = ("raw", "json", "keyvalue")                       # doctool.sh:83-88
INTENT = ("compare", "compute", "extract-entities", "locate", "render", "summarize", "validate")
OP = ("extract", "locate", "outline", "profile", "query", "render")   # doctool.sh:121-130
# Ops que PRODUZEM algo no pack. `extract` e preparacao: escreve em $WORK e nao vira claim.
OP_PRODUTIVO = ("locate", "outline", "profile", "query", "render")
# doctool.sh:51-52. Qualquer outro `$NOME` chega ao comando como texto literal.
PLACEHOLDERS = ("$INPUT", "$WORK", "$TOOLS", "$TERM", "$PAGE")

RE_VERSAO = re.compile(r"^[0-9]+\.[0-9]+\.[0-9]+$")
RE_EXT = re.compile(r"^\.[a-z0-9]+$")
RE_ID = re.compile(r"^[a-z][a-z0-9-]*$")
# `${VAR}` e `$VAR` - as duas grafias que um shell expandiria e que aqui NAO sao expandidas.
RE_PLACEHOLDER = re.compile(r"\$\{?([A-Za-z_][A-Za-z0-9_]*)\}?")
# doctool.sh:126 - `ls "$WORK"/page*.png | head -1`. O prefixo e literal no publicador. O arg
# pode ser o NOME final (`$WORK/page-001.png`) ou um PREFIXO ao qual a ferramenta acrescenta
# numero e extensao (`$WORK/page`, forma que `pdftoppm` exige) - as duas caem no glob.
RE_RENDER_ALVO = re.compile(r"^\$WORK/page[^/]*$")
RE_SUFIXO = re.compile(r"\.[A-Za-z0-9]+$")


def _texto_nao_vazio(valor):
    return isinstance(valor, str) and valor.strip() != ""


def _alvo_de_render(arg):
    """O arg publica o artefato pelo glob de doctool.sh:126? Aceita o nome final e o prefixo;
    se houver sufixo de extensao, ele precisa ser `.png` - `$WORK/page.jpg` seria escrito e
    nunca publicado."""
    if not isinstance(arg, str) or not RE_RENDER_ALVO.match(arg):
        return False
    return not RE_SUFIXO.search(arg) or arg.endswith(".png")


def _placeholders_estranhos(texto):
    """Os `$NOME` de `texto` que o executor NAO substitui. Checagem TEXTUAL: prova que nenhum
    nome desconhecido e usado, nunca que os conhecidos sao usados no lugar certo."""
    return [m.group(0) for m in RE_PLACEHOLDER.finditer(texto)
            if f"${m.group(1)}" not in PLACEHOLDERS]


def _valida_args(args, onde, erro):
    """`args` e lista de strings e nao usa placeholder desconhecido. Devolve o texto concatenado
    dos args validos (para as checagens que perguntam 'este plano cita $INPUT?')."""
    if not isinstance(args, list) or not args:
        erro(f"{onde}.args deve ser uma lista nao vazia de strings")
        return ""
    juntos = []
    for i, a in enumerate(args):
        if not isinstance(a, str):
            erro(f"{onde}.args[{i}] deve ser string (o executor passa cada arg por VALOR, "
                 f"sem shell - numero ou objeto nao tem substituicao definida)")
            continue
        estranhos = _placeholders_estranhos(a)
        if estranhos:
            erro(f"{onde}.args[{i}] usa placeholder que o executor nao substitui: "
                 f"{sorted(set(estranhos))} - permitidos {list(PLACEHOLDERS)}. "
                 f"O texto chegaria ao comando literalmente.")
        juntos.append(a)
    return "\n".join(juntos)


def _valida_probe(probe, erro):
    if not isinstance(probe, dict):
        erro("probe deve ser um objeto com 'command', 'args' e 'parse'")
        return
    faltando = [k for k in ("command", "args", "parse") if k not in probe]
    if faltando:
        erro(f"probe exige {faltando} (doctool.sh:67,72,83 leem os tres)")
    sobra = sorted(set(probe) - {"command", "args", "parse"})
    if sobra:
        erro(f"probe tem chave(s) desconhecida(s): {sobra}")
    if "command" in probe and not _texto_nao_vazio(probe["command"]):
        erro("probe.command vazio - doctool.sh:68 checaria a existencia do binario 'null'")
    if "parse" in probe and probe["parse"] not in PARSE:
        erro(f"probe.parse '{probe.get('parse')}' fora de {list(PARSE)} - "
             f"um valor nao previsto cai no ramo padrao (raw) em silencio")
    if "args" in probe:
        texto = _valida_args(probe["args"], "probe", erro)
        if "$INPUT" not in texto:
            erro("probe.args nao cita $INPUT - o probe nao olharia o arquivo pedido")


def _valida_plano(plano, i, ids_vistos, erro):
    onde = f"plans[{i}]"
    if not isinstance(plano, dict):
        erro(f"{onde} deve ser um objeto")
        return
    faltando = [k for k in PLANO_OBRIGATORIO if k not in plano]
    if faltando:
        erro(f"{onde} exige {faltando}")
    sobra = sorted(set(plano) - set(PLANO_OBRIGATORIO) - set(PLANO_OPCIONAL))
    if sobra:
        erro(f"{onde} tem chave(s) desconhecida(s): {sobra}")

    pid = plano.get("id")
    if not _texto_nao_vazio(pid):
        erro(f"{onde}.id vazio - e por ele que `doctool.sh run` seleciona o plano")
    else:
        onde = f"plans[{i}]({pid})"
        if pid in ids_vistos:
            erro(f"{onde}.id duplicado - doctool.sh:96 seleciona por id e nao discriminaria")
        ids_vistos.add(pid)

    intent = plano.get("intent")
    if not isinstance(intent, list) or not intent:
        erro(f"{onde}.intent deve ser lista nao vazia - sem intencao o plano nao aparece em "
             f"`doctool.sh plans <arquivo> <intent>`")
    else:
        fora = sorted({x for x in intent if x not in INTENT})
        if fora:
            erro(f"{onde}.intent tem valor fora do vocabulario: {fora} - permitidos "
                 f"{list(INTENT)}")

    if "when" in plano and (not isinstance(plano["when"], dict) or not plano["when"]):
        erro(f"{onde}.when deve ser um objeto nao vazio quando presente "
             f"(e documentacao exibida por `plans`, nao condicao avaliada)")

    steps = plano.get("steps")
    if not isinstance(steps, list) or not steps:
        erro(f"{onde}.steps deve ser lista nao vazia")
        return

    produtivo = False
    texto_do_plano = []
    for j, st in enumerate(steps):
        sonde = f"{onde}.steps[{j}]"
        if not isinstance(st, dict):
            erro(f"{sonde} deve ser um objeto")
            continue
        faltando = [k for k in STEP_OBRIGATORIO if k not in st]
        if faltando:
            erro(f"{sonde} exige {faltando}")
        sobra = sorted(set(st) - set(STEP_OBRIGATORIO))
        if sobra:
            erro(f"{sonde} tem chave(s) desconhecida(s): {sobra}")
        op = st.get("op")
        if op not in OP:
            erro(f"{sonde}.op '{op}' fora do vocabulario {list(OP)} - doctool.sh:121-130 nao "
                 f"trata outro valor, e a etapa rodaria sem entrar no pack")
        elif op in OP_PRODUTIVO:
            produtivo = True
        if not _texto_nao_vazio(st.get("command")):
            erro(f"{sonde}.command vazio")
        texto = _valida_args(st.get("args"), sonde, erro)
        texto_do_plano.append(texto)
        args_do_step = st.get("args") if isinstance(st.get("args"), list) else []
        if op == "render" and not any(_alvo_de_render(a) for a in args_do_step):
            erro(f"{sonde} tem op 'render' mas nenhum arg escreve em '$WORK/page*.png' "
                 f"(nome final ou prefixo) - doctool.sh:126 publica o artefato por esse glob "
                 f"literal; com outro nome o pack sai sem claim e sem gap")

    if not produtivo:
        erro(f"{onde} nao tem nenhum step com op produtivo {list(OP_PRODUTIVO)} - o plano "
             f"rodaria e devolveria claims vazias com exit 0 (beco sem saida silencioso)")
    if "$INPUT" not in "\n".join(texto_do_plano):
        erro(f"{onde} nao cita $INPUT em nenhum step - o plano nao processa o arquivo pedido")


def _valida_gaps(gaps, erro):
    if not isinstance(gaps, dict) or not gaps:
        erro("gaps deve ser um objeto nao vazio quando presente")
        return
    for nome, g in gaps.items():
        onde = f"gaps.{nome}"
        if not isinstance(g, dict):
            erro(f"{onde} deve ser um objeto")
            continue
        sobra = sorted(set(g) - {"needs", "available", "declare", "detect"})
        if sobra:
            erro(f"{onde} tem chave(s) desconhecida(s): {sobra}")
        if not _texto_nao_vazio(g.get("needs")):
            erro(f"{onde}.needs vazio - a lacuna precisa nomear o que falta")
        if not isinstance(g.get("available"), bool):
            erro(f"{onde}.available deve ser booleano")
        if not _texto_nao_vazio(g.get("declare")):
            erro(f"{onde}.declare vazio - lacuna sem texto de declaracao e lacuna contornada: "
                 f"o agente precisa da frase a dizer em vez de inferir o conteudo")
        if "detect" in g and not _texto_nao_vazio(g["detect"]):
            erro(f"{onde}.detect vazio")


def _valida_requires(req, erro):
    if not isinstance(req, dict):
        erro("requires deve ser um objeto")
        return
    sobra = sorted(set(req) - {"python_packages", "declare_if_missing"})
    if sobra:
        erro(f"requires tem chave(s) desconhecida(s): {sobra}")
    pk = req.get("python_packages")
    if not isinstance(pk, list) or not pk or not all(_texto_nao_vazio(x) for x in pk):
        erro("requires.python_packages deve ser lista nao vazia de strings "
             "(tests/unit/supply-chain.sh S5 a resolve contra o que a CI instala)")
    if not _texto_nao_vazio(req.get("declare_if_missing")):
        erro("requires.declare_if_missing vazio - sem a frase, a dependencia ausente vira "
             "saida vazia em vez de lacuna declarada")


def valida(doc, arquivo, ids_vistos, extensoes_vistas):
    """Erros do adaptador `arquivo`. Lista vazia significa conforme."""
    erros = []
    base = os.path.basename(arquivo)

    def erro(msg):
        erros.append(f"{base}: {msg}")

    if not isinstance(doc, dict):
        erro("o arquivo nao contem um objeto JSON no topo")
        return erros

    faltando = [k for k in TOPO_OBRIGATORIO if k not in doc]
    if faltando:
        erro(f"chave(s) obrigatoria(s) ausente(s): {faltando}")
    sobra = sorted(set(doc) - set(TOPO_OBRIGATORIO) - set(TOPO_OPCIONAL))
    if sobra:
        erro(f"chave(s) desconhecida(s): {sobra} - o schema e fechado; adaptador que inventa "
             f"campo proprio deixa de responder ao executor sem parecer quebrado")
    for k in TOPO_OBRIGATORIO:
        if k in doc and doc[k] in (None, "", [], {}):
            erro(f"'{k}' presente mas vazio")

    aid = doc.get("id")
    if not isinstance(aid, str) or not RE_ID.match(aid or ""):
        erro(f"id '{aid}' fora do formato (minusculas, digitos e hifen)")
    else:
        esperado = f"{aid}.json"
        if base != esperado:
            erro(f"id '{aid}' nao casa com o nome do arquivo (esperado '{esperado}') - "
                 f"o pack emite `adapter: id` e a rastreabilidade depende dos dois coincidirem")
        if aid in ids_vistos:
            erro(f"id '{aid}' duplicado (ja usado em {ids_vistos[aid]})")
        else:
            ids_vistos[aid] = base

    if doc.get("class") != CLASSE:
        erro(f"class '{doc.get('class')}' - este registro e de adaptadores '{CLASSE}'")

    if not isinstance(doc.get("version"), str) or not RE_VERSAO.match(str(doc.get("version"))):
        erro(f"version '{doc.get('version')}' fora do formato N.N.N - doctool.sh:61 usa "
             f"`.version // \"0\"`, entao a ausencia sairia no pack como versao '0'")

    ext = doc.get("extensions")
    if not isinstance(ext, list) or not ext:
        erro("extensions deve ser lista nao vazia")
    else:
        for e in ext:
            if not isinstance(e, str) or not RE_EXT.match(e):
                erro(f"extensions: '{e}' nao e um sufixo no formato '.xxx' minusculo - "
                     f"doctool.sh:38-41 compara com `.${{arquivo##*.}}` literal")
                continue
            if e in extensoes_vistas and extensoes_vistas[e] != base:
                erro(f"extensions: '{e}' ja declarada em {extensoes_vistas[e]} - a rota vai "
                     f"para o PRIMEIRO adaptador da ordem de glob, e o roteamento passaria a "
                     f"depender do nome do arquivo")
            elif e in extensoes_vistas:
                erro(f"extensions: '{e}' repetida no proprio arquivo")
            else:
                extensoes_vistas[e] = base

    if not _texto_nao_vazio(doc.get("rationale")):
        erro("rationale vazio - por que este formato exige plano proprio")
    if not _texto_nao_vazio(doc.get("security")):
        erro("security vazio - documento e entrada NAO CONFIAVEL, e o adaptador precisa dizer "
             "o que faz a respeito")
    if doc.get("untrusted_input") is not True:
        erro("untrusted_input deve ser true - conteudo de documento e DADO, jamais POLITICA "
             "(invariante 3 de execution/adapters/documents/README.md). Um adaptador que "
             "precise declarar outra coisa muda o invariante primeiro, nao este campo.")

    if "probe" in doc:
        _valida_probe(doc["probe"], erro)

    planos = doc.get("plans")
    if not isinstance(planos, list) or not planos:
        erro("plans deve ser lista nao vazia - doctool.sh:92 e :96 iteram `.plans[]`; sem ela "
             "`plans` e `run` saem com erro cru de jq e o formato fica sem caminho sancionado")
    else:
        ids_de_plano = set()
        for i, p in enumerate(planos):
            _valida_plano(p, i, ids_de_plano, erro)

    if "gaps" in doc:
        _valida_gaps(doc["gaps"], erro)
    if "requires" in doc:
        _valida_requires(doc["requires"], erro)
    return erros


def main(argv):
    diretorio = argv[1] if len(argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
        "execution", "adapters", "documents")

    if not os.path.isdir(diretorio):
        sys.stderr.write(f"NAO VERIFICADO: registro de adaptadores inexistente: {diretorio}\n")
        return EXIT_NAO_VERIFICADO
    arquivos = sorted(f for f in os.listdir(diretorio) if f.endswith(".json"))
    if not arquivos:
        sys.stderr.write(f"NAO VERIFICADO: nenhum adaptador em {diretorio}\n")
        return EXIT_NAO_VERIFICADO

    erros, ids_vistos, extensoes_vistas = [], {}, {}
    for nome in arquivos:
        caminho = os.path.join(diretorio, nome)
        try:
            with open(caminho, encoding="utf-8") as fh:
                doc = json.load(fh)
        except (json.JSONDecodeError, OSError) as exc:
            erros.append(f"{nome}: JSON ilegivel: {exc}")
            continue
        erros.extend(valida(doc, caminho, ids_vistos, extensoes_vistas))

    print(f"adaptadores lidos: {len(arquivos)} em {diretorio}")
    if erros:
        print(f"\nVIOLACOES ({len(erros)}):")
        for x in erros:
            print(f"  - {x}")
        return EXIT_VIOLACAO
    # A FRASE E O RELATORIO: enumera o que foi conferido, e nada alem. O que nao foi conferido
    # esta no docstring, sob "O QUE ESTE VALIDADOR NAO FAZ".
    print("registro conforme: schema de topo fechado; id/extensao sem colisao; probe com parse "
          "conhecido; todo plano com step produtivo e apenas placeholders que o executor "
          "substitui; lacunas com texto de declaracao.")
    print("NAO verificado aqui: que os comandos declarados existam nesta maquina, e que algum "
          "plano produza o que promete (nada e executado).")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv))
