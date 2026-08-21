#!/usr/bin/env python3
from __future__ import annotations

import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
registry = json.loads((ROOT / "orchestration/registry.json").read_text(encoding="utf-8"))

expected = {
    "policy": "orchestration/skill-policy.json",
    "evaluation_protocol": "orchestration/evaluation-protocol.json",
    "method": "docs/method/skill-evaluation-protocol.md",
    "adr": "docs/adr/0025-skills-evidence-gated.md",
}
actual = registry.get("skill_governance")

if actual != expected:
    raise SystemExit(f"FAIL skill_governance divergente: {actual!r}")

for label, raw_path in expected.items():
    path = ROOT / raw_path
    if not path.is_file():
        raise SystemExit(f"FAIL {label} nao resolve: {raw_path}")

print("PASS registry liga policy, protocolo, metodo e ADR")

# ONDA 15 - O CORPUS NAO PODE DECLARAR UMA CONTAGEM QUE ELE MESMO CONTRADIZ.
#
# `evidence/corpus/agente-x-defeito.json` publica `counts_by_mode`, e a primeira versao dessa
# tabela foi escrita a mao e SAIU ERRADA (remedicao: declarado 8, medido 9). Numero declarado que
# ninguem confere e a forma mais barata do defeito que este repositorio persegue - e ele apareceu
# dentro do proprio corpus que documenta esse defeito. Recontar aqui custa quatro linhas.
corpus_path = ROOT / "evidence/corpus/agente-x-defeito.json"
if not corpus_path.is_file():
    raise SystemExit("FAIL corpus agente-x-defeito ausente")
corpus = json.loads(corpus_path.read_text(encoding="utf-8"))

# ONDA 18: `counts_by_mode` saiu do topo do arquivo e virou parte do bloco DERIVADO, junto do
# resto do frame. A recontagem continua, agora contra `derived` - ver a checagem completa abaixo,
# que compara o bloco inteiro com o que o renderer calcula.
medido: dict[str, int] = {}
for achado in corpus["findings"]:
    medido[achado["mode"]] = medido.get(achado["mode"], 0) + 1
declarado = (corpus.get("derived") or {}).get("counts_by_mode")
if medido != declarado:
    raise SystemExit(f"FAIL corpus: derived.counts_by_mode {declarado} != medido {medido}")

# Todo modo citado numa linha tem de estar definido em `modes`, senao a coluna nao significa nada.
desconhecidos = sorted(set(medido) - set(corpus["modes"]))
if desconhecidos:
    raise SystemExit(f"FAIL corpus: modos usados e nao definidos: {desconhecidos}")

# ANTIVACUIDADE: um corpus vazio satisfaria as duas checagens acima sem dizer nada.
if len(corpus["findings"]) < 10:
    raise SystemExit(f"FAIL corpus com {len(corpus['findings'])} achados - vazio demais para medir")

# COMPLETUDE, NAO SO CONSISTENCIA. Achado de auditoria externa, e ele e a tese deste
# repositorio aplicada ao proprio instrumento que a documenta: a recontagem acima confere que
# `counts_by_mode` bate com as linhas PRESENTES, e nunca conferiu se as linhas presentes sao
# TODOS os achados da fonte declarada. Estavam faltando dezesseis - os cinco criticos e oito
# avisos do `revisor-codigo`, e os tres do `refutador`, todos da onda 15. Sobre esse universo
# incompleto, um relatorio publicado concluiu que a auditoria externa fora o modo mais
# produtivo; com o universo completo a ordem se inverte.
#
#     corpus internamente consistente  NAO IMPLICA  corpus completo
#
# A regra: todo identificador citado com MARCADOR ESTRUTURADO num ADR (`**C1 -`, `**F2 -`,
# `**A4 -`) tem de existir como `finding_id` aqui. Marcador estruturado, e nao qualquer mencao,
# porque prosa cita identificador de passagem e transformar isso em obrigacao produziria ruido.
ids_corpus = {f.get("finding_id") for f in corpus["findings"]}
faltando: dict[str, list[str]] = {}
for adr in sorted((ROOT / "docs/adr").glob("*.md")):
    citados = set(re.findall(r"\*\*([A-Z]\d{1,2})\*{0,2} [-\u2014]", adr.read_text(encoding="utf-8")))
    ausentes = sorted(citados - ids_corpus)
    if ausentes:
        faltando[adr.name] = ausentes
if faltando:
    raise SystemExit(f"FAIL corpus INCOMPLETO: achados citados em ADR e ausentes do corpus: {faltando}")

# ANTIVACUIDADE: se nenhum ADR citasse identificador algum, a checagem acima passaria vazia e
# nao distinguiria "completo" de "nada a conferir".
_citados_total = set()
for adr in sorted((ROOT / "docs/adr").glob("*.md")):
    _citados_total |= set(re.findall(r"\*\*([A-Z]\d{1,2})\*{0,2} [-\u2014]", adr.read_text(encoding="utf-8")))
if len(_citados_total) < 5:
    raise SystemExit(f"FAIL completude vacua: so {len(_citados_total)} identificadores citados em ADR")

if "inclusion_criterion" not in corpus:
    raise SystemExit("FAIL corpus sem criterio de inclusao explicito - sem ele, 'produtividade "
                     "do revisor' fica vulneravel a selecao retrospectiva")

print(f"PASS corpus agente-x-defeito coerente ({len(corpus['findings'])} achados, {len(medido)} modos)")
print(f"PASS completude ADR-ID: os {len(_citados_total)} achados citados com marcador\n     estruturado em ADR estao no corpus. NAO e completude absoluta do universo de\n     defeitos - defeito descrito em ADR SEM identificador fica fora deste frame.")

# ONDA 15, SEGUNDA RODADA - O NUMERO PUBLICADO NO ADR E RECONFERIDO CONTRA O PORTAO.
#
# Achado C4 de revisao independente: o ADR 0035 e a errata da observacao publicavam
# `D_E = 87 sobre 33 capabilities` enquanto o portao do MESMO commit media 89 sobre 34. A prosa
# fora escrita antes de a ultima capability entrar, e nada reconferia - a mesma classe do
# `counts_by_mode` do corpus, corrigida logo acima, reaparecendo no arquivo que JUSTIFICA a onda.
# Numero que justifica uma decisao e o ultimo lugar onde se pode confiar em copia manual.

ADR = ROOT / "docs/adr/0035-a-divida-era-de-uma-classe-so.md"
if not ADR.is_file():
    raise SystemExit("FAIL ADR 0035 ausente")

_saida = subprocess.run([sys.executable, str(ROOT / "tests/unit/capability-conformance.py")],
                        capture_output=True, text=True, cwd=str(ROOT))
_medido = re.search(r"D_E\(head\)=(\d+) obrigacoes em aberto sobre (\d+) capabilities",
                    _saida.stdout)
if _medido is None:
    # O portao sai 2 = NAO VERIFICADO quando nao ha ref de base. Sem medida nao se pode conferir
    # a publicacao, e inventar um veredito aqui seria pior que declarar a lacuna.
    print("NAO VERIFICADO: o portao nao produziu D_E (sem ref de base?) - numero do ADR nao conferido")
else:
    _pub = re.search(r"D_E\(head\) = (\d+) obrigacoes em aberto sobre (\d+) capabilities",
                     ADR.read_text(encoding="utf-8"))
    if _pub is None:
        raise SystemExit("FAIL ADR 0035 nao publica o D_E medido - o numero que justifica a onda sumiu")
    if _pub.groups() != _medido.groups():
        raise SystemExit(f"FAIL ADR 0035 publica D_E={_pub.group(1)}/{_pub.group(2)} "
                         f"e o portao mede {_medido.group(1)}/{_medido.group(2)}")
    # ONDA 18 - A PROSA DO CORPUS NAO PODE CONTER NUMERAL, e o frame e DERIVADO.
#
# A onda 17 pos um lint de numeral com excecao por janela lexical. Auditoria externa mostrou que
# nao fechava a classe: "Antes de discutir severidade, sao 40 achados no corpus atual" passava,
# porque "Antes" caia na janela de excecao; e o mesmo cabecalho declarava "ondas 11 a 15" com
# onda 17 nos dados. O erro estava no FORMATO, nao no regex:
#
#     contagem estruturada -> humano escreve o numero -> regex tenta descobrir se copiou certo
#
# Invertido: a prosa usa marcadores, `evidence/corpus/render.py` os resolve a partir dos
# findings, e digito literal em campo de prosa passa a ser recusado. Nao ha o que copiar errado.
#
# LIMITE: numero por EXTENSO nao e alcancado. A garantia e de FORMATO - nenhum digito -, nao de
# semantica de texto. Dizer o contrario seria a amplitude que esta serie vem corrigindo.
sys.path.insert(0, str(ROOT / "evidence/corpus"))
import render as _render                                                    # noqa: E402

_derivado = _render.derivar(corpus["findings"])
_divergente = {k: (corpus["derived"].get(k), v) for k, v in _derivado.items()
               if corpus["derived"].get(k) != v}
if _divergente:
    raise SystemExit(f"FAIL corpus: bloco `derived` diverge dos findings: {_divergente} "
                     "- rode `python3 evidence/corpus/render.py --update`")

# ESCOPO DESTE LINT, dito com precisao porque a versao anterior errou justamente aqui. Ele
# recusa DUAS formas de contagem escritas a mao - `<N> achados` e `N=<N>` -, que sao as que de
# fato reincidiram. Nao pretende cobrir prosa derivada em geral: numero por extenso, aritmetica
# em texto e referencia narrativa a uma onda passada ficam fora, e a garantia contra elas nao
# vem daqui - vem de o FRAME ser derivado em `derived`, onde nao ha o que copiar errado.
#
# A EXCECAO LEXICAL FOI REMOVIDA. A versao da onda 17 absolvia o numeral se a janela de noventa
# caracteres anterior contivesse "antes", "anterior", "primeira versao" ou "ja esteve. Auditoria
# externa mediu: "Antes de discutir severidade, sao 40 achados no corpus atual" passava, com o
# numero corrente FALSO. Excecao por vizinhanca de palavra e adivinhacao de intencao. O historico
# nao precisa dela: vive em `historical_states`, estruturado, e o renderer o imprime.
_sem_marcador = [re.sub(r"\{\{[^}]+\}\}", "", s) for s in _render.prosa(corpus)]
_com_contagem = [s[:70] for s in _sem_marcador if re.search(r"\b\d+ achados\b|\bN=\d+\b", s)]
if _com_contagem:
    raise SystemExit("FAIL corpus: contagem escrita a mao na prosa; use marcador resolvido por "
                     f"evidence/corpus/render.py, e historico em historical_states: {_com_contagem}")
if not (corpus.get("historical_states") or []):
    raise SystemExit("FAIL corpus sem `historical_states` - sem ele o registro do proprio erro "
                     "so caberia na prosa, que e o que esta regra acabou de proibir")

_mapa = _render.substituicoes(corpus)
_orfaos = [m for s in _render.prosa(corpus) for m in _render._MARCADOR.findall(s) if m not in _mapa]
if _orfaos:
    raise SystemExit(f"FAIL corpus: marcador que nao resolve: {sorted(set(_orfaos))}")

# ONDA 18 - AFIRMACAO DE AUSENCIA NA LITERATURA EXIGE BUSCA DELIMITADA.
#
# A onda 17 proibiu a forma lexical e abriu duas excecoes: a palavra ERRATA numa janela de oito
# linhas, e o token `[citacao-corrigida]` na propria linha. Auditoria externa mediu as duas
# falhas. Quatro reformulacoes triviais passavam intocadas ("Nao ha estudo publicado que meca",
# "A literatura ainda nao mede", "Inexiste trabalho que", "There are no published studies"), e o
# token de escape podia ser escrito pelo MESMO PR que escrevia a claim - criterio de excecao
# dentro do objeto governado, a familia do D_MAX numa representacao nova.
#
# Duas mudancas. A primeira: a lista de realizacoes cresce, e a claim sobre ela ENCOLHE - isto e
# um LINT de realizacoes lexicais, nunca um detector semantico de negativa universal.
#
# A segunda e a que fecha a classe para claim NOVA: a unica forma autorizada de afirmar ausencia
# e referenciar uma busca delimitada, `[busca:<id>]`, resolvendo para um registro em
# `evidence/literature/searches/`. `PARA TODO p, nao P(p)` nao e demonstravel por busca finita;
# `NaoEncontrado(consultas, fontes, data)` e.
#
# E a valvula de CITACAO nao e mais autodeclarada: uma linha com a forma so e absolvida se
# EXISTIR IDENTICA NA ARVORE BASE - fato que o PR nao pode forjar, o mesmo principio da onda 14.
_NEG = re.compile(
    r"(nenhum[a]? (?:trabalho|paper|estudo|artigo|pesquisa)"
    r"|ninguem (?:mede|mediu|avalia)"
    r"|inexiste (?:trabalho|estudo)"
    r"|nao (?:ha|existe) (?:trabalho|estudo|paper|pesquisa)"
    r"|a literatura (?:ainda )?nao mede"
    r"|no (?:work|paper|study|research) (?:measures|evaluates)"
    r"|there (?:are|is) no published)", re.IGNORECASE)
_BUSCA = re.compile(r"\[busca:([A-Z]{2}-\d{4})\]")

_base_ref = None
for _r in ("origin/main", "main"):
    if subprocess.run(["git", "-C", str(ROOT), "rev-parse", "--verify", _r],
                      capture_output=True).returncode == 0:
        _base_ref = _r
        break

_sem_busca, _busca_morta = [], []
for _adr in sorted((ROOT / "docs/adr").glob("*.md")):
    _linhas = _adr.read_text(encoding="utf-8").splitlines()
    _base_txt = ""
    if _base_ref:
        _r = subprocess.run(["git", "-C", str(ROOT), "show", f"{_base_ref}:docs/adr/{_adr.name}"],
                            capture_output=True, text=True)
        _base_txt = _r.stdout if _r.returncode == 0 else ""
    for _i, _linha in enumerate(_linhas, 1):
        if not _NEG.search(_linha):
            continue
        if _linha in _base_txt:          # citacao de texto que ja existia na BASE
            continue
        _ids = _BUSCA.findall(_linha)
        if not _ids:
            _sem_busca.append(f"{_adr.name}:{_i}")
            continue
        for _id in _ids:
            if not list((ROOT / "evidence/literature/searches").glob(f"{_id}-*.yaml")):
                _busca_morta.append(f"{_adr.name}:{_i} -> {_id}")
if _sem_busca:
    raise SystemExit("FAIL afirmacao de ausencia na literatura sem busca delimitada "
                     f"[busca:<id>], e sem existir identica na base: {_sem_busca}")
if _busca_morta:
    raise SystemExit(f"FAIL referencia [busca:<id>] que nao resolve: {_busca_morta}")

_buscas = sorted((ROOT / "evidence/literature/searches").glob("*.yaml"))
if not _buscas:
    raise SystemExit("FAIL nenhuma busca delimitada registrada - a regra acima seria vacua")

print(f"PASS corpus: frame derivado dos dados, prosa sem numeral literal "
      f"({_derivado['n_findings']} achados, ondas {_derivado['wave_min']}-{_derivado['wave_max']})")
print(f"PASS ausencia na literatura so por busca delimitada ({len(_buscas)} registrada(s))")
print(f"PASS ADR 0035 publica o D_E que o portao mede ({_medido.group(1)} sobre {_medido.group(2)})")
