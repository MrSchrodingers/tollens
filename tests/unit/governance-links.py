#!/usr/bin/env python3
from __future__ import annotations

import json
import re
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

medido: dict[str, int] = {}
for achado in corpus["findings"]:
    medido[achado["mode"]] = medido.get(achado["mode"], 0) + 1
declarado = corpus["counts_by_mode"]
if medido != declarado:
    raise SystemExit(f"FAIL corpus: counts_by_mode declarado {declarado} != medido {medido}")

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
# TODOS os achados da fonte declarada. Estavam faltando catorze - os cinco criticos e seis
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
print(f"PASS corpus COMPLETO: os {len(_citados_total)} achados citados em ADR estao todos presentes")

# ONDA 15, SEGUNDA RODADA - O NUMERO PUBLICADO NO ADR E RECONFERIDO CONTRA O PORTAO.
#
# Achado C4 de revisao independente: o ADR 0035 e a errata da observacao publicavam
# `D_E = 87 sobre 33 capabilities` enquanto o portao do MESMO commit media 89 sobre 34. A prosa
# fora escrita antes de a ultima capability entrar, e nada reconferia - a mesma classe do
# `counts_by_mode` do corpus, corrigida logo acima, reaparecendo no arquivo que JUSTIFICA a onda.
# Numero que justifica uma decisao e o ultimo lugar onde se pode confiar em copia manual.
import subprocess
import sys

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
    print(f"PASS ADR 0035 publica o D_E que o portao mede ({_medido.group(1)} sobre {_medido.group(2)})")
