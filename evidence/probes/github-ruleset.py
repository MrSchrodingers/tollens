#!/usr/bin/env python3
"""PROBE - mede Applies(P,r) no SERVIDOR. Fecha o quantificador que faltava.

POR QUE ESTE ARQUIVO EXISTE
----------------------------
A formula publicada era:

    ExternalGate(P,a) <=> RequiredCheck(P) ^ not Bypass(a,P)

e ficava SATISFEITA com o ruleset 20385799 em `enforcement: active`, `bypass_actors: []`,
exigindo `verify-pr`, enquanto `conditions.ref_name.include` era `[]` - isto e, a regra nao se
aplicava a ref nenhuma. Faltava o termo de aplicabilidade. A propriedade correta:

    Gate(P,a,r) <=> Applies(P,r) ^ Required(P) ^ not Bypass(a,P)

`tests/unit/fronteira-externa.sh` e ESTATICO: le os arquivos de workflow deste repositorio.
Ele nunca observa o SERVIDOR, e o defeito acima era, por definicao, invisivel a essa leitura -
o YAML dos workflows nunca mudou, so a configuracao do ruleset no GitHub mudou. Este probe MEDE
o lado que a suite estatica nao alcanca, contra o endpoint AUTORITATIVO:

    GET /repos/{owner}/{repo}/rules/branches/{branch}

que e o proprio GitHub resolvendo, no servidor, quais regras de quais rulesets ATIVOS se
aplicam aquela ref - a mesma resolucao que decide se um push e aceito ou recusado. Uma resposta
VAZIA significa Applies(P,r) = False para toda regra: nenhuma se aplica. Isso e FALHA, nunca
silencio - foi exatamente essa a forma do defeito medido em 2026-08-10.

DOUTRINA FAIL-CLOSED (a mesma de evidence/hooks/verify-gate.sh)
-----------------------------------------------------------------
`verify-gate.sh` trata lacuna de oraculo (ferramenta ausente, dependencia estrutural ausente,
identidade que nao pode ser calculada) como NAO VERIFICADO / exit 2 - nunca como aprovacao.
Este probe segue a mesma doutrina para a rede e a API:

  - `gh` (GitHub CLI) ausente do PATH        -> NOT_VERIFIED, exit 2.
  - `gh api` falha (sem token, sem rede,        NOT_VERIFIED, exit 2. Nao se distingue 401 de
    401, 404, timeout, DNS, 5xx)              -> rede indisponivel: em ambos os casos o oraculo
                                                  nao respondeu, e a causa exata nao muda a
                                                  conclusao (nao verificado).
  - resposta que nao e JSON valido           -> NOT_VERIFIED, exit 2.
  - resposta VAZIA (nenhuma regra ativa)     -> FAIL, exit 1. Este e Applies(P,r) = False.
  - regras se aplicam mas nenhuma delas e
    `required_status_checks`, ou o contexto
    exigido nao esta entre as que produzem  -> FAIL, exit 1. Required(P) = False.
  - `strict_required_status_checks_policy`
    desligado em alguma regra aplicavel     -> FAIL, exit 1 (branch pode ficar desatualizada
                                                  e ainda assim mergear).
  - bypass_actors nao vazio, ou
    `current_user_can_bypass` != "never"    -> FAIL, exit 1. Bypass(a,P) = True para algum a.
  - `gh api rulesets/{id}` falha para UM dos
    rulesets aplicaveis (rede, 403, etc.)     -> "nao medido" para ESSE ruleset; o laco
                                                  CONTINUA para os demais (ver precedencia abaixo).
  - resposta de rulesets/{id} que nao e
    um objeto (oraculo malformado)          -> "nao medido" para esse ruleset, nunca
                                                  AttributeError/exit 1 (mesma continuacao acima).
  - `bypass_actors` ou `current_user_can_bypass`
    AUSENTES da resposta do ruleset         -> NOT_VERIFIED, exit 2 (a menos que outro campo
                                                  medido ja prove FAIL - ver abaixo). A API so
                                                  devolve `bypass_actors` a quem tem acesso de
                                                  escrita ao ruleset ("Get a repository ruleset",
                                                  https://docs.github.com/en/rest/repos/rules).
                                                  Um GITHUB_TOKEN de Actions com `contents: read`
                                                  (o perfil de execucao agendada) nao tem essa
                                                  permissao: o campo nao vem, e ausencia nao e
                                                  "medido: ninguem burla". `or []` sobre um campo
                                                  nao devolvido era exatamente essa confusao.
  - `bypass_actors` presente e `null`,
    ou de tipo que nao e lista              -> NOT_VERIFIED, exit 2, mesma doutrina do item
                                                  acima. Um valor nulo nao e "medido: []" - so a
                                                  CHAVE ausente tinha guard; o VALOR nulo e o
                                                  tipo errado (ex.: string) eram a mesma classe de
                                                  defeito, um passo adiante: `or []` colapsava
                                                  null em vazio, e um tipo nao-lista estourava
                                                  TypeError nao tratado em vez de NOT_VERIFIED.
  - tudo acima satisfeito                    -> PASS, exit 0.

Quando ha violacao PROVADA (bypass_actors nao vazio, current_user_can_bypass!=never,
enforcement!=active, strict desligado, incluindo strict medido ANTES de resolver bypass) E, em
outro ruleset aplicavel, um campo nao foi divulgado OU o proprio ruleset nao pode ser lido
(rede, 403, resposta malformada), o resultado e FAIL, nao NOT_VERIFIED: Bypass(a,P)=True ou a
politica ja esta demonstrado(a), e rebaixar isso para "nao medido" esconderia um problema real
atras de uma lacuna de permissao ou de rede. Nenhum ponto do laco que resolve bypass RETORNA
cedo por isso: toda lacuna de medicao vira entrada acumulada, e quem decide entre FAIL e
NOT_VERIFIED e sempre o portao final, depois que o laco inteiro roda.

NUNCA "PASS porque o YAML parece certo". O YAML nunca entra nesta decisao.

CLIENTE DE API - A FRONTEIRA QUE OS TESTES STUBAM
--------------------------------------------------
A unica fronteira de rede deste programa e o subprocesso `gh api <path>`. Nao ha chamada de
rede direta (urllib/requests): delegar a autenticacao ao `gh` CLI evita reimplementar o
tratamento de token, e casa com a convencao ja usada nas observacoes deste repositorio
(`evidence/observations/*.md` citam `gh api` diretamente). `tests/unit/fronteira-viva.sh`
substitui o BINARIO `gh` por um stub determinístico mais cedo no PATH - a mesma tecnica que
`tests/unit/regressao-gate.sh` usa para simular ferramentas ausentes ou com comportamento
controlado - e nao chama nenhuma rede de verdade.

SCHEMA NA FRONTEIRA (wave4, 2026-08-11) - por que a validacao campo-a-campo parou de escalar
-----------------------------------------------------------------------------------------------
Ate aqui, cada onda de correcao fechou um NIVEL da mesma forma de defeito sobre `bypass_actors`
(chave ausente, depois valor nulo, depois tipo do container) escrevendo um `elif` novo. Uma
revisao independente mediu que o padrao nao converge - ele so descobre o proximo nivel:

  C1 - `ruleset_id` ausente em PARTE das regras `required_status_checks` aplicaveis: a regra
       sem `ruleset_id` desaparecia do conjunto sem deixar rastro em `nao_medidos`, e o portao
       emitia PASS com a afirmacao UNIVERSAL "bypass_actors=[] em todos os rulesets de origem"
       sem ter resolvido bypass daquela regra.
  C2 - o guard de tipo cobria o CONTAINER (`isinstance(bypass_actors, list)`) mas nao o
       ELEMENTO: uma lista de strings (`["OrganizationAdmin"]`) passava o guard e estourava
       `TypeError` em `{"ruleset_id": rid, **a}`.
  A1 - `parameters` nunca teve guard: `r.get("parameters") or {}` sobre uma string estourava
       `AttributeError` no primeiro `.get()` seguinte.
  A2 - ausencia de `enforcement`/`strict_required_status_checks_policy` era COAGIDA em violacao
       (`enforcement='None'`, `bool(None) == False`) em vez de registrada como nao medida - o
       inverso exato da doutrina que o resto deste arquivo declara.

Em vez de um quinto `elif`, este modulo valida CADA CAMPO decisivo das duas respostas (a lista
de `rules/branches/{branch}` e o objeto de `rulesets/{id}`) contra um schema declarativo (ver
`valida_campo` abaixo) ANTES de qualquer decisao de negocio ler o valor. `valida_campo` e o
UNICO ponto que decide "AUSENTE" vs "NULO explicito" vs "TIPO errado" vs "ELEMENTO invalido
dentro de uma lista do tipo certo" - a mesma distincao de quatro vias, para qualquer campo, em
vez de reescrita por campo. Um campo NAO conformar nunca vira PASS por omissao, nunca vira uma
excecao nao tratada, e nunca vira um valor coagido (`None` -> `'None'`, ausencia -> `False`):
vira uma entrada nomeada em `nao_medidos`, que o portao final (inalterado desde a onda 3)
resolve com a MESMA precedencia ja estabelecida - FAIL vence NOT_VERIFIED quando ambos se
aplicam. Isso vale tambem para `Required(P)`: se uma regra `required_status_checks` aplicavel
nao pode ser lida por completo (parametros malformados, item de `required_status_checks`
ilegivel), o contexto ausente do conjunto lido NAO prova mais `Required(P) = False` sozinho -
prova NOT_VERIFIED, porque a regra ilegivel PODERIA te-lo exigido. So quando NENHUMA regra
aplicavel ficou ilegivel e o contexto ainda assim nao aparece e que `Required(P) = False` e
uma conclusao medida, nao suposta.

O SEXTO CAMPO, ANTES DO SCHEMA (wave5, 2026-08-11) - o filtro que alimenta o schema
-----------------------------------------------------------------------------------------------
`valida_campo` fecha a classe de formas invalidas de um campo JA LIDO - mas o filtro que decide
QUAIS elementos de `rules/branches/{branch}` chegam a ser lidos como `required_status_checks`
nunca passava por ele: `rsc = [r for r in rules if isinstance(r, dict) and r.get("type") ==
"required_status_checks"]` descartava, em SILENCIO, qualquer regra com `type` ausente, nulo, ou
de tipo errado - a mesma classe C1/A1/A2 fecharam para `ruleset_id`/`parameters`/`enforcement`,
um passo mais cedo, na propria FRONTEIRA de entrada de `rules`. Reproduzido: duas regras, a
segunda sem `type`, cujo ruleset tinha `bypass_actors` NAO VAZIO - `estado: PASS exit=0`, com a
afirmacao universal de bypass_actors=[] sem ter resolvido a segunda regra. A linha seguinte do
filtro original, `tipos = sorted({r.get("type") for r in rules if isinstance(r, dict)})`, e a
MESMA classe de defeito ainda mais visivel: com `type` ausente ao lado de um presente o set vira
`{None, "deletion"}` e `sorted` estoura `TypeError` nao tratado - exit 1 por acidente do
interprete, a classe que V9/V17/MV3/MV9 existem para proibir em qualquer outro campo. Corrigido
com o MESMO mecanismo: um laco sobre `rules` valida `type` via `valida_campo` ANTES de decidir
se um elemento entra em `rsc`, e um elemento ilegivel vira `nao_medidos`, nunca um `PASS`
silencioso nem uma excecao. `chk.get("context")`, dentro do laco que extrai contexto de
`required_status_checks`, tinha a mesma forma - ausencia coagida em "este item nao contribui" -
fail-closed na DIRECAO (o resultado por omissao era FAIL, nunca PASS), mas a mesma violacao
doutrinaria: ausencia nao e medicao, mesmo quando o efeito e conservador. Corrigido com
`valida_campo(chk, "context", str)`, a mesma chamada ja usada para qualquer outro campo.

`strict_required_status_checks_policy` (ausente/nulo/tipo errado) e `enforcement != "active"` /
`current_user_can_bypass != "never"` (valor presente e MEDIDO, nao ausente) ja eram tratados
corretamente pelo codigo antes desta onda - o defeito aqui nao era no CODIGO, era na AUSENCIA de
caso: nenhum caso de `tests/unit/fronteira-viva.sh` isolava `strict` ausente/nulo/tipo-errado
(so a variante `strict:false` EXPLICITA tinha caso), e nenhum isolava um `enforcement`/
`current_user_can_bypass` PRESENTE mas de valor invalido (so a AUSENCIA desses campos tinha
caso). Reintroduzir a coercao de ausencia em `strict_medidos.append(bool(params.get(...)))`, ou
substituir por sempre-falso a comparacao que detecta enforcement e current_user_can_bypass
invalidos, deixava a suite inteira verde - garantia sem teste e o mesmo risco de uma garantia
removida em silencio.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys

PASS, FAIL, NOT_VERIFIED = "PASS", "FAIL", "NOT_VERIFIED"
EXIT = {PASS: 0, FAIL: 1, NOT_VERIFIED: 2}

# Formato de owner/repo do GitHub: nunca comeca com '-' (evitaria que um valor externo fosse
# lido como opcao por `gh`), e so os caracteres que o GitHub aceita em login/nome de repo.
RE_OWNER_REPO = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")
# Nome de branch/ref: aceita barras (ex.: release/v1), nunca comeca com '-' ou '/', nunca '..'.
RE_BRANCH = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._/-]*$")

# Os quatro estados que `valida_campo` distingue - ver o docstring da funcao. `None` (nao um
# destes quatro) significa "conforme": o campo esta presente, nao e nulo, e e do tipo certo.
FALTANTE = "faltante"
NULO = "nulo"
TIPO_INVALIDO = "tipo_invalido"
ITEM_INVALIDO = "item_invalido"


def valida_campo(objeto, nome, tipo, tipo_item=None):
    """Confere UM campo de `objeto` (um dict ja confirmado pelo chamador) contra o schema
    declarado. E o UNICO ponto do arquivo que decide a diferenca entre "campo ausente", "campo
    presente e nulo", "campo de tipo errado" e "elemento de lista de tipo errado" - a mesma
    distincao que tres ondas de correcao reescreveram, cada vez para um campo novo. Nenhum dos
    quatro estados e "medido: valor por omissao"; so o quinto (conforme) e.

    `tipo_item`, quando dado, estende a MESMA distincao ao ELEMENTO de uma lista: o defeito que
    sobra depois que o CONTAINER ja tem guard (`isinstance(valor, list)`) e uma lista valida de
    elementos invalidos - `bypass_actors: ["OrganizationAdmin"]` e uma `list` legitima cujos
    elementos nao sao mapeaveis.

    Devolve (status, valor):
      status None           -> conforme; `valor` e o dado, pronto para uso.
      status FALTANTE       -> `nome` nao esta em `objeto`.
      status NULO           -> `nome` esta em `objeto` com valor `None` explicito (nao e o
                                mesmo que ausente: a API pode devolver a chave com `null`).
      status TIPO_INVALIDO   -> presente, nao-nulo, mas `not isinstance(valor, tipo)`.
      status ITEM_INVALIDO   -> `valor` e uma `list` do tipo certo, mas contem um elemento que
                                nao e instancia de `tipo_item`; `valor` entao e `(indice,
                                elemento)` do PRIMEIRO elemento que nao conforma.
    """
    if nome not in objeto:
        return FALTANTE, None
    valor = objeto[nome]
    if valor is None:
        return NULO, None
    if not isinstance(valor, tipo):
        return TIPO_INVALIDO, valor
    if tipo_item is not None:
        for i, item in enumerate(valor):
            if not isinstance(item, tipo_item):
                return ITEM_INVALIDO, (i, item)
    return None, valor


class Resultado:
    def __init__(self, estado, motivo, detalhes=None):
        self.estado = estado
        self.motivo = motivo
        self.detalhes = detalhes or {}

    @property
    def exit_code(self):
        return EXIT[self.estado]


def gh_api(path):
    """Chama `gh api <path>`. Devolve (dados, erro). `erro` None quando a chamada resolveu.

    Nao ha `shell=True` e o path e um UNICO argumento de lista - sem isso um valor hostil em
    owner/repo/branch poderia ser lido como opcao adicional pelo parser do `gh`.
    """
    try:
        proc = subprocess.run(
            ["gh", "api", path],
            capture_output=True, text=True, timeout=30,
        )
    except FileNotFoundError:
        return None, "'gh' (GitHub CLI) nao esta instalado / nao esta no PATH"
    except subprocess.TimeoutExpired:
        return None, f"gh api {path} excedeu o tempo limite (30s) - rede indisponivel ou lenta"
    if proc.returncode != 0:
        detalhe = (proc.stderr or proc.stdout or "").strip().splitlines()
        detalhe = detalhe[0] if detalhe else f"exit {proc.returncode}"
        return None, f"gh api {path} falhou: {detalhe}"
    try:
        return json.loads(proc.stdout), None
    except json.JSONDecodeError as exc:
        return None, f"gh api {path} devolveu JSON invalido: {exc}"


def resolve_owner_repo(explicit_owner, explicit_repo):
    """owner/repo vem do CLI, ou e derivado de `git config --get remote.origin.url`.

    Sem um dos dois, nao ha alvo para consultar - e isso e lacuna de oraculo, nao aprovacao.
    """
    if explicit_owner and explicit_repo:
        return explicit_owner, explicit_repo, None
    try:
        proc = subprocess.run(
            ["git", "config", "--get", "remote.origin.url"],
            capture_output=True, text=True, timeout=10,
        )
    except (FileNotFoundError, subprocess.TimeoutExpired) as exc:
        return None, None, f"nao foi possivel derivar owner/repo do git remote: {exc}"
    if proc.returncode != 0 or not proc.stdout.strip():
        return None, None, "sem --owner/--repo e sem remote 'origin' para derivar o alvo"
    url = proc.stdout.strip()
    m = re.search(r"github\.com[:/]([^/]+)/([^/]+?)(?:\.git)?$", url)
    if not m:
        return None, None, f"remote.origin.url '{url}' nao e um remoto do github.com reconhecivel"
    return m.group(1), m.group(2), None


def probe(owner, repo, branch, context):
    for nome, valor, rgx in (("owner", owner, RE_OWNER_REPO), ("repo", repo, RE_OWNER_REPO),
                              ("branch", branch, RE_BRANCH)):
        if not valor or not rgx.match(valor) or ".." in valor:
            return Resultado(NOT_VERIFIED,
                              f"'{nome}' invalido ou vazio ('{valor}') - nao ha alvo para consultar")
    if not context:
        return Resultado(NOT_VERIFIED, "contexto exigido nao informado (--context)")

    # --- Applies(P,r): o endpoint AUTORITATIVO. Resposta vazia = nenhuma regra ativa se aplica. ---
    rules, err = gh_api(f"repos/{owner}/{repo}/rules/branches/{branch}")
    if err:
        return Resultado(NOT_VERIFIED, err)
    if not isinstance(rules, list):
        return Resultado(NOT_VERIFIED,
                          f"resposta de rules/branches/{branch} nao e uma lista: {type(rules).__name__}")
    if not rules:
        return Resultado(
            FAIL,
            f"Applies(P,r) = False: nenhuma regra ativa se aplica a ref '{branch}'. "
            f"Resposta vazia do endpoint autoritativo - a mesma forma do defeito medido em "
            f"2026-08-10 (conditions.ref_name.include == []).",
            {"rules": rules},
        )

    # --- Required(P): existe regra required_status_checks aplicavel, e ela exige `context`. ---
    # `nao_medidos` nasce AQUI, ANTES do filtro que separa `rsc` do resto de `rules` - o quinto
    # degrau (wave5, 2026-08-11): um elemento cujo `type` nao pode ser lido (ausente, nulo, tipo
    # errado) OU que nao e sequer um objeto nao pode ser classificado como required_status_checks
    # ou nao. O filtro original, um list comprehension com `isinstance` e `==`, descartava esse
    # elemento em SILENCIO - nunca entrava em `rsc`, seu `ruleset_id` nunca era resolvido, seu
    # ruleset nunca era consultado, e nada entrava em `nao_medidos`: a MESMA classe de defeito que
    # C1/A1/A2 fecharam mais abaixo (onda 4), um passo mais cedo, na FRONTEIRA de entrada do
    # proprio `rules`, antes que exista sequer um `rsc` para iterar. A linha seguinte do filtro
    # original, `sorted({r.get("type") for r in rules if isinstance(r, dict)})`, e a MESMA classe
    # de defeito ainda mais visivel: com `type` ausente ao lado de um presente o set vira
    # `{None, "deletion"}` e `sorted` estoura `TypeError: '<' not supported between instances of
    # 'str' and 'NoneType'` - traceback nao tratado, exit 1 por acidente do interprete. `tipos_
    # legiveis` abaixo so acumula strings JA validadas por `valida_campo`, nunca `None`.
    nao_medidos = []
    rsc = []
    tipos_legiveis = []
    for i, r in enumerate(rules):
        if not isinstance(r, dict):
            nao_medidos.append(
                f"elemento #{i + 1} de rules/branches/{branch}: nao e um objeto "
                f"({type(r).__name__}) - nao e possivel determinar se e uma regra "
                f"required_status_checks aplicavel.")
            continue
        tipo_status, tipo_val = valida_campo(r, "type", str)
        if tipo_status == FALTANTE:
            nao_medidos.append(
                f"elemento #{i + 1} de rules/branches/{branch}: 'type' ausente - nao e possivel "
                f"determinar se e uma regra required_status_checks aplicavel (os demais elementos "
                f"legiveis, se aplicavel, continuam sendo medidos).")
            continue
        elif tipo_status == NULO:
            nao_medidos.append(
                f"elemento #{i + 1} de rules/branches/{branch}: 'type' e null - mesma doutrina de "
                f"campo ausente.")
            continue
        elif tipo_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"elemento #{i + 1} de rules/branches/{branch}: 'type' tem tipo inesperado "
                f"({type(tipo_val).__name__}, esperava string) - nao medido.")
            continue
        tipos_legiveis.append(tipo_val)
        if tipo_val == "required_status_checks":
            rsc.append(r)

    if not rsc:
        if nao_medidos:
            # Sem isto, um elemento de `rules` cujo `type` nao pode ser lido faria este ramo
            # concluir `Required(P) = False` (o mesmo FAIL fabricado que A2 ja fechou para
            # enforcement/strict) sem nunca saber se o elemento ilegivel era, ele mesmo, uma regra
            # required_status_checks com bypass aberto - reproduzido: duas regras, a segunda sem
            # `type`, cujo ruleset tinha bypass_actors NAO VAZIO, saiam `PASS exit=0` antes desta
            # correcao porque a regra ilegivel nunca chegava a `rsc`.
            return Resultado(
                NOT_VERIFIED,
                f"Required(P) para '{context}' nao pode ser determinado: nenhum elemento legivel "
                f"de rules/branches/{branch} e 'required_status_checks' (tipos legiveis: "
                f"{sorted(set(tipos_legiveis)) or '(nenhum)'}), mas ao menos um elemento nao pode "
                f"ser classificado e poderia te-lo sido: " + "; ".join(nao_medidos),
                {"rules": rules},
            )
        return Resultado(
            FAIL,
            f"Applies(P,r) = True (regras aplicaveis: {sorted(set(tipos_legiveis))}), mas nenhuma "
            f"e 'required_status_checks' - Required(P) = False para '{branch}'.",
            {"rules": rules},
        )

    # `problemas` nasce AQUI, antes do laco sobre `rsc` - nao apos ele como nas ondas anteriores.
    # `nao_medidos` ja nasceu ACIMA, antes do filtro que produziu `rsc`, e persiste por todo o
    # resto da funcao. C1 e A1 (ruleset_id/parameters ausentes ou malformados em PARTE das regras
    # aplicaveis) sao lacunas de medicao que acontecem DENTRO deste laco, e precisam do MESMO
    # acumulador que o resto do arquivo usa: uma entrada aqui nunca faz este laco `return` cedo,
    # pela mesma razao ja documentada para o laco de rulesets abaixo - um `return` descartaria uma
    # violacao de `strict` ja medida numa regra ANTERIOR do mesmo laco.
    problemas = []
    contextos = set()
    strict_medidos = []
    ruleset_ids = set()
    for i, r in enumerate(rsc):
        rid_status, rid = valida_campo(r, "ruleset_id", int)
        rotulo = f"ruleset {rid}" if rid_status is None else f"regra aplicavel #{i + 1}"
        if rid_status == FALTANTE:
            # (C1) a regra some do conjunto sem isto - o bypass dela nunca seria resolvido, e
            # antes desta correcao nada entrava em `nao_medidos` para dizer que isso aconteceu.
            nao_medidos.append(
                f"{rotulo}: 'ruleset_id' ausente da regra - not Bypass(a,P) e enforcement NAO "
                f"podem ser resolvidos para esta regra especifica (as demais regras aplicaveis, "
                f"se legiveis, continuam sendo medidas).")
        elif rid_status == NULO:
            nao_medidos.append(f"{rotulo}: 'ruleset_id' e null na regra - mesma doutrina de campo ausente.")
        elif rid_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"{rotulo}: 'ruleset_id' tem tipo inesperado ({type(rid).__name__}, esperava "
                f"inteiro) - oraculo malformado, nao e possivel resolver bypass_actors nem "
                f"enforcement para esta regra.")
        else:
            ruleset_ids.add(rid)

        params_status, params = valida_campo(r, "parameters", dict)
        if params_status == FALTANTE:
            # (A1) sem guard, `r.get("parameters") or {}` deixava passar qualquer coisa truthy
            # (uma string, por exemplo) e o primeiro `.get()` seguinte estourava AttributeError.
            nao_medidos.append(
                f"{rotulo}: 'parameters' ausente da regra - strict_required_status_checks_policy "
                f"e o contexto exigido NAO puderam ser lidos desta regra.")
            continue
        if params_status == NULO:
            nao_medidos.append(f"{rotulo}: 'parameters' e null na regra - mesma doutrina de campo ausente.")
            continue
        if params_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"{rotulo}: 'parameters' tem tipo inesperado ({type(params).__name__}, esperava "
                f"objeto) - oraculo malformado, strict_required_status_checks_policy e o "
                f"contexto exigido NAO puderam ser lidos desta regra.")
            continue

        strict_status, strict_val = valida_campo(params, "strict_required_status_checks_policy", bool)
        if strict_status == FALTANTE:
            # A2 (metade 1): `bool(params.get(...))` coagia a AUSENCIA da chave em `False` - uma
            # violacao FABRICADA, nao medida. Ausencia agora e "nao medido", nunca "medido: false".
            nao_medidos.append(
                f"{rotulo}: 'strict_required_status_checks_policy' ausente de 'parameters' - "
                f"strict NAO foi medido para esta regra.")
        elif strict_status == NULO:
            nao_medidos.append(
                f"{rotulo}: 'strict_required_status_checks_policy' e null - mesma doutrina de campo ausente.")
        elif strict_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"{rotulo}: 'strict_required_status_checks_policy' tem tipo inesperado "
                f"({type(strict_val).__name__}, esperava booleano) - nao medido.")
        else:
            strict_medidos.append(strict_val)

        checks_status, checks = valida_campo(params, "required_status_checks", list, tipo_item=dict)
        if checks_status is None and checks is not None:
            for j, chk in enumerate(checks):
                # (D5, wave5) `chk.get("context")` tratava a AUSENCIA da chave, o valor `null`
                # explicito e um tipo errado como a MESMA coisa - "este item nao contribui
                # contexto algum" - a mesma coercao de ausencia em conclusao que A2 ja fechou para
                # enforcement/strict, agora sobre o elemento de `required_status_checks`. Fail-
                # closed na DIRECAO (nunca produzia PASS por omissao), mas era a mesma violacao
                # doutrinaria: ausencia nao e medicao, mesmo quando o resultado por omissao e um
                # FAIL fabricado em vez de um PASS fabricado.
                ctx_status, ctx_val = valida_campo(chk, "context", str)
                if ctx_status == FALTANTE:
                    nao_medidos.append(
                        f"{rotulo}: 'required_status_checks[{j}]' sem 'context' - esta regra NAO "
                        f"pode ser confirmada nem descartada como fonte do contexto exigido.")
                elif ctx_status == NULO:
                    nao_medidos.append(
                        f"{rotulo}: 'required_status_checks[{j}].context' e null - mesma doutrina "
                        f"de campo ausente.")
                elif ctx_status == TIPO_INVALIDO:
                    nao_medidos.append(
                        f"{rotulo}: 'required_status_checks[{j}].context' tem tipo inesperado "
                        f"({type(ctx_val).__name__}, esperava string) - nao medido.")
                else:
                    contextos.add(ctx_val)
        elif checks_status == ITEM_INVALIDO:
            idx, item = checks
            nao_medidos.append(
                f"{rotulo}: 'required_status_checks[{idx}]' tem tipo inesperado "
                f"({type(item).__name__}, esperava objeto) - o contexto desta regra NAO pode "
                f"ser lido por completo.")
        # FALTANTE/NULO/TIPO_INVALIDO de 'required_status_checks' (a LISTA em si) apenas significa
        # que esta regra nao contribui contexto algum - a mesma consequencia de uma lista vazia,
        # que ja nao era um defeito antes desta correcao. O CAMPO 'context' de cada item da lista
        # passa pela mesma validacao de schema que qualquer outro campo decisivo (ver acima).

    if context not in contextos:
        if nao_medidos:
            # Sem isto, uma regra aplicavel ILEGIVEL (C1/A1 acima) que PODERIA ter exigido
            # `context` faria este ramo declarar `Required(P) = False` por omissao - a mesma
            # coercao de ausencia em conclusao que A2 fecha para bypass/enforcement, agora para
            # Required(P). So quando toda regra aplicavel foi lida por completo e nenhuma exige
            # `context` e que "Required(P) = False" e medido, nao suposto.
            return Resultado(
                NOT_VERIFIED,
                f"Required(P) para '{context}' nao pode ser determinado: o contexto nao foi "
                f"encontrado entre as regras legiveis ({sorted(contextos) or '(nenhum)'}), mas "
                f"ao menos uma regra required_status_checks aplicavel nao pode ser lida por "
                f"completo e poderia te-lo exigido: " + "; ".join(nao_medidos),
                {"rules": rules},
            )
        return Resultado(
            FAIL,
            f"Required(P) = False: o contexto exigido '{context}' NAO esta entre os produzidos "
            f"pelas regras required_status_checks aplicaveis a '{branch}': {sorted(contextos) or '(nenhum)'}.",
            {"rules": rules},
        )

    if not ruleset_ids:
        return Resultado(
            NOT_VERIFIED,
            "nenhuma regra required_status_checks aplicavel declarou 'ruleset_id' valido - "
            "nao e possivel resolver bypass_actors nem enforcement de ruleset algum"
            + ("; " + "; ".join(nao_medidos) if nao_medidos else ""),
            {"rules": rules},
        )

    # strict_required_status_checks_policy ja foi medido acima, no laco sobre `rsc` - nao depende
    # do endpoint de ruleset individual. Entra em `problemas` ANTES do laco seguinte: uma
    # violacao ja provada aqui nao pode ser descartada so porque um ruleset aplicavel, resolvido
    # depois, falha ou nao divulga um campo. A mesma precedencia que o portao final declara
    # (FAIL vence NOT_VERIFIED) so vale se nada dentro do laco abaixo sair cedo demais para
    # nunca alcancar esta linha - e ela ja rodou. `strict_medidos` so contem valores GENUINAMENTE
    # lidos (o `elif` acima ja filtrou ausencia/nulo/tipo errado para `nao_medidos`) - uma lista
    # vazia aqui significa "nenhuma regra aplicavel tinha o campo legivel", nunca "todas
    # desligadas", e por isso NAO produz uma entrada em `problemas` por si so.
    if strict_medidos and not all(strict_medidos):
        problemas.append(
            f"strict_required_status_checks_policy nao esta ligado em toda regra aplicavel "
            f"legivel ({strict_medidos})")

    # --- ¬Bypass(a,P): so o endpoint de RULESET individual traz bypass_actors e
    # current_user_can_bypass. rules/branches/{branch} nao os inclui (medido: ver observacao).
    #
    # NENHUM dos dois campos e garantido na resposta. A documentacao da API ("Get a repository
    # ruleset", https://docs.github.com/en/rest/repos/rules) declara: "To prevent leaking
    # sensitive information, the bypass_actors property is only returned if the user making the
    # API request has write access to the ruleset." Medido nesta sessao contra um repositorio
    # onde o token NAO tem write no ruleset (`gh api repos/github/docs/rulesets/19633356`):
    # 'bypass_actors' ausente da resposta, 'current_user_can_bypass' presente. Um GITHUB_TOKEN de
    # Actions com `contents: read` (o perfil que evidence/claims/C-018.yaml recomenda para
    # execucao AGENDADA) esta nessa mesma situacao. `detalhe.get("bypass_actors") or []`
    # colapsava "medido: nenhum ator pode burlar" com "nao divulgado por falta de permissao" - o
    # mesmo defeito que este probe existe para corrigir, agora sobre o proprio termo
    # not Bypass(a,P). Campo ausente e NOT_VERIFIED, nunca PASS por omissao de sinal.
    #
    # NENHUM ponto deste laco RETORNA cedo. Uma falha de rede/permissao ao ler UM ruleset, ou uma
    # resposta malformada, vira entrada em `nao_medidos` e o laco CONTINUA para os demais - um
    # `return` aqui descartaria `problemas` ja acumulado (o strict acima, ou o bypass de um
    # ruleset anterior no mesmo laco), mascarando uma violacao ja provada atras de uma lacuna de
    # medicao encontrada depois. O portao final, apos o laco, e quem decide a precedencia.
    bypass_total = []
    detalhes_rulesets = {}
    for rid in sorted(ruleset_ids):
        detalhe, err = gh_api(f"repos/{owner}/{repo}/rulesets/{rid}")
        if err:
            nao_medidos.append(
                f"ruleset {rid}: nao foi possivel ler para resolver bypass: {err}")
            continue
        if not isinstance(detalhe, dict):
            # Mesma doutrina do type-guard de `rules` acima: uma resposta que nao e objeto nao
            # pode ser lida com `.get(...)` sem AttributeError, e um oraculo malformado e
            # "nao medido" - nunca a excecao nao tratada que sairia 1 (FAIL) por acidente.
            nao_medidos.append(
                f"ruleset {rid}: resposta de rulesets/{rid} nao e um objeto: "
                f"{type(detalhe).__name__} - oraculo malformado, nao ha como resolver "
                f"bypass_actors nem enforcement")
            continue
        detalhes_rulesets[rid] = detalhe

        enf_status, enforcement = valida_campo(detalhe, "enforcement", str)
        if enf_status == FALTANTE:
            # (A2, metade 2) `detalhe.get("enforcement")` coagia a AUSENCIA em `None`, e
            # `enforcement != "active"` fabricava uma violacao ("enforcement='None'") sobre um
            # campo que nao foi medido. Ausencia agora e "nao medido", nunca "medido: inativo".
            nao_medidos.append(
                f"ruleset {rid}: 'enforcement' ausente da resposta - enforcement NAO foi medido "
                f"para este ruleset.")
        elif enf_status == NULO:
            nao_medidos.append(f"ruleset {rid}: 'enforcement' e null na resposta - mesma doutrina de campo ausente.")
        elif enf_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"ruleset {rid}: 'enforcement' tem tipo inesperado ({type(enforcement).__name__}, "
                f"esperava string) - nao medido.")
        elif enforcement != "active":
            # Defesa em profundidade: rules/branches/{branch} ja deveria filtrar por regra
            # ativa. Se um dia esse filtro mudar de comportamento, este probe nao herda a
            # suposicao em silencio.
            problemas.append(f"ruleset {rid} enforcement='{enforcement}' (esperado 'active')")

        bp_status, bp_valor = valida_campo(detalhe, "bypass_actors", list, tipo_item=dict)
        if bp_status == FALTANTE:
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' ausente da resposta - not Bypass(a,P) NAO foi "
                f"medido. A API so devolve este campo a quem tem acesso de escrita ao ruleset.")
        elif bp_status == NULO:
            # Mesma doutrina da chave ausente, um passo adiante: um valor `null` EXPLICITO
            # tambem nao e "medido: []". `atores = detalhe["bypass_actors"] or []` colapsava os
            # dois casos no mesmo PASS fabricado que a correcao anterior fechou so para a chave
            # ausente - a INSTANCIA foi corrigida, a CLASSE (valor nulo) continuava aberta.
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' e null na resposta - not Bypass(a,P) NAO foi "
                f"medido (mesma doutrina de campo ausente).")
        elif bp_status == TIPO_INVALIDO:
            # Tipo inesperado (ex.: string, numero): sem este guard, `**a` sobre um elemento que
            # nao e mapeamento (ou a propria iteracao sobre uma string) produz TypeError nao
            # tratado - a mesma promessa de "nunca traceback" que ja valia para o OBJETO
            # `detalhe`, agora tambem para este CAMPO dele.
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' tem tipo inesperado "
                f"({type(bp_valor).__name__}, esperava lista) - oraculo "
                f"malformado, not Bypass(a,P) NAO foi medido.")
        elif bp_status == ITEM_INVALIDO:
            # (C2) o guard acima cobria o CONTAINER (`isinstance(..., list)`), nao o ELEMENTO -
            # uma lista de nao-mapeamentos (`["OrganizationAdmin"]`) passava por ele e estourava
            # TypeError em `{"ruleset_id": rid, **a}`. `valida_campo` fecha a mesma classe de
            # defeito no ELEMENTO que ja fechava no container.
            idx, item = bp_valor
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors[{idx}]' tem tipo inesperado "
                f"({type(item).__name__}, esperava objeto) - elemento nao mapeavel, "
                f"not Bypass(a,P) NAO foi medido por completo.")
        else:
            if bp_valor:
                bypass_total.extend({"ruleset_id": rid, **a} for a in bp_valor)

        cucb_status, cucb = valida_campo(detalhe, "current_user_can_bypass", str)
        if cucb_status == FALTANTE:
            nao_medidos.append(
                f"ruleset {rid}: 'current_user_can_bypass' ausente da resposta - not Bypass(a,P) "
                f"NAO foi medido para o ator autenticado (mesma doutrina de 'bypass_actors': "
                f"ausencia nao e 'never').")
        elif cucb_status == NULO:
            nao_medidos.append(
                f"ruleset {rid}: 'current_user_can_bypass' e null na resposta - mesma doutrina de campo ausente.")
        elif cucb_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"ruleset {rid}: 'current_user_can_bypass' tem tipo inesperado "
                f"({type(cucb).__name__}, esperava string) - nao medido.")
        elif cucb != "never":
            problemas.append(
                f"ruleset {rid}: current_user_can_bypass='{cucb}' (esperado 'never')")

    if bypass_total:
        problemas.append(f"bypass_actors nao vazio: {bypass_total}")

    if problemas:
        # FAIL vence sobre "nao medido": uma violacao ja PROVADA (bypass_actors nao vazio,
        # current_user_can_bypass != never, enforcement != active, strict desligado) decide
        # Bypass(a,P) = True de qualquer forma, mesmo que outro ruleset aplicavel nao tenha
        # divulgado o proprio campo. Rebaixar isso a NOT_VERIFIED esconderia um problema real
        # atras de "faltou permissao para medir" - o oposto do fail-closed que este bloco existe
        # para impor.
        return Resultado(
            FAIL,
            "Applies(P,r) e Required(P) valem, mas Bypass(a,P) ou a politica de atualizacao "
            "falham: " + "; ".join(problemas),
            {"rules": rules, "rulesets": detalhes_rulesets},
        )

    if nao_medidos:
        return Resultado(
            NOT_VERIFIED,
            "Applies(P,r) e Required(P) valem e nenhuma violacao foi encontrada nos campos "
            "medidos, mas not Bypass(a,P) NAO foi medido por completo - PASS exigiria medir, "
            "nao supor: " + "; ".join(nao_medidos),
            {"rules": rules, "rulesets": detalhes_rulesets},
        )

    return Resultado(
        PASS,
        f"Gate(P,a,r) satisfeita para '{branch}': contexto '{context}' e exigido por regra "
        f"ativa aplicavel, strict_required_status_checks_policy=true, bypass_actors=[] em "
        f"todos os rulesets de origem ({sorted(ruleset_ids)}).",
        {"rules": rules, "rulesets": detalhes_rulesets},
    )


def main(argv):
    ap = argparse.ArgumentParser(
        description="Mede Applies(P,r) ^ Required(P) ^ not Bypass(a,P) via API do GitHub. "
                    "Fail-closed: sem oraculo, NOT_VERIFIED (exit 2).")
    ap.add_argument("--owner", default=None, help="dono do repositorio (default: derivado do remote origin)")
    ap.add_argument("--repo", default=None, help="nome do repositorio (default: derivado do remote origin)")
    ap.add_argument("--branch", default="main", help="ref alvo (default: main)")
    ap.add_argument("--context", default="verify-pr",
                     help="contexto de required status check exigido (default: verify-pr)")
    ap.add_argument("--json", action="store_true", help="emite o relatorio tambem como JSON em stdout")
    args = ap.parse_args(argv[1:])

    owner, repo, err = resolve_owner_repo(args.owner, args.repo)
    if err:
        print(f"NAO VERIFICADO: {err}", file=sys.stderr)
        return EXIT[NOT_VERIFIED]

    r = probe(owner, repo, args.branch, args.context)

    print(f"alvo: {owner}/{repo}@{args.branch}  contexto exigido: {args.context}")
    print(f"estado: {r.estado}")
    print(f"motivo: {r.motivo}")
    if args.json:
        print(json.dumps({"estado": r.estado, "motivo": r.motivo, "owner": owner, "repo": repo,
                           "branch": args.branch, "context": args.context,
                           "detalhes": r.detalhes}, indent=2, sort_keys=True))
    if r.estado == NOT_VERIFIED:
        print("Estado: NAO VERIFICADO - a lacuna de oraculo (rede/token/API) impede o veredito. "
              "Nao declare PASS nem FAIL por auto-avaliacao.", file=sys.stderr)
    return r.exit_code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
