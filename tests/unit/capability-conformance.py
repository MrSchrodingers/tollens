#!/usr/bin/env python3
"""CONFORMIDADE DE CAPABILITY - o artefato contra a policy, nao a policy contra si mesma.

POR QUE ESTE ARQUIVO EXISTE, e o achado e de auditoria externa, confirmado por medicao.

`orchestration/skill-policy.json` declara cinco estados de lifecycle e SETE condicoes de
promocao: avaliacao pareada, snapshot fixo, verificador deterministico, manifesto de
compatibilidade, controle negativo, medicao de custo e checagem de interferencia de contexto.

`tests/unit/methodology.py` afere que esse JSON CONTEM as clausulas certas. Ele tambem abre
artefatos de skill - resolve invocacoes `/x`, confere comandos publicados - portanto NAO e
verdade que ignore os artefatos. O que ele nao faz, e ninguem fazia, e verificar a proposicao
que de fato importa:

    Promoted(s)  =>  AND_{r in promotion_requires} Evidence(s, r)

Medido em 2026-08-18, antes desta linha existir: oito skills em `execution/skills/promoted/`,
ZERO declarando estado, ZERO com dossie, e `python3 tests/unit/methodology.py` -> TOTAL=53
FAIL=0. O portao provava que a lei estava bem escrita enquanto nada a cumpria. E a forma do
ADR 0030 no nivel da politica: o verificador observa a REPRESENTACAO da garantia, nao o
fenomeno que a garantia pretende controlar.

O QUE MUDOU NA ONDA 13, e o que este arquivo passa a exigir:

  - `state` deixa de ser inferido de nome de diretorio e passa a ser campo declarado em
    `orchestration/registry.json:capabilities`;
  - `state` e `installed` sao INDEPENDENTES, porque colapsa-los tornava a reclassificacao
    epistemologica uma desinstalacao (medido: 49 -> 41 componentes, 0 skills);
  - `promoted` sem dossie valido REPROVA;
  - a divida de avaliacao vira numero com teto.

DIVIDA DE AVALIACAO (D_E), e ela e o mecanismo que faltava para "congelar a expansao":

    D_E = |{ c : state(c) in {candidate, promoted} and not Valid(dossier(c)) }|

Congelar expansao por prosa e norma sem portao - exatamente o defeito que este repositorio
persegue. Com D_E e um teto, admitir capability nova exige antes pagar dossie de outra. O teto
inicial e o valor corrente, o que congela sem exigir quitar a divida inteira de uma vez; cada
dossie fechado o abaixa.

LIMITE DECLARADO: este portao verifica que o dossie EXISTE e declara os campos exigidos. Nao
verifica que o experimento descrito nele tenha sido de fato executado, nem que suas conclusoes
sejam validas. E oraculo de conformidade, nao de veracidade experimental.
"""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("TOLLENS_ROOT", DEFAULT_ROOT)).resolve()

registry = json.loads((ROOT / "orchestration/registry.json").read_text(encoding="utf-8"))
policy = json.loads((ROOT / "orchestration/skill-policy.json").read_text(encoding="utf-8"))

checks: list[tuple[bool, str]] = []


def check(ok: bool, label: str) -> None:
    checks.append((bool(ok), label))
    print(f"  {'PASS' if ok else 'FAIL'}  {label}")


caps = registry.get("capabilities")
check(isinstance(caps, dict) and len(caps) > 0, "registry declara o bloco `capabilities`")
caps = caps or {}

estados_policy = set(policy["lifecycle"]["states"])
requisitos = list(policy["lifecycle"]["promotion_requires"])
CAMPOS = ("kind", "source", "state", "installed", "activation", "evidence")

# TETO DA DIVIDA DE AVALIACAO. Ver cabecalho. Abaixar quando um dossie for fechado; NUNCA
# levantar para acomodar capability nova - levantar o teto e a forma de fingir que a divida
# nao existe, e o numero perde a funcao que justifica sua existencia.
D_MAX = 8

# ---------------------------------------------------------------------------------------
print("== CC1. forma: toda capability declara os campos do schema ==")
sem_campo = [f"{n}:{c}" for n, cap in sorted(caps.items()) for c in CAMPOS if c not in cap]
check(not sem_campo, f"toda capability declara {list(CAMPOS)}"
      + ("" if not sem_campo else f" - faltando: {sem_campo}"))

estado_ruim = [f"{n}={cap.get('state')}" for n, cap in sorted(caps.items())
               if cap.get("state") not in estados_policy]
check(not estado_ruim, f"todo `state` pertence aos estados da policy {sorted(estados_policy)}"
      + ("" if not estado_ruim else f" - invalidos: {estado_ruim}"))

evid_ruim = [n for n, cap in sorted(caps.items())
             if not isinstance(cap.get("evidence"), dict)
             or "status" not in cap["evidence"] or "dossier" not in cap["evidence"]]
check(not evid_ruim, "todo bloco `evidence` declara `status` e `dossier`"
      + ("" if not evid_ruim else f" - malformados: {evid_ruim}"))

# ---------------------------------------------------------------------------------------
print("== CC2. a proposicao que faltava: promoted exige dossie valido ==")


def dossie_valido(cap: dict) -> bool:
    ev = cap.get("evidence") or {}
    if ev.get("status") != "valid":
        return False
    d = ev.get("dossier")
    if not d:
        return False
    caminho = ROOT / d
    if not caminho.is_file():
        return False
    try:
        doc = json.loads(caminho.read_text(encoding="utf-8"))
    except Exception:
        return False
    # O dossie tem de cobrir os SETE requisitos que a propria policy declara. Aceitar um
    # dossie que cubra menos seria reintroduzir a lacuna num nivel abaixo.
    #
    # ONDA 13, achado da revisao: `all(r in doc ...)` sozinho aceitava dois casos vazios.
    # Com `doc` sendo dict e valores None, `r in doc` so testa a CHAVE - dossie com os sete
    # nomes e nenhum conteudo passava. Pior: com `doc` sendo uma STRING JSON contendo os sete
    # nomes, `r in doc` vira containment de substring e passava tambem. Uma string nao declara
    # campo nenhum, e o cabecalho promete verificar que o dossie DECLARA os campos.
    if not isinstance(doc, dict):
        return False
    return all(r in doc and doc[r] not in (None, "", [], {}) for r in requisitos)


promovidas_sem_prova = [n for n, cap in sorted(caps.items())
                        if cap.get("state") == "promoted" and not dossie_valido(cap)]
check(not promovidas_sem_prova,
      "toda capability `promoted` tem dossie que cobre os 7 promotion_requires"
      + ("" if not promovidas_sem_prova else f" - sem prova: {promovidas_sem_prova}"))

# ---------------------------------------------------------------------------------------
print("== CC3. instalacao e independente de lifecycle, mas nao de existencia ==")
# ANCORA, NAO FILTRO. Achado da revisao: `source: "/etc"` passava nas DUAS checagens e a
# lacuna se auto-cancelava. `Path(ROOT) / "/etc"` devolve `/etc` - pathlib deixa o caminho
# absoluto sobrescrever a raiz - entao "fonte existe" dava PASS; e a comparacao disco x registry
# excluia a entrada dos DOIS lados, entao tambem dava PASS. Quem escapava do prefixo saia de
# ambos os oraculos. `install/apply.sh` confina e aborta, mas depender do portao do deploy e
# depender do ultimo elo, como o proprio `install/manifest.sh` registra.
# NOME E COMPONENTE DE CAMINHO. `install/manifest.sh` grava `skills/<nome>` sem validar, e um
# nome com `../` produziu `skills/../../../../tmp/PWNED` no manifesto (medido). `apply.sh:95`
# confina e aborta, entao nao ha escrita arbitraria - mas o proprio `manifest.sh` registra que
# depender do portao do deploy e depender do ultimo elo.
nome_ruim = [n for n in sorted(caps) if not re.fullmatch(r"[a-z0-9][a-z0-9._-]*", n)]
check(not nome_ruim, "todo nome de capability e um componente de caminho seguro"
      + ("" if not nome_ruim else f" - invalidos: {nome_ruim}"))

PREFIXO = "execution/skills/"
fora_do_prefixo = [f"{n} -> {cap.get('source')}" for n, cap in sorted(caps.items())
                   if cap.get("kind") == "skill" and cap.get("installed")
                   and not (cap.get("source") or "").startswith(PREFIXO)]
check(not fora_do_prefixo, f"toda skill instalada declara source sob `{PREFIXO}`"
      + ("" if not fora_do_prefixo else f" - fora: {fora_do_prefixo}"))

fonte_ausente = [f"{n} -> {cap.get('source')}" for n, cap in sorted(caps.items())
                 if cap.get("installed") and not (cap.get("source")
                                                  and (ROOT / cap["source"]).exists())]
check(not fonte_ausente, "toda capability instalada tem fonte existente"
      + ("" if not fonte_ausente else f" - ausentes: {fonte_ausente}"))

retirada_instalada = [n for n, cap in sorted(caps.items())
                      if cap.get("state") in {"deprecated", "rejected"} and cap.get("installed")]
check(not retirada_instalada, "nenhuma capability deprecated/rejected permanece instalada"
      + ("" if not retirada_instalada else f" - instaladas: {retirada_instalada}"))

# O SEGUNDO LADO DO MESMO FURO. `quarantine` significa "nova, nao avaliada", e a policy poe
# `default_activation: off`. Uma capability nao avaliada instalada e carregavel e exatamente o
# risco que a quarentena existe para conter - e era a rota de entrada que escapava do teto.
# Quarentena se exercita por invocacao local explicita, nao por instalacao.
quarentena_instalada = [n for n, cap in sorted(caps.items())
                        if cap.get("state") == "quarantine" and cap.get("installed")]
check(not quarentena_instalada, "nenhuma capability em quarantine esta instalada"
      + ("" if not quarentena_instalada else f" - instaladas: {quarentena_instalada}"))

# O diretorio deixou de carregar semantica, entao ele NAO pode divergir do registry em
# nenhuma direcao: skill em disco nao declarada e capability fantasma; declarada e ausente
# quebra o instalador.
dir_skills = ROOT / "execution/skills"
em_disco = {d.name for d in dir_skills.iterdir() if d.is_dir()} if dir_skills.is_dir() else set()
declaradas_com_fonte = {n for n, cap in caps.items()
                        if (cap.get("source") or "").startswith("execution/skills/")}
check(em_disco == declaradas_com_fonte,
      f"disco e registry coincidem (disco={len(em_disco)} registry={len(declaradas_com_fonte)})"
      + ("" if em_disco == declaradas_com_fonte
         else f" - so em disco: {sorted(em_disco - declaradas_com_fonte)};"
              f" so no registry: {sorted(declaradas_com_fonte - em_disco)}"))

# ---------------------------------------------------------------------------------------
print("== CC4. divida de avaliacao com teto ==")
# `quarantine` ENTRA NA CONTAGEM, e a omissao dela era o furo. A policy declara
# `initial_state: quarantine`: toda capability NASCE nesse estado. Contar so
# {candidate, promoted} deixava a porta de entrada inteira fora do teto - capability nova
# em `quarantine` + `installed: true` passava, medido pelo portao final (rc=0, D_E=8 de 10).
# Ninguem precisava levantar o teto; bastava usar o estado default. A proibicao do cabecalho
# ("nunca levantar D_MAX") foi escrita contra o ataque errado.
_EM_DIVIDA = {"quarantine", "candidate", "promoted"}
d_e = sorted(n for n, cap in caps.items()
             if cap.get("state") in _EM_DIVIDA and not dossie_valido(cap))
check(len(d_e) <= D_MAX,
      f"divida de avaliacao D_E={len(d_e)} nao excede o teto D_MAX={D_MAX}"
      + ("" if len(d_e) <= D_MAX else f" - sem dossie: {d_e}"))
print(f"        D_E={len(d_e)} de {len(caps)} capabilities; teto={D_MAX}")

# ---------------------------------------------------------------------------------------
print("== CC5. o manifesto reflete o registry (o par que faltava) ==")
# ESTE E O PORTAO QUE TERIA MATADO O CRITICO 1 DESTA ONDA. A onda criou uma SEGUNDA fonte de
# verdade - o registry - e nao fechou o par com a primeira. Medido pela revisao: com o registry
# perdendo a chave `capabilities`, `install/manifest.sh` gravava 41 componentes e ZERO skills com
# exit 0 e stderr vazio, `apply.sh` apagava as oito de `~/.claude/skills/`, e `verify.sh`
# respondia "41/41 ok | ESTADO: conforme". Duas fontes de verdade sem invariante que as ligue
# nao sao duas fontes: sao uma fonte e um boato.
_lock = ROOT / "install/manifest.lock"
if not _lock.is_file():
    check(False, "install/manifest.lock existe para ser conferido contra o registry")
else:
    # PAR (origem, destino), nao so destino. Achado do portao final: comparar apenas o nome de
    # destino deixava sobreviver um manifesto com a ORIGEM do layout pre-onda
    # (`execution/skills/promoted/forge` -> `skills/forge`). O artefato estagnado desta migracao
    # especifica passava justamente pelo portao escrito para pega-la.
    _no_manifesto = {(l.split("\t")[2].split("/", 1)[1], l.split("\t")[1])
                     for l in _lock.read_text(encoding="utf-8").splitlines()
                     if l.startswith("skill\t") and len(l.split("\t")) >= 3}
    _instaladas = {(n, cap["source"]) for n, cap in caps.items()
                   if cap.get("installed") and cap.get("kind") == "skill"}
    check(_no_manifesto == _instaladas,
          f"skills do manifesto == skills instaladas no registry "
          f"(manifesto={len(_no_manifesto)} registry={len(_instaladas)})"
          + ("" if _no_manifesto == _instaladas
             else f" - so no manifesto: {sorted(_no_manifesto - _instaladas)};"
                  f" so no registry: {sorted(_instaladas - _no_manifesto)}"))

# ANTIVACUIDADE. Sem capabilities, todos os casos acima passariam vazios - e um portao que
# aprova o conjunto vazio nao distingue "conforme" de "nao ha o que conferir". Este
# repositorio ja pagou essa forma cinco vezes.
check(len(caps) >= 5, f"ha capabilities a conferir (medido: {len(caps)})")
check(len(requisitos) >= 5, f"a policy declara requisitos de promocao (medido: {len(requisitos)})")

failed = sum(not ok for ok, _ in checks)
print(f"\nTOTAL={len(checks)} FAIL={failed}")
raise SystemExit(1 if failed else 0)
