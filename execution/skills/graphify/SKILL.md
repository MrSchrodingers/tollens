---
name: graphify
description: Constroi e consulta um grafo de codigo do repositorio (AST) para achar call-sites, blast-radius e hotspots ANTES de um fan-out de grep/read. Acionar SO em tarefa nao trivial de refactor, auditoria ou exploracao ampla, e preferencialmente quando graphify-out/graph.json ja existe. NAO acionar para pergunta pontual sobre um arquivo conhecido - ai grep dirigido e mais barato.
---

# /graphify - batedor de orientacao, nunca oraculo

Estreita o alvo antes da leitura cara: em vez de ler tudo, o grafo aponta os poucos pontos que
importam e os agentes leem so esse conjunto.

## Quando NAO usar (leia primeiro)

- Pergunta pontual sobre arquivo ou simbolo que voce ja sabe onde fica: `rg` e mais barato.
- Repo sem `graphify-out/` e tarefa de uso unico: o custo de construir nao se paga.
- Como fonte de verdade: ver o guardrail abaixo.

## Uso

```
graphify extract . --code-only     # AST puro: sem LLM, sem API key, de graca. Comece por aqui.
graphify update .                  # refresh incremental, barato. Rode antes de confiar no mapa.
/graphify query "<tema>"           # hotspots e call-sites (fast-path, sem rebuild)
/graphify explain "<simbolo>"      # blast-radius de uma mudanca
```

A camada SEMANTICA (`/graphify . --directed`) usa LLM e custa ordens de grandeza mais. Reserve-a
para mapear docs e rationale, nunca por reflexo. Para orientacao de CODIGO, `--code-only` cobre
a maior parte do valor de graca.

## GUARDRAIL (o que refuta o mau uso)

O grafo e HIPOTESE, nunca conclusao. A camada de codigo e AST estatica: **nao enxerga dispatch
dinamico** - signals do Django, autodiscover do admin, URL por string, registry do Temporal,
`getattr`, importacao tardia. A camada semantica e LLM, logo probabilistica.

Consequencias praticas, medidas em uso:
- "orfao no grafo" teve precisao baixa sem triagem - a maioria era alcancada por dispatch
  dinamico que o AST nao ve. Nunca remova codigo por ser orfao no grafo, sem confirmar na fonte.
- "fan-in alto" NAO implica god object: pode ser modulo profundo e bem reusado, que e exatamente
  o que se quer.
- Aresta `INFERRED` ou `AMBIGUOUS` e palpite rotulado, nao fato.

Todo sinal do grafo termina numa leitura do codigo real. O ganho e de token e de tempo - o grafo
reduz o conjunto a ler; ele nao substitui a leitura.

## Detalhe

`references/full-manual.md` (manual completo), `query.md`, `update.md`, `extraction-spec.md`,
`exports.md`, `hooks.md`, `add-watch.md`, `github-and-merge.md`, `transcribe.md`.
