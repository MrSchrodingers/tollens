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
    rsc = [r for r in rules if isinstance(r, dict) and r.get("type") == "required_status_checks"]
    if not rsc:
        tipos = sorted({r.get("type") for r in rules if isinstance(r, dict)})
        return Resultado(
            FAIL,
            f"Applies(P,r) = True (regras aplicaveis: {tipos}), mas nenhuma e "
            f"'required_status_checks' - Required(P) = False para '{branch}'.",
            {"rules": rules},
        )

    contextos = set()
    strict_flags = []
    ruleset_ids = set()
    for r in rsc:
        params = r.get("parameters") or {}
        strict_flags.append(bool(params.get("strict_required_status_checks_policy")))
        for chk in params.get("required_status_checks") or []:
            if isinstance(chk, dict) and chk.get("context"):
                contextos.add(str(chk["context"]))
        rid = r.get("ruleset_id")
        if rid is not None:
            ruleset_ids.add(rid)

    if context not in contextos:
        return Resultado(
            FAIL,
            f"Required(P) = False: o contexto exigido '{context}' NAO esta entre os produzidos "
            f"pelas regras required_status_checks aplicaveis a '{branch}': {sorted(contextos) or '(nenhum)'}.",
            {"rules": rules},
        )

    if not ruleset_ids:
        return Resultado(
            NOT_VERIFIED,
            "a regra required_status_checks aplicavel nao declarou 'ruleset_id' - "
            "nao e possivel resolver bypass_actors nem enforcement do ruleset de origem",
            {"rules": rules},
        )

    problemas = []
    nao_medidos = []

    # strict_required_status_checks_policy ja foi medido acima, no laco sobre `rsc` - nao depende
    # do endpoint de ruleset individual. Entra em `problemas` ANTES do laco seguinte: uma
    # violacao ja provada aqui nao pode ser descartada so porque um ruleset aplicavel, resolvido
    # depois, falha ou nao divulga um campo. A mesma precedencia que o portao final declara
    # (FAIL vence NOT_VERIFIED) so vale se nada dentro do laco abaixo sair cedo demais para
    # nunca alcancar esta linha - e ela ja rodou.
    strict_ok = bool(strict_flags) and all(strict_flags)
    if not strict_ok:
        problemas.append(
            f"strict_required_status_checks_policy nao esta ligado em toda regra aplicavel "
            f"({strict_flags})")

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
        enforcement = detalhe.get("enforcement")
        if enforcement != "active":
            # Defesa em profundidade: rules/branches/{branch} ja deveria filtrar por regra
            # ativa. Se um dia esse filtro mudar de comportamento, este probe nao herda a
            # suposicao em silencio.
            problemas.append(f"ruleset {rid} enforcement='{enforcement}' (esperado 'active')")

        if "bypass_actors" not in detalhe:
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' ausente da resposta - not Bypass(a,P) NAO foi "
                f"medido. A API so devolve este campo a quem tem acesso de escrita ao ruleset.")
        elif detalhe["bypass_actors"] is None:
            # Mesma doutrina da chave ausente, um passo adiante: um valor `null` EXPLICITO
            # tambem nao e "medido: []". `atores = detalhe["bypass_actors"] or []` colapsava os
            # dois casos no mesmo PASS fabricado que a correcao anterior fechou so para a chave
            # ausente - a INSTANCIA foi corrigida, a CLASSE (valor nulo) continuava aberta.
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' e null na resposta - not Bypass(a,P) NAO foi "
                f"medido (mesma doutrina de campo ausente).")
        elif not isinstance(detalhe["bypass_actors"], list):
            # Tipo inesperado (ex.: string, numero): sem este guard, `**a` sobre um elemento que
            # nao e mapeamento (ou a propria iteracao sobre uma string) produz TypeError nao
            # tratado - a mesma promessa de "nunca traceback" que ja valia para o OBJETO
            # `detalhe`, agora tambem para este CAMPO dele.
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' tem tipo inesperado "
                f"({type(detalhe['bypass_actors']).__name__}, esperava lista) - oraculo "
                f"malformado, not Bypass(a,P) NAO foi medido.")
        else:
            atores = detalhe["bypass_actors"]
            if atores:
                bypass_total.extend({"ruleset_id": rid, **a} for a in atores)

        if "current_user_can_bypass" not in detalhe:
            nao_medidos.append(
                f"ruleset {rid}: 'current_user_can_bypass' ausente da resposta - not Bypass(a,P) "
                f"NAO foi medido para o ator autenticado (mesma doutrina de 'bypass_actors': "
                f"ausencia nao e 'never').")
        else:
            cucb = detalhe["current_user_can_bypass"]
            if cucb != "never":
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
