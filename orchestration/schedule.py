#!/usr/bin/env python3
"""Validador de configuracao de escalonamento por subagentes.

Ate aqui `orchestration/workflows/*.json` so descrevia `nodes`/`edges`; que subconjunto de
nos podia rodar em paralelo dependia do orquestrador ler o grafo e decidir na hora. Este
modulo formaliza a decisao e a torna verificavel:

  a < b   dependencia de dado: aresta do workflow, b requer a saida de a.
  a X b   conflito de escrita: Writes(a) intersecta Writes(b) (simetrico, independe de ordem).

Um par de nos (a, b) e legal sse:
  (1) nao ha relacao `<` entre eles, direta ou transitiva;
  (2) Writes(a) e Writes(b) sao disjuntas;
  (3) por checkout COMPARTILHADO, no maximo um dos dois toma o lock de suite
      (tests/lib/lock.sh). Nos isolados em worktree proprio (`isolation: worktree`) nao
      competem pelo mesmo arquivo de lock - medido: o fallback de lock usa um caminho
      derivado do checkout, e dois checkouts distintos nao colidem - entao nao contam
      nesse limite.

PODER DISCRIMINANTE SOBRE OS 3 WORKFLOWS DE PRODUCAO (medido, nao suposto): ha 9 pares de
nos concorrentes (sem relacao `<`) nos 3 workflows reais deste repositorio (`standard-change`,
`high-risk-change`, `investigation-only`), e em ZERO deles a checagem de conflito de
escrita (2) chega a ser avaliada, porque todo no de codigo (`red`/`implement`/`mutation`/
`test`) declara `writes: ["**"]` e todo no read-only declara `[]` - a condicao `writes_a and
writes_b` (ambas nao-vazias) nunca fica verdadeira entre dois nos concorrentes reais. Por
isso este modulo NAO e descrito como "garantia mecanica de paralelismo": esse titulo
implicaria auditoria do paralelismo em uso, e o poder demonstrado ate aqui vem inteiramente
de fixtures SINTETICAS (tests/unit/schedule.sh), nunca do dado real. O que ele entrega,
medido, e um validador de CONFIGURACAO de escalonamento: barra `schedule/<id>.json`
malformado ou logicamente inconsistente hoje, e continua util no dia em que um no de
codigo parar de declarar `writes: ["**"]` e passar a escopo real - so nao se pode alegar
que audita o paralelismo hoje em producao, porque hoje ele nunca chega a comparar duas
escritas reais.

FONTE DA RELACAO (1): somente `orchestration/workflows/<id>.json` (nodes/edges), o mesmo
arquivo que `orchestration/render.py --check` ja valida estruturalmente. Este modulo NAO
redeclara "requires" node a node: duplicar a precedencia aqui arriscaria divergir do grafo
canonico sem que nada acusasse a divergencia. A relacao `<` e decidida por alcancabilidade
no DAG (`_fecho_transitivo`: para cada no, o conjunto de descendentes por aresta direta ou
transitiva) - dois nos SEM relacao `<` entre si, em QUALQUER lugar do grafo, sao checados
por (2)/(3), independente de em que nivel de `_ondas` cada um caiu. Isto NAO e o mesmo que
"par no mesmo nivel de `_ondas`": o nivelamento por caminho mais longo agrupa por
DISTANCIA ate a raiz, e dois nos sem aresta entre si podem cair em niveis diferentes sem
ter precedencia real entre eles (ex.: nodes [a,b,x], edges [[a,b]] - `x` fica no nivel 0
junto com `a`, `b` fica no nivel 1, mas `x` e `b` continuam sem relacao `<`). O despacho
real deste repositorio e por PRONTIDAO, nao onda-a-onda sincronizada (CLAUDE.md; ADR 0007 -
"FAN-OUT paralelo dos revisores read-only, sem dependencia entre si, lancados na mesma
mensagem"): dois nos assim podem rodar ao mesmo tempo na pratica, entao checa-los so
quando caem na mesma onda deixaria um par concorrente sem checagem - medido: inerte nos 3
workflows reais (0 pares nessa condicao hoje), gap provado so por fixture sintetica.
`_ondas`/nivelamento continua em uso para emitir a saida `ONDAS <id> [...]` (o que o
orquestrador de fato despacha junto) e para o `read_parallelism_cap`, que permanece
particionado por nivel.

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
import posixpath
from collections import defaultdict, deque

DEFAULT_ROOT = pathlib.Path(__file__).resolve().parents[1]
ROOT = pathlib.Path(os.environ.get("EVIDENCE_GATE_ROOT", DEFAULT_ROOT)).resolve()

REQUIRED_NODE_KEYS = {"actor", "isolation", "holds_suite_lock", "reads", "writes", "produces"}
VALID_ISOLATION = {"shared", "worktree"}

# Dialeto de glob aceito em `writes[]`: literais, `*` (qualquer sequencia), `?` (um
# caractere) e `[...]` (classe de caracteres) - o subconjunto que `_glob_base` sabe
# comparar por prefixo do trecho literal. Expansao de chaves (`{a,b}`) NAO e deste
# dialeto: `_glob_base` trata `{`/`}` como literais, entao um padrao como `src/{a,b}/x.py`
# comparava como se fosse o arquivo literal `src/{a,b}/x.py` em vez de "src/a/x.py OU
# src/b/x.py" - falso negativo medido contra `src/a/x.py` (revisao independente). Em vez
# de comparar errado, o padrao e RECUSADO na validacao de metadados: aceitar um glob que
# nao se sabe comparar corretamente e o proprio fail-open que este modulo existe para evitar.
UNSUPPORTED_GLOB_CHARS = "{}"


def fail(msg: str) -> int:
    print(f"SCHEDULE_ERROR {msg}")
    return 1


def _dialeto_glob_invalido(pattern: str) -> str | None:
    """Primeiro caractere fora do dialeto suportado em `pattern`, ou None se valido."""
    for ch in UNSUPPORTED_GLOB_CHARS:
        if ch in pattern:
            return ch
    return None


def _glob_base(pattern: str) -> str:
    """Trecho literal antes do primeiro metacaractere de glob (`*`, `?`, `[`).

    O padrao e normalizado primeiro (`posixpath.normpath`: remove `./` inicial, barras
    duplicadas e `a/../` redundante) para que grafias equivalentes do MESMO caminho
    produzam a MESMA base. Sem isto, `./src/x.py` e `src/x.py` - o mesmo arquivo - geravam
    bases literais diferentes ("./src/x.py" vs "src/x.py") e o conflito nunca era
    detectado: falso negativo medido pela revisao independente. `normpath` nao interpreta
    `*`/`?`/`[...]` como componentes especiais de caminho, entao globs com esses
    metacaracteres atravessam a normalizacao inalterados.
    """
    pattern = posixpath.normpath(pattern) if pattern else pattern
    for i, ch in enumerate(pattern):
        if ch in "*?[":
            return pattern[:i]
    return pattern


def _writes_conflict(writes_a: list[str], writes_b: list[str]) -> str | None:
    """Par de padroes em conflito, ou None se pares-a-par disjuntos.

    Heuristica CONSERVADORA por prefixo do trecho literal (apos normalizacao de caminho em
    `_glob_base`): um padrao cujo trecho literal e prefixo do outro (nos dois sentidos) e
    tratado como conflito, mesmo quando o glob completo talvez nao colidisse em todo caso
    concreto. Isto pode marcar falso positivo em padroes-irmaos improvaveis. A assimetria e
    deliberada: o custo de serializar por engano e baixo, o de um conflito de escrita nao
    detectado (dado corrompido ou sobrescrito) e alto.

    "Nunca falso negativo" vale DENTRO do dialeto declarado em `UNSUPPORTED_GLOB_CHARS` (a
    validacao de metadados recusa o que estiver fora dele) e apos a normalizacao de
    caminho acima - as duas classes de falso negativo medidas pela revisao independente
    (grafia `./x` vs `x`, e expansao de chaves) sao cobertas por essas duas camadas, nao
    por esta funcao isoladamente.
    """
    for wa in writes_a:
        base_a = _glob_base(wa)
        for wb in writes_b:
            base_b = _glob_base(wb)
            if base_a.startswith(base_b) or base_b.startswith(base_a):
                return f"{wa} x {wb}"
    return None


def _ondas(nodes: list[str], edges: list[list[str]]) -> list[list[str]]:
    """Nivela o DAG por caminho mais longo (Kahn). Levanta ValueError se houver ciclo.

    Antes de nivelar, valida que toda aresta referencia so nos declarados em `nodes`. Sem
    isto, uma aresta cuja ORIGEM esta fora de `nodes` inflava o indegree de um no real sem
    nunca ser processada (a origem fantasma nunca entra na fila inicial), e o sintoma era
    `processados != len(nodes)` - reportado como "ciclo detectado", diagnostico ERRADO (nao
    ha ciclo, ha aresta invalida); uma aresta cujo DESTINO esta fora de `nodes` estourava
    `KeyError` cru em `level[m]`, sem SCHEDULE_ERROR nenhum. Ambos medidos pela revisao
    independente.
    """
    node_set = set(nodes)
    for a, b in edges:
        if a not in node_set:
            raise ValueError(f"aresta referencia no inexistente em 'nodes': {a!r} (origem)")
        if b not in node_set:
            raise ValueError(f"aresta referencia no inexistente em 'nodes': {b!r} (destino)")
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
            # MUTANTE EQUIVALENTE (nao consertar): `level[n] + 1` sem o `max` produziria o
            # MESMO resultado aqui. Kahn com fila FIFO desenfileira nos em ordem
            # NAO-DECRESCENTE de nivel (um no so entra na fila quando seu ULTIMO
            # predecessor - necessariamente o de maior nivel entre eles - e processado, e
            # esse predecessor so e processado depois de todos os predecessores de nivel
            # menor). Logo os predecessores de qualquer no `m` sao processados em ordem
            # nao-decrescente de nivel, e cada atribuicao a `level[m]` e >= a anterior - o
            # `max` e redundante NESTE ponto especifico do algoritmo. Verificado aqui por
            # simulacao propria (20000 DAGs aleatorios, arestas em ordem aleatoria, 0
            # divergencia entre as duas formas) e citado pela revisao independente como
            # testado sobre 300000 DAGs com o mesmo resultado (numero nao reproduzido
            # nesta sessao). Isto NAO generaliza para outro uso de `max` num nivelamento
            # com ordem de processamento diferente - a equivalencia depende do FIFO+Kahn
            # acima, nao e uma propriedade geral de "level[m] = level[n]+1".
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
                continue
            if campo == "writes":
                for padrao in valor:
                    ch = _dialeto_glob_invalido(padrao)
                    if ch:
                        erros.append(
                            f"{wf_id}:{nid}: writes tem sintaxe de glob fora do dialeto "
                            f"suportado ({ch!r} em {padrao!r}) - aceito: literais, '*', "
                            f"'?', '[...]'"
                        )
    return erros


def _fecho_transitivo(nodes: list[str], edges: list[list[str]]) -> dict[str, set[str]]:
    """Para cada no, o conjunto de descendentes alcancaveis por aresta (direta ou
    transitiva). Usado para decidir se dois nos tem relacao de precedencia `<` entre si em
    QUALQUER lugar do DAG, nao so dentro da mesma onda de `_ondas`.
    """
    succ: dict[str, list[str]] = defaultdict(list)
    for a, b in edges:
        succ[a].append(b)
    descendentes: dict[str, set[str]] = {}
    for n in nodes:
        vistos: set[str] = set()
        fila = deque(succ[n])
        while fila:
            m = fila.popleft()
            if m in vistos:
                continue
            vistos.add(m)
            fila.extend(succ[m])
        descendentes[n] = vistos
    return descendentes


def _checa_workflow(wf_id: str, wf: dict, sched: dict, cap: int) -> tuple[list[str], list[list[str]]]:
    wf_nodes = wf.get("nodes", [])
    erros = _valida_metadados(wf_id, wf_nodes, sched)
    if erros:
        return erros, []
    edges = wf.get("edges", [])
    try:
        ondas = _ondas(wf_nodes, edges)
    except ValueError as exc:
        return [f"{wf_id}: {exc}"], []

    # (2)/(3) cobrem toda ANTICADEIA do DAG - todo par de nos SEM relacao de precedencia
    # entre si, direta ou transitiva - nao so pares que caem na mesma onda de `_ondas`.
    # `_ondas` particiona por NIVEL (caminho mais longo ate a raiz): dois nos sem aresta
    # entre si podem cair em niveis DIFERENTES sem ter precedencia real (ex.: nodes
    # [a,b,x], edges [[a,b]] - `x` nao depende de nada e fica no nivel 0 com `a`, `b` fica
    # no nivel 1, mas `x` e `b` continuam sem relacao `<` entre si). O despacho real deste
    # repositorio e por PRONTIDAO, nao onda-a-onda sincronizada (CLAUDE.md; ADR 0007: fan-out
    # dos revisores "sem dependencia entre si, lancados na mesma mensagem") - dois nos
    # assim PODEM rodar ao mesmo tempo na pratica, entao a checagem de conflito precisa
    # cobrir o par, nao so o caso em que o nivelamento os agrupou. Medido: inerte nos 3
    # workflows reais deste repositorio (0 pares nessa condicao hoje) - a fixture que prova
    # o gap e sintetica.
    descendentes = _fecho_transitivo(wf_nodes, edges)
    for i in range(len(wf_nodes)):
        for j in range(i + 1, len(wf_nodes)):
            a, b = wf_nodes[i], wf_nodes[j]
            if b in descendentes[a] or a in descendentes[b]:
                continue  # tem precedencia `<` (direta ou transitiva): nunca concorrem
            writes_a, writes_b = sched[a]["writes"], sched[b]["writes"]
            if writes_a and writes_b:
                conflito = _writes_conflict(writes_a, writes_b)
                if conflito:
                    erros.append(
                        f"{wf_id}: conflito de escrita entre '{a}' e '{b}' (sem "
                        f"precedencia entre si): {conflito}"
                    )
            if (
                sched[a]["holds_suite_lock"] and sched[a]["isolation"] == "shared"
                and sched[b]["holds_suite_lock"] and sched[b]["isolation"] == "shared"
            ):
                erros.append(
                    f"{wf_id}: '{a}' e '{b}' (sem precedencia entre si) - mais de um no "
                    f"compartilhado disputa o lock de suite"
                )

    for idx, onda in enumerate(ondas):
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
