#!/usr/bin/env python3
"""Escalonador de paralelismo por subagentes.

Ate aqui `orchestration/workflows/*.json` so descrevia `nodes`/`edges`; que subconjunto de
nos podia rodar em paralelo dependia do orquestrador ler o grafo e decidir na hora. Este
modulo formaliza a decisao e a torna verificavel:

  a < b   dependencia de dado: aresta do workflow, b requer a saida de a.
  a X b   conflito de escrita: Writes(a) intersecta Writes(b) (simetrico, independe de ordem).

Um grupo paralelo G (uma "onda" do escalonamento) e legal sse:
  (1) nenhum par em G tem relacao `<` entre si, direta ou transitiva;
  (2) as escritas dos nos de G sao par-a-par disjuntas;
  (3) por checkout COMPARTILHADO, no maximo um no de G toma o lock de suite
      (tests/lib/lock.sh). Nos isolados em worktree proprio (`isolation: worktree`) nao
      competem pelo mesmo arquivo de lock - medido: o fallback de lock usa um caminho
      derivado do checkout, e dois checkouts distintos nao colidem - entao nao contam
      nesse limite.

FONTE DA RELACAO (1): somente `orchestration/workflows/<id>.json` (nodes/edges), o mesmo
arquivo que `orchestration/render.py --check` ja valida estruturalmente. Este modulo NAO
redeclara "requires" node a node: duplicar a precedencia aqui arriscaria divergir do grafo
canonico sem que nada acusasse a divergencia. A ordem e computada por nivelamento de
caminho mais longo (`_ondas`): se x precede y, direta ou transitivamente, o nivel de x e
estritamente menor que o de y - propriedade padrao de nivelamento por caminho mais longo -
entao dois nos no MESMO nivel nunca tem relacao `<` entre si. A condicao (1) fica garantida
pela propria construcao da onda; a suite de mutacao mira essa construcao diretamente
(o incremento de nivel), nao um checador redundante.

METADADOS POR NO vivem em `orchestration/schedule/<id>.json`, um arquivo por workflow, com
o MESMO conjunto de ids que `nodes` no workflow correspondente (verificado abaixo). Cada no:
  actor            : rotulo documental (agente ou "orchestrator"); nao valida contra
                     `orchestration/registry.json` - a legalidade do escalonamento nao
                     depende de quem executa, so de escrita/isolamento/lock.
  isolation        : "shared" (checkout principal da sessao) | "worktree" (checkout proprio).
  holds_suite_lock : true se o no invoca uma suite deste repositorio (toma tests/lib/lock.sh).
  reads[]          : globs documentais do que o no le. NAO participa da legalidade nesta
                     versao - o modelo fornecido define conflito so em cima de escritas.
  writes[]         : globs do que o no escreve. Nos de codigo (`red`/`implement`/`mutation`)
                     tem escopo real definido pela tarefa concreta, resolvido no despacho
                     pelo grafo de dependencias daquela tarefa; aqui isso e declarado como
                     `["**"]` (maximamente conservador) precisamente porque o escopo real so
                     e conhecido em tempo de execucao. Nos sem escopo de escrita ficam com
                     `[]` e por definicao nunca conflitam nem contam no cap de leitura.
  produces[]       : rotulos documentais do artefato que o no emite. Sem uso algoritmico.

Um no com `writes == []` conta como leitor para `read_parallelism_cap` (orchestration/
registry.json); nos com escrita nao contam nesse limite - sao regidos por (2)/(3).
"""
from __future__ import annotations

import argparse
import json
import os
import pathlib
from collections import defaultdict, deque

DEFAULT_ROOT = pathlib.Path(__file__).resolve().parents[1]
ROOT = pathlib.Path(os.environ.get("EVIDENCE_GATE_ROOT", DEFAULT_ROOT)).resolve()

REQUIRED_NODE_KEYS = {"actor", "isolation", "holds_suite_lock", "reads", "writes", "produces"}
VALID_ISOLATION = {"shared", "worktree"}


def fail(msg: str) -> int:
    print(f"SCHEDULE_ERROR {msg}")
    return 1


def _glob_base(pattern: str) -> str:
    """Trecho literal antes do primeiro metacaractere de glob (`*`, `?`, `[`)."""
    for i, ch in enumerate(pattern):
        if ch in "*?[":
            return pattern[:i]
    return pattern


def _writes_conflict(writes_a: list[str], writes_b: list[str]) -> str | None:
    """Par de padroes em conflito, ou None se pares-a-par disjuntos.

    Heuristica CONSERVADORA por prefixo do trecho literal: um padrao cujo trecho literal e
    prefixo do outro (nos dois sentidos) e tratado como conflito, mesmo quando o glob
    completo talvez nao colidisse em todo caso concreto. Isto pode marcar falso positivo em
    padroes-irmaos improvaveis; nunca falso negativo. A assimetria e deliberada: o custo de
    serializar por engano e baixo, o de um conflito de escrita nao detectado (dado
    corrompido ou sobrescrito) e alto.
    """
    for wa in writes_a:
        base_a = _glob_base(wa)
        for wb in writes_b:
            base_b = _glob_base(wb)
            if base_a.startswith(base_b) or base_b.startswith(base_a):
                return f"{wa} x {wb}"
    return None


def _ondas(nodes: list[str], edges: list[list[str]]) -> list[list[str]]:
    """Nivela o DAG por caminho mais longo (Kahn). Levanta ValueError se houver ciclo."""
    succ: dict[str, list[str]] = defaultdict(list)
    indeg = {n: 0 for n in nodes}
    for a, b in edges:
        succ[a].append(b)
        indeg[b] = indeg.get(b, 0) + 1
    level = {n: 0 for n in nodes}
    fila = deque(n for n in nodes if indeg.get(n, 0) == 0)
    processados = 0
    indeg_restante = dict(indeg)
    while fila:
        n = fila.popleft()
        processados += 1
        for m in succ[n]:
            level[m] = max(level[m], level[n] + 1)
            indeg_restante[m] -= 1
            if indeg_restante[m] == 0:
                fila.append(m)
    if processados != len(nodes):
        raise ValueError("ciclo detectado no grafo do workflow - escalonamento indefinido")
    por_nivel: dict[int, list[str]] = defaultdict(list)
    for n in nodes:
        por_nivel[level[n]].append(n)
    return [por_nivel[k] for k in sorted(por_nivel)]


def _valida_metadados(wf_id: str, wf_nodes: list[str], sched: dict) -> list[str]:
    erros = []
    sched_ids = set(sched)
    wf_ids = set(wf_nodes)
    if sched_ids != wf_ids:
        faltando = wf_ids - sched_ids
        orfao = sched_ids - wf_ids
        if faltando:
            erros.append(f"{wf_id}: nos sem metadado de escalonamento: {sorted(faltando)}")
        if orfao:
            erros.append(f"{wf_id}: metadado orfao (no inexistente no workflow): {sorted(orfao)}")
        return erros
    for nid, meta in sched.items():
        if not isinstance(meta, dict):
            erros.append(f"{wf_id}:{nid}: metadado nao e objeto")
            continue
        faltando_campos = REQUIRED_NODE_KEYS - set(meta)
        if faltando_campos:
            erros.append(f"{wf_id}:{nid}: campos ausentes {sorted(faltando_campos)}")
            continue
        if meta["isolation"] not in VALID_ISOLATION:
            erros.append(f"{wf_id}:{nid}: isolation invalido ({meta['isolation']!r})")
        if not isinstance(meta["holds_suite_lock"], bool):
            erros.append(f"{wf_id}:{nid}: holds_suite_lock precisa ser booleano")
        for campo in ("reads", "writes", "produces"):
            valor = meta[campo]
            if not isinstance(valor, list) or not all(isinstance(v, str) for v in valor):
                erros.append(f"{wf_id}:{nid}: {campo} precisa ser lista de strings")
    return erros


def _checa_workflow(wf_id: str, wf: dict, sched: dict, cap: int) -> tuple[list[str], list[list[str]]]:
    wf_nodes = wf.get("nodes", [])
    erros = _valida_metadados(wf_id, wf_nodes, sched)
    if erros:
        return erros, []
    try:
        ondas = _ondas(wf_nodes, wf.get("edges", []))
    except ValueError as exc:
        return [f"{wf_id}: {exc}"], []

    for idx, onda in enumerate(ondas):
        for i in range(len(onda)):
            for j in range(i + 1, len(onda)):
                a, b = onda[i], onda[j]
                writes_a, writes_b = sched[a]["writes"], sched[b]["writes"]
                if writes_a and writes_b:
                    conflito = _writes_conflict(writes_a, writes_b)
                    if conflito:
                        erros.append(
                            f"{wf_id}: onda {idx} {onda} - conflito de escrita entre "
                            f"'{a}' e '{b}': {conflito}"
                        )
        lockers_compartilhados = [
            n for n in onda if sched[n]["holds_suite_lock"] and sched[n]["isolation"] == "shared"
        ]
        if len(lockers_compartilhados) > 1:
            erros.append(
                f"{wf_id}: onda {idx} {onda} - mais de um no compartilhado disputa o lock "
                f"de suite: {lockers_compartilhados}"
            )
        leitores = [n for n in onda if not sched[n]["writes"]]
        if len(leitores) > cap:
            erros.append(
                f"{wf_id}: onda {idx} {onda} - {len(leitores)} leitores excedem "
                f"read_parallelism_cap={cap}: {leitores}"
            )
    return erros, ondas


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    parser.parse_args()

    reg_path = ROOT / "orchestration/registry.json"
    if not reg_path.is_file():
        return fail("orchestration/registry.json ausente")
    reg = json.loads(reg_path.read_text())
    cap = reg.get("invariants", {}).get("read_parallelism_cap")
    if not isinstance(cap, int):
        return fail("registry.json: invariants.read_parallelism_cap ausente ou nao inteiro")

    wf_dir = ROOT / "orchestration/workflows"
    sched_dir = ROOT / "orchestration/schedule"
    if not wf_dir.is_dir():
        return fail("orchestration/workflows ausente")
    if not sched_dir.is_dir():
        return fail("orchestration/schedule ausente")

    wf_ids = {p.stem for p in wf_dir.glob("*.json")}
    sched_ids = {p.stem for p in sched_dir.glob("*.json")}
    if wf_ids != sched_ids:
        faltando = wf_ids - sched_ids
        orfao = sched_ids - wf_ids
        detalhe = []
        if faltando:
            detalhe.append(f"sem escalonamento: {sorted(faltando)}")
        if orfao:
            detalhe.append(f"escalonamento orfao: {sorted(orfao)}")
        return fail("inventario de workflows diverge do de escalonamento (" + "; ".join(detalhe) + ")")

    todos_erros: list[str] = []
    total_ondas = 0
    saida_ondas: list[str] = []
    for wf_path in sorted(wf_dir.glob("*.json")):
        wf_id = wf_path.stem
        wf = json.loads(wf_path.read_text())
        sched = json.loads((sched_dir / f"{wf_id}.json").read_text())
        erros, ondas = _checa_workflow(wf_id, wf, sched, cap)
        todos_erros.extend(erros)
        if not erros:
            total_ondas += len(ondas)
            saida_ondas.append(f"ONDAS {wf_id} {json.dumps(ondas)}")

    if todos_erros:
        for erro in todos_erros:
            print(f"SCHEDULE_ERROR {erro}")
        return 1

    for linha in saida_ondas:
        print(linha)
    print(f"escalonamento verificado: {len(wf_ids)} workflows, {total_ondas} ondas, read_parallelism_cap={cap}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
