#!/usr/bin/env python3
from __future__ import annotations

import json
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

print(f"PASS corpus agente-x-defeito coerente ({len(corpus['findings'])} achados, {len(medido)} modos)")

# ONDA 15, SEGUNDA RODADA - O NUMERO PUBLICADO NO ADR E RECONFERIDO CONTRA O PORTAO.
#
# Achado C4 de revisao independente: o ADR 0035 e a errata da observacao publicavam
# `D_E = 87 sobre 33 capabilities` enquanto o portao do MESMO commit media 89 sobre 34. A prosa
# fora escrita antes de a ultima capability entrar, e nada reconferia - a mesma classe do
# `counts_by_mode` do corpus, corrigida logo acima, reaparecendo no arquivo que JUSTIFICA a onda.
# Numero que justifica uma decisao e o ultimo lugar onde se pode confiar em copia manual.
import re
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
