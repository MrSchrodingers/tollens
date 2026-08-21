#!/usr/bin/env python3
"""Renderiza o corpus agente x defeito, e recalcula o bloco `derived`.

POR QUE ESTE ARQUIVO EXISTE. Auditoria externa achou, em duas rodadas seguidas, a mesma forma:

    onda 16   o corpus foi de 26 para 47 achados e a prosa continuou dizendo "40 achados"
    onda 17   o cabecalho declarava "ondas 11 a 15" e ADR 0031..0035 enquanto os dados ja
              tinham onda 17 e ADR 0036

As duas correcoes anteriores foram a mao, e a segunda foi feita DEPOIS de um portao ter sido
construido para a primeira. O portao pegava numeral em prosa por regex e tinha excecao lexical
por janela de contexto - lint sobre algumas realizacoes, nunca a classe. Medido pela auditoria:
"Antes de discutir severidade, sao 40 achados no corpus atual" passava, porque a palavra "Antes"
caia na janela de excecao.

O erro estava no formato, nao no regex:

    contagem estruturada -> humano escreve o numero -> regex tenta descobrir se copiou certo

Este arquivo inverte a direcao:

    contagem estruturada -> renderer -> prosa

Nenhum numeral de contagem e digitado. A prosa do corpus usa marcadores, e este modulo os
resolve a partir dos proprios findings. `tests/unit/governance-links.py` reprova prosa com
digito literal e reprova `derived` divergente dos dados.

LIMITE DECLARADO: numero escrito por EXTENSO ("vinte e sete") continua fora do alcance. A
regra proibe DIGITO em campo de prosa; palavra nao. Nao ha aqui nenhuma pretensao de verificar
semantica de texto - a garantia e de formato, e e essa que se sustenta.

Uso:
    python3 evidence/corpus/render.py            imprime a versao legivel
    python3 evidence/corpus/render.py --update   recalcula `derived` no arquivo
"""
from __future__ import annotations

import json
import os
import re
import sys
from collections import Counter
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("TOLLENS_ROOT", DEFAULT_ROOT)).resolve()
CORPUS = ROOT / "evidence/corpus/agente-x-defeito.json"

CAMPOS_DE_PROSA = ("purpose", "source_of_truth", "inclusion_criterion", "completeness")
LISTAS_DE_PROSA = ("limits", "reading")


def derivar(findings: list[dict]) -> dict:
    """O frame do corpus, computado a partir do corpus. Nunca digitado."""
    return {
        "n_findings": len(findings),
        "wave_min": min(x["wave"] for x in findings),
        "wave_max": max(x["wave"] for x in findings),
        "counts_by_mode": {k: v for k, v in sorted(Counter(x["mode"] for x in findings).items())},
        "sources": sorted({x.get("source_ref", "") for x in findings if x.get("source_ref")}),
        "open_findings": sorted(x["finding_id"] for x in findings
                                if str(x.get("status", "")).startswith("aberto")),
    }


def substituicoes(d: dict) -> dict[str, str]:
    dv = d["derived"]
    fora = {"{{N}}": str(dv["n_findings"]),
            "{{WAVE_MIN}}": str(dv["wave_min"]),
            "{{WAVE_MAX}}": str(dv["wave_max"])}
    for modo, n in dv["counts_by_mode"].items():
        fora[f"{{{{MODE:{modo}}}}}"] = str(n)
    return fora


_MARCADOR = re.compile(r"\{\{[^}]+\}\}")


def resolver(texto: str, mapa: dict[str, str]) -> tuple[str, list[str]]:
    """Texto com marcadores resolvidos, mais a lista dos que NAO resolveram."""
    faltando = [m for m in _MARCADOR.findall(texto) if m not in mapa]
    for k, v in mapa.items():
        texto = texto.replace(k, v)
    return texto, faltando


def prosa(d: dict) -> list[str]:
    """Todos os campos de prosa, na ordem em que aparecem. Usado tambem pelo portao."""
    fora = [d.get(c, "") for c in CAMPOS_DE_PROSA]
    for c in LISTAS_DE_PROSA:
        fora.extend(d.get(c) or [])
    return [s for s in fora if s]


def main() -> int:
    d = json.loads(CORPUS.read_text(encoding="utf-8"))
    novo = derivar(d["findings"])

    if "--update" in sys.argv:
        d["derived"] = {"_comment": d["derived"]["_comment"], **novo}
        CORPUS.write_text(json.dumps(d, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        print(f"derived atualizado: {novo['n_findings']} achados, ondas "
              f"{novo['wave_min']}-{novo['wave_max']}")
        return 0

    mapa = substituicoes(d)
    dv = d["derived"]
    print(f"CORPUS AGENTE x DEFEITO - ondas {dv['wave_min']} a {dv['wave_max']}, "
          f"{dv['n_findings']} achados\n")
    for modo, n in sorted(dv["counts_by_mode"].items(), key=lambda kv: -kv[1]):
        print(f"  {modo:26s} {n:3d}")
    print(f"\n  em aberto: {', '.join(dv['open_findings']) or '(nenhum)'}")
    for estado in d.get("historical_states") or []:
        print(f"  historico: {estado['as_of']} -> {estado['n_findings']} achados"
              f"  ({estado.get('nota','')})")
    print("\nLIMITES\n")
    for s in d.get("limits") or []:
        texto, faltando = resolver(s, mapa)
        if faltando:
            print(f"  MARCADOR NAO RESOLVIDO: {faltando}", file=sys.stderr)
            return 1
        print(f"  - {texto}\n")
    print("LEITURA\n")
    for s in d.get("reading") or []:
        texto, faltando = resolver(s, mapa)
        if faltando:
            print(f"  MARCADOR NAO RESOLVIDO: {faltando}", file=sys.stderr)
            return 1
        print(f"  - {texto}\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
