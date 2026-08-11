#!/usr/bin/env python3
"""Validador da camada de qualidade de evidencia para LITERATURA EXTERNA (evidence/literature/*.yaml).

POR QUE ESTE ARQUIVO EXISTE
----------------------------
`evidence/claims/` (validate-claims.py) ancora uma AFIRMACAO DESTE REPOSITORIO em evidencia
DESTE REPOSITORIO (suite, blob, execucao de CI). Isso nao cobre um tipo diferente de citacao:
quando um documento do projeto (README, ADR, prompt de agente) invoca um PAPER EXTERNO para
justificar uma decisao. Para esse caso a pergunta nao e "essa evidencia existe" - ela existe,
o paper foi publicado - e sim "essa evidencia SE APLICA a este harness, e com que forca".

O defeito que motivou este arquivo: a secao 6.1 do README citava SWE-Skills-Bench como "39 de
49 skills sem melhoria de pass rate, ganho medio de +1,2 ponto percentual" sem o baseline
(89,8% sem skill), sem o teto de melhoria que esse baseline implica (no maximo +10,2pp), sem
declarar que o experimento usa um UNICO modelo e UNICO scaffold (o proprio artigo declara "does
not evaluate alternative agent frameworks") e sem o status de pre-print com resultados
preliminares. Cada numero isolado era verdadeiro; a citacao, no conjunto, selecionava o dado
mais favoravel ao argumento e descartava o contexto que o qualifica - recall bias, nao
fabricacao, e por isso resiste a checagem numero-a-numero.

Precedente proprio, ja registrado neste repositorio antes deste arquivo existir: `docs/adr/0011`
audita a mesma classe de defeito contra `arXiv:2606.09863` - a config citava "false success
45-89%" quando o paper reporta 45-48% / 3% / 75.8% em tres condicoes distintas. Nao existe a
faixa 45-89%. Quatro de cinco citacoes auditadas naquele ADR falharam sob a mesma regra que as
proibia. Este validador nao substitui a leitura humana da fonte primaria - nenhum programa faz
isso sem acesso ao PDF - mas impede que um numero fique na prosa argumentativa sem o contexto
que o qualifica, que foi o mecanismo concreto dos dois defeitos acima.

TRES DIMENSOES, SEPARADAS DE PROPOSITO
---------------------------------------
  provenance     : ONDE o resultado foi publicado (peer_reviewed, preprint, vendor_primary,
                   local_experiment). Nao diz nada sobre desenho metodologico.
  study_quality  : COMO o estudo foi desenhado (benchmark, n, modelos, scaffold, oraculo,
                   baseline, trials repetidos, incerteza reportada, disponibilidade de
                   codigo/dados, replicacao).
  applicability  : O QUANTO o dominio, o scaffold e o oraculo do estudo se parecem com os
                   deste repositorio.

Um estudo pode ser peer-reviewed, ter n grande e ainda ser apenas EXTRAPOLATED para este
repositorio, se foi medido num scaffold e dominio diferentes - caso de SWE-Skills-Bench
(Claude Code + Claude Haiku 4.5 unicos) contra um harness que roda Claude Code E Codex. E o
inverso tambem vale: um pre-print pode ter applicability alta quando mede exatamente a classe
de artefato que uma politica deste repositorio trata - caso dos dois estudos de seguranca de
marketplace de skill (`arxiv-2601.10338`, `arxiv-2602.06547`): nao avaliam `evidence-gate`, mas
medem risco na MESMA classe de artefato (skills) que a politica de quarentena deste
repositorio governa.

`inference_strength` - A ESCALA FECHADA, E POR QUE ELA E O CAMPO MAIS IMPORTANTE
-----------------------------------------------------------------------------------
  DIRECT       : mede o proprio artefato/mecanismo deste repositorio.
  SUPPORTED    : mede o mesmo fenomeno, em populacao/dominio proximo, com metodologia solida.
  SUGGESTIVE   : aponta na mesma direcao, mas com heterogeneidade ou lacuna metodologica
                 relevante o bastante para pesar na leitura.
  EXTRAPOLATED : modelo/scaffold/dominio unicos e distintos deste repositorio; aplicar aqui
                 exige assumir uma generalizacao que o estudo, sozinho, nao demonstra.
  SPECULATIVE  : nenhuma medicao direta; a citacao vale como plausibilidade teorica, nao como
                 evidencia de efeito.

O QUE O VALIDADOR IMPOE
-------------------------
  1. Campos obrigatorios presentes (raiz, `study_quality`, `applicability`, `findings[]`).
  2. `inference_strength` e `provenance` dentro dos vocabularios fechados.
  3. Toda afirmacao numerica tem fonte declarada, por DOIS mecanismos que se cobrem:
     a) `findings[]` e o lugar estrutural para um numero: cada item exige `metric`, `value` E
        `source` (nao vazios) - o campo `source` E a fonte declarada.
     b) qualquer OUTRA string do documento (`study_quality`, `applicability`,
        `inference_rationale`, `limitations`) que contenha um digito precisa conter, ela
        mesma, a palavra `fonte` ou `verificad` (cobre verificado/nao verificado/verificacao).
        Sem isso um numero poderia entrar pela prosa argumentativa - `inference_rationale` ou
        `applicability` - sem nunca passar pelo mecanismo de sourcing, que foi exatamente a
        rota do defeito de 6.1: um numero solto dentro de um paragrafo de argumento, sem o
        contexto que o qualifica.
     Campos bibliograficos (`literature_id`, `identifier`, `url`, `citation`, `cited_in`) ficam
     de fora da varredura (b): sao METADADOS de endereco (onde o paper esta, onde ele e citado
     no repositorio), nao afirmacoes empiricas sobre o que o paper mediu.
  4. Nome do arquivo == `literature_id` + `.yaml`, mesma disciplina de `evidence/claims`.
  5. Contradicao interna ESTRITA: se uma string do documento contem um marcador de retratacao
     (`nao existe no`/`nao existe na`, `citacao ... inventada`, `invent*`, `fabricad*`) junto de
     um trecho entre aspas retas (`"..."`, 8+ caracteres), esse MESMO trecho, palavra por
     palavra, nao pode reaparecer em NENHUM outro campo do documento sem o mesmo tipo de
     marcador por perto. Ver a secao de LIMITES abaixo: isto so cobre reaparicao VERBATIM, nao
     paráfrase - a distincao importa e esta documentada, nao e um detalhe de implementacao.

O QUE ESTE VALIDADOR NAO FAZ - limites declarados
---------------------------------------------------
  - REGRA 5 (contradicao interna) SO detecta reaparicao VERBATIM da citacao retratada. NAO
    detecta uma afirmacao retratada que reaparece como PARAFRASE em outro campo - que foi o
    defeito real corrigido em arxiv-2603.15401.yaml nesta mesma onda: a citacao inventada em
    ingles ("does not evaluate alternative agent frameworks") foi retratada em `scaffold`, mas
    a MESMA alegacao, reescrita em portugues ("declara explicitamente nao avaliar outros
    frameworks"), sobreviveu como fato em `applicability.scaffold_similarity` e em
    `limitations` - sem repetir a string retratada, portanto invisivel a um comparador de
    substring. Detectar isso exigiria reconhecer que duas sentencas com palavras DIFERENTES
    afirmam a MESMA proposicao (entailment/parafrase), o que este programa - varredura de
    string e vocabulario fechado, sem compreensao de linguagem - nao pode fazer honestamente.
    Uma aproximacao por sobreposicao de palavras-chave foi avaliada e descartada: o termo
    partilhado entre a citacao retratada e a parafrase e "frameworks", que tambem aparece em
    diversas outras frases legitimas e nao-contraditorias deste mesmo documento (ex.:
    `study_quality.scaffold`, corretamente reescrita apos a correcao) - qualquer regra ligada a
    esse termo teria ALTO falso-positivo, calibrado a um unico caso passado, nao um detector
    geral. Regra 5 fica, deliberadamente, restrita ao subconjunto que PODE ser verificado sem
    ambiguidade: string identica reaparecendo sem a marca de retratacao. A defesa real contra o
    caso de parafrase continua sendo leitura humana da fonte primaria, nao este validador.
  - Nao contata a rede, nao baixa o PDF, nao confere se o numero, o titulo, os autores ou uma
    citacao verbatim batem com o artigo. VERDE AQUI E CONFORMIDADE DE FORMA (campos presentes,
    vocabulario fechado, todo numero com um marcador de fonte declarado), NUNCA FIDELIDADE DE
    CONTEUDO A FONTE PRIMARIA. Essa conferencia so pode ser humana, com acesso a fonte, numero a
    numero e citacao a citacao.
  - PROVA CONCRETA, nao hipotetica: uma rodada anterior desta mesma camada (onda 1) declarou os
    27 casos de `tests/unit/literatura.sh` verdes e os 6 arquivos de `evidence/literature/*.yaml`
    validos com (a) o TITULO de arxiv-2602.06547 fabricado - "Malicious Agent Skills in the
    Wild: A Large-Scale Security Empirical Study", que nao existe; o titulo real e "Do Not
    Mention This to the User": Detecting and Understanding Malicious Agent Skills in the Wild
    -, (b) uma citacao verbatim INVENTADA em arxiv-2603.15401.yaml ("does not evaluate
    alternative agent frameworks", marcada como "verificado no texto completo" mas ausente da
    fonte), e (c) iniciais de autor trocadas no mesmo arquivo. Nenhuma dessas tres violacoes e
    detectavel pelos mecanismos deste programa - `citation` e campo bibliografico (fora da
    varredura de marcador de fonte, ver CAMPOS_BIBLIOGRAFICOS) e o parser YAML nao sabe o que um
    arXiv realmente diz. As tres so foram encontradas quando um agente leu a fonte primaria de
    novo, fora deste validador. Este historico e o motivo desta secao, nao um hipotetico.
  - Nao decide SE a forca de inferencia declarada esta CORRETA - confere so que o valor esta no
    vocabulario fechado. A calibracao entre o estudo e a forca de inferencia e argumento
    humano, exatamente como a ligacao entre evidencia e tese em `evidence/claims`
    (validate-claims.py, mesma limitacao declarada la).
  - Nao impede que o mesmo numero apareca com valores diferentes em dois arquivos distintos.
  - A varredura de "numero sem marcador de fonte" e um heuristico textual (regex), nao um
    parser semantico: uma string que contenha um digito por acidente (ex.: um identificador
    interno) e tratada como afirmacao numerica do mesmo jeito. O custo dessa simplicidade e
    falso positivo ocasional, corrigivel adicionando o marcador; a alternativa - permitir
    numeros soltos por padrao - e o defeito que este arquivo existe para fechar. O mesmo
    heuristico tambem e CEGO ao CONTEUDO do marcador: uma string pode conter a palavra "fonte"
    e ainda assim carregar um numero, titulo ou quote que a fonte declarada nao sustenta - o
    marcador prova que uma fonte foi APONTADA, nao que ela foi CONFERIDA.
"""
import os
import re
import sys

EXIT_OK, EXIT_VIOLACAO, EXIT_NAO_VERIFICADO = 0, 1, 2

try:
    import yaml
except ImportError:
    # DEPENDENCIA DE ORACULO ausente, nao variacao de ambiente: sem parser nao ha como decidir
    # se a camada de literatura e valida, e "nao reprovou" seria indistinguivel de "nao foi
    # verificado" (mesma razao documentada em validate-claims.py).
    sys.stderr.write(
        "NAO VERIFICADO: pyyaml ausente. A camada de literatura nao pode ser validada neste "
        "ambiente. Instale a versao pinada (ver .github/workflows/verify-pr.yml).\n")
    sys.exit(EXIT_NAO_VERIFICADO)

PROVENIENCIA = {"peer_reviewed", "preprint", "vendor_primary", "local_experiment"}
FORCA_INFERENCIA = {"DIRECT", "SUPPORTED", "SUGGESTIVE", "EXTRAPOLATED", "SPECULATIVE"}

OBRIGATORIOS = ("literature_id", "citation", "identifier", "url", "provenance",
                "study_quality", "applicability", "inference_strength",
                "inference_rationale", "findings", "limitations")

# Os DEZ subcampos de study_quality pedidos pela delegacao, verbatim: "benchmark, n, modelos,
# scaffold, oraculo, baseline, trials repetidos, incerteza reportada, codigo/dados
# disponiveis, replicado".
CAMPOS_STUDY_QUALITY = ("benchmark", "n", "models", "scaffold", "oracle", "baseline",
                        "trials_repeated", "uncertainty_reported", "code_data_available",
                        "replicated")
# Os TRES subcampos de applicability: "domain_similarity, scaffold_similarity, oracle_similarity".
CAMPOS_APPLICABILITY = ("domain_similarity", "scaffold_similarity", "oracle_similarity")

# Campos de ENDERECO (onde o paper esta, onde ele e citado) - nao sao afirmacoes empiricas e
# por isso ficam fora da varredura de "numero precisa de marcador de fonte".
CAMPOS_BIBLIOGRAFICOS = {"literature_id", "identifier", "url", "citation", "cited_in"}

RE_LITERATURE_ID = re.compile(r"^[a-z][a-z0-9]*(?:[.\-][a-z0-9]+)*$")
RE_METRIC = re.compile(r"^[a-z][a-z0-9_]*$")
RE_DIGIT = re.compile(r"\d")
# "fonte" ou "verificad" (verificado / nao verificado / verificacao) - o marcador minimo que
# obriga quem escreve a declarar, no proprio texto, de onde o numero vem ou que ele nao foi
# conferido. Case-insensitive: nao ha ganho em discriminar maiusculas aqui.
RE_MARCADOR_FONTE = re.compile(r"fonte|verificad", re.IGNORECASE)

# REGRA 5 (contradicao interna, verbatim apenas - ver docstring, secao de LIMITES, para o que
# isto NAO cobre). RE_RETRATACAO reconhece o vocabulario ja usado neste repositorio para marcar
# uma afirmacao retratada (ver arxiv-2602.06547.yaml e arxiv-2603.15401.yaml apos a correcao
# desta onda). RE_ASPAS extrai trechos entre aspas retas de 8+ caracteres - abaixo disso o risco
# de casar um fragmento generico (nome de metrica, sigla) sobe sem ganho de deteccao real.
RE_RETRATACAO = re.compile(
    r"nao existe (no|na)|citac(a|ã)o.{0,40}inventada|era citac(a|ã)o inventada|"
    r"\binvent\w*|\bfabricad\w*", re.IGNORECASE)
RE_ASPAS = re.compile(r'"([^"]{8,300})"')


def _varre_fonte(valor, caminho, violacoes):
    """Percorre recursivamente o documento (exceto o que o chamador ja excluiu) e reprova toda
    STRING que contem digito sem conter, ela mesma, um marcador de fonte declarada."""
    if isinstance(valor, dict):
        for k, v in valor.items():
            _varre_fonte(v, f"{caminho}.{k}" if caminho else str(k), violacoes)
    elif isinstance(valor, list):
        for i, v in enumerate(valor):
            _varre_fonte(v, f"{caminho}[{i}]", violacoes)
    elif isinstance(valor, str):
        if RE_DIGIT.search(valor) and not RE_MARCADOR_FONTE.search(valor):
            violacoes.append(
                f"{caminho}: contem numero sem marcador de fonte declarada "
                f"('fonte'/'verificad' ausente do proprio texto): {valor!r}")


def _coleta_folhas(valor, caminho, folhas):
    """Coleta todo par (caminho, texto) de string do documento, achatando dict/list. Usado pela
    REGRA 5 (contradicao interna) - diferente de _varre_fonte, aqui NAO ha exclusao de campo
    bibliografico: uma citacao ou titulo fabricado (campo `citation`) e exatamente o tipo de
    string que pode reaparecer, verbatim, em outro campo como se fosse fato nao-retratado."""
    if isinstance(valor, dict):
        for k, v in valor.items():
            _coleta_folhas(v, f"{caminho}.{k}" if caminho else str(k), folhas)
    elif isinstance(valor, list):
        for i, v in enumerate(valor):
            _coleta_folhas(v, f"{caminho}[{i}]", folhas)
    elif isinstance(valor, str):
        folhas.append((caminho, valor))


def _varre_contradicao(doc):
    """REGRA 5: uma citacao entre aspas marcada como RETRATADA (fonte - RE_RETRATACAO) nao pode
    reaparecer, palavra por palavra, em outro campo do documento sem a mesma marca por perto.
    Escopo estrito e documentado: cobre so reaparicao VERBATIM, nao parafrase - ver docstring do
    modulo, secao 'O QUE ESTE VALIDADOR NAO FAZ', para o porque um comparador de parafrase nao
    seria honesto aqui."""
    violacoes = []
    folhas = []
    _coleta_folhas(doc, "", folhas)
    for caminho, texto in folhas:
        if not RE_RETRATACAO.search(texto):
            continue
        for m in RE_ASPAS.finditer(texto):
            citacao = re.sub(r"\s+", " ", m.group(1).strip()).lower()
            if len(citacao) < 8:
                continue
            for outro_caminho, outro_texto in folhas:
                if outro_caminho == caminho:
                    continue
                outro_norm = re.sub(r"\s+", " ", outro_texto).lower()
                if citacao in outro_norm and not RE_RETRATACAO.search(outro_texto):
                    violacoes.append(
                        f"{caminho} retrata a citacao {m.group(1).strip()!r}, mas ela reaparece "
                        f"verbatim em {outro_caminho} sem marca de retratacao por perto - "
                        f"contradicao interna: afirmacao retratada numa secao, repetida como "
                        f"fato noutra")
    return violacoes


def _valida_findings(findings, arquivo):
    e = []
    def erro(msg):
        e.append(f"{os.path.basename(arquivo)}: {msg}")

    if not isinstance(findings, list) or not findings:
        erro("findings deve ser uma lista nao vazia - toda citacao numerica fica ancorada aqui")
        return e
    for i, f in enumerate(findings):
        if not isinstance(f, dict):
            erro(f"findings[{i}] deve ser um mapeamento com 'metric', 'value' e 'source'")
            continue
        for campo in ("metric", "value", "source"):
            if f.get(campo) in (None, ""):
                erro(f"findings[{i}].{campo} ausente ou vazio - sem 'source' o numero nao tem "
                     f"fonte declarada")
        metrica = f.get("metric")
        if isinstance(metrica, str) and metrica and not RE_METRIC.match(metrica):
            erro(f"findings[{i}].metric '{metrica}' fora do formato snake_case")
    return e


def valida(doc, arquivo, vistos):
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

    lid = str(doc["literature_id"])
    if not RE_LITERATURE_ID.match(lid):
        erro(f"literature_id '{lid}' fora do formato (letras/digitos minusculos, "
             f"separadores '-' ou '.')")
    if lid in vistos:
        erro(f"literature_id '{lid}' duplicado (ja usado em {vistos[lid]})")
    else:
        vistos[lid] = os.path.basename(arquivo)
    esperado = f"{lid}.yaml"
    if os.path.basename(arquivo) != esperado:
        erro(f"nome do arquivo deveria ser '{esperado}' para casar com literature_id")

    if doc["provenance"] not in PROVENIENCIA:
        erro(f"provenance '{doc['provenance']}' fora do vocabulario {sorted(PROVENIENCIA)}")

    if doc["inference_strength"] not in FORCA_INFERENCIA:
        erro(f"inference_strength '{doc['inference_strength']}' fora do vocabulario fechado "
             f"{sorted(FORCA_INFERENCIA)}")

    sq = doc.get("study_quality")
    if not isinstance(sq, dict):
        erro("study_quality deve ser um mapeamento")
    else:
        for campo in CAMPOS_STUDY_QUALITY:
            if campo not in sq or sq[campo] in (None, ""):
                erro(f"study_quality.{campo} ausente ou vazio")

    ap = doc.get("applicability")
    if not isinstance(ap, dict):
        erro("applicability deve ser um mapeamento")
    else:
        for campo in CAMPOS_APPLICABILITY:
            if campo not in ap or ap[campo] in (None, ""):
                erro(f"applicability.{campo} ausente ou vazio")

    if not isinstance(doc.get("inference_rationale"), str) or not doc["inference_rationale"].strip():
        erro("inference_rationale deve ser texto nao vazio explicando a forca declarada")

    e.extend(_valida_findings(doc.get("findings"), arquivo))

    if not isinstance(doc.get("limitations"), list) or not doc["limitations"]:
        erro("limitations deve ser uma lista nao vazia - todo estudo tem alcance finito")
    elif any(not isinstance(x, str) or not x.strip() for x in doc["limitations"]):
        erro("limitations nao pode conter item vazio")

    # REGRA 3(b): tudo o que NAO e campo bibliografico e NAO e a subarvore de findings (ja
    # coberta pela regra 3(a), acima) e varrido por numero sem marcador de fonte.
    resto = {k: v for k, v in doc.items() if k not in CAMPOS_BIBLIOGRAFICOS and k != "findings"}
    violacoes_fonte = []
    _varre_fonte(resto, "", violacoes_fonte)
    for v in violacoes_fonte:
        erro(v)

    # REGRA 5: contradicao interna verbatim (ver docstring do modulo e _varre_contradicao para
    # o escopo exato - so cobre reaparicao literal, nao parafrase). Roda sobre o DOCUMENTO
    # inteiro, incluindo campos bibliograficos: uma citacao ou titulo fabricado em `citation` e
    # exatamente o tipo de string que pode reaparecer, sem retratacao, em outro campo.
    for v in _varre_contradicao(doc):
        erro(v)

    return e


def main(argv):
    raiz = os.path.abspath(argv[1]) if len(argv) > 1 else os.path.abspath(
        os.path.join(os.path.dirname(__file__), ".."))
    ldir = argv[2] if len(argv) > 2 else os.path.join(raiz, "evidence", "literature")

    if not os.path.isdir(ldir):
        sys.stderr.write(f"NAO VERIFICADO: diretorio de literatura inexistente: {ldir}\n")
        return EXIT_NAO_VERIFICADO

    arquivos = sorted(f for f in os.listdir(ldir) if f.endswith((".yaml", ".yml")))
    if not arquivos:
        sys.stderr.write(f"NAO VERIFICADO: nenhuma entrada de literatura em {ldir}\n")
        return EXIT_NAO_VERIFICADO

    erros, vistos = [], {}
    for nome in arquivos:
        caminho = os.path.join(ldir, nome)
        try:
            with open(caminho, encoding="utf-8") as fh:
                doc = yaml.safe_load(fh)
        except yaml.YAMLError as exc:
            erros.append(f"{nome}: YAML invalido: {exc}")
            continue
        erros.extend(valida(doc, caminho, vistos))

    print(f"entradas de literatura lidas: {len(arquivos)}")
    if erros:
        print(f"\nVIOLACOES ({len(erros)}):")
        for x in erros:
            print(f"  - {x}")
        return EXIT_VIOLACAO
    print("camada de literatura valida: campos obrigatorios presentes; inference_strength e "
          "provenance no vocabulario fechado; toda afirmacao numerica com fonte declarada "
          "(findings[].source estrutural, ou marcador 'fonte'/'verificad' inline no restante "
          "do documento).")
    print("ESTE VERDE E FORMA, NAO FIDELIDADE A FONTE PRIMARIA: nao contata a rede, nao baixa o "
          "PDF, nao confere se titulo, autor, numero ou citacao verbatim batem com o artigo. "
          "Precedente concreto: uma rodada anterior desta camada saiu 27/27 verde com um titulo "
          "fabricado e uma citacao verbatim inventada dentro - ver docstring deste arquivo.")
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main(sys.argv))
