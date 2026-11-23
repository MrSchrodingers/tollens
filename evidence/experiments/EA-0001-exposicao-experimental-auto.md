# EA-0001 - designacao experimental_auto para exposicao de skills ao router

Registrado em 2026-09-09, no momento em que `orchestration/registry.json` passa a declarar
`exposure` como eixo independente de `state` (ADR 0044). Este documento e o alvo que
`eval_id: EA-0001` resolve para as capabilities marcadas `experimental_auto` -
`design-system-proposal`, `graphify`, `grill-me`, `prd-to-plan`, `write-a-prd`.

## O que esta sendo declarado, e o que nao esta

`experimental_auto` e autorizacao de GOVERNANCA para que o router selecione a skill
automaticamente, por prazo definido, enquanto a dimensao candidata E_A (ver
`orchestration/evidence-policy.json:dimensions_candidatas.E_A`) permanece sem oraculo que
confirme a ativacao de fato. Este registro NAO afirma que o router selecionou nenhuma das cinco
skills - `tests/unit/capability-conformance.py` (CC8) verifica a DECLARACAO no artefato, nao o
evento de runtime. Ler isto como prova de ativacao repeteria G6a (ADR 0036).

## Braco declarado (G108, issue #52)

As cinco capabilities desta lista declaram `exposure.arm: B_sistema_deployado`
(`orchestration/evaluation-protocol.json#design.arms`). O valor e B, nao A, porque o nudge de
`execution/hooks/graphify-scout-mode.sh` estava ativo (`TOLLENS_ROUTING_NUDGES` nao desligado) na
maioria das sessoes medidas para este registro - ver "Resposta ao criterio 3" abaixo. Um registro
de braco B nao sustenta afirmacao sobre `A_router_puro` (description-only sem nudge); estima
"skill + nudge produzem uso", nao "a description roteia sozinha".

## Resposta ao criterio 3 (o nudge estava ativo nas sessoes medidas?)

Medido cruzando `evidence/telemetry/medir-skills.sh` (88 chamadas de Skill observadas nos
transcripts) com a presenca do nudge `[GRAFO]` no mesmo transcript:

- 66/88 chamadas ocorreram em transcript com o nudge presente, sendo 28 na variante com
  `graphify-out/graph.json` (ramo `if` do hook) e 38 sem ele (ramo `elif`, "Repo sem knowledge
  graph...");
- 22/88 ocorreram em transcript sem o nudge;
- 0/88 chamadas correspondem a alguma das cinco skills deste repositorio (`design-system-proposal`,
  `graphify`, `grill-me`, `prd-to-plan`, `write-a-prd`) - o denominador de 88 e sobre skills em
  geral, nao sobre estas cinco.

Isso refuta a premissa de que o nudge exige `graph.json`: o ramo `elif` de
`graphify-scout-mode.sh` fala tambem sem o arquivo (ver correcao em
`docs/method/skill-evaluation-protocol.md`).

Limite declarado, para nao inventar precisao: a presenca de `[GRAFO]` foi apurada POR TRANSCRIPT,
nao por turno. Isso prova que o nudge foi entregue naquela sessao; NAO prova que foi entregue no
mesmo turno da chamada de Skill. "O nudge estava ativo na maioria das sessoes medidas" e
VERIFICADO; "estava ativo no turno exato de cada chamada" e NAO VERIFICADO.

## Por que estas cinco, e por que agora

As cinco ja eram, antes desta onda, as excecoes de `activation.model_invocable_exceptions` em
`orchestration/skill-policy.json`: elegibilidade a selecao pelo modelo (`disable-model-invocation`
ausente no frontmatter) sem `exposure` correspondente no vocabulario de governanca. O eixo novo
formaliza o que ja era mecanismo, com prazo e instrumento de medicao associados.

## Instrumentos de medicao disponiveis para esta janela

- `evidence/telemetry/medir-skills.sh` - varre transcripts (`~/.claude/projects/**/*.jsonl`) e
  separa invocacao pelo modelo de invocacao por comando do usuario. Medido em 2026-09 sobre 2502
  transcripts: as skills instaladas desta arvore aparecem com contagem zero nos dois canais.
- `control/hooks/activation-log.sh` - grava `PreToolUse(Skill)` em
  `/var/log/tollens-activation.jsonl`, canal independente do transcript. Medido: 36 eventos no
  periodo observado, nenhum correspondendo a uma das cinco skills desta lista.

Nenhum dos dois e conferido mecanicamente por este registro - `runtime` e `model` no bloco
`exposure` de cada capability permanecem DECLARADOS E NAO CONFERIDOS, o mesmo limite ja assumido
em `orchestration/evidence-policy.json:staleness.limit` para dossies de skill.

## Janela e disposicao

`started_at`: 2026-09-09. `expires_at`: 2026-12-08 (90 dias). Apos a expiracao,
`tests/unit/capability-conformance.py` reprova a designacao `experimental_auto` vencida - efeito
pretendido, nao falha de manutencao: renovar exige reescrever este registro com uma janela nova e
o que foi observado na anterior, ou rebaixar a exposicao para `manual`.

## Limite declarado

Este documento nao substitui dossie de skill (`skill-policy.json:promotion_requires`) nem paga
nenhuma das quatro dimensoes de `orchestration/evidence-policy.json:dimensions`. E registro de
AUTORIZACAO de exposicao, escopo unico desta onda.
