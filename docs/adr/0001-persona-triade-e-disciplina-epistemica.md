# ADR 0001 - Persona em triade filosofica e disciplina epistemica anti-sycophancy

- Status: Superseded por 0002-reforma-persona-colegio-analitico.md (2026-06-17). A persona
  Triade (Karnal/Cortella/Clovis com oscilacao Markov) foi substituida pelo Colegio
  Analitico. Mantido como registro historico; nao reflete a config vigente.
- Data: 2026-06-15
- Escopo: configuracao global do usuario (`~/.claude/`), todos os projetos
- Decisores: operador (mrschrodingers@gmail.com) + sessao principal

## Contexto

A persona global (`~/.claude/CLAUDE.md`, secao 1) era a voz "ET1155": youtuber
brasileiro de hype, teatral, com bordoes de aprovacao e celebracao. Dois problemas:

1. Um parecer comportamental (analise dos videos de Leandro Karnal conversando com
   uma IA) identificou risco de sycophancy: a tendencia de modelos ajustados por
   feedback humano a validar o enquadramento do usuario em vez de maximizar verdade,
   rigor e utilidade operacional. A voz de hype, por construcao, reforca esse vies
   (aplauso, concordancia, retorica inflada).
2. O operador pediu uma persona nova: oscilacao entre Leandro Karnal, Mario Sergio
   Cortella e Clovis de Barros Filho, com trejeitos, falas e referencias acuradas, e
   um comportamento quasi-cientifico, metodico e cetico, com arquitetura de validacao
   por agentes e tolerancia zero a erro pre-existente nao resolvido.

## Decisao

1. **Aposentar a voz ET1155 por completo.** A camada de estilo da resposta passa a
   oscilar entre tres vozes (Karnal, Cortella, Clovis de Barros Filho), descritas em
   fichas no CLAUDE.md a partir de pesquisa com fonte verificada.
2. **Oscilacao sticky (Markov-like).** A voz corrente persiste entre turnos; a troca e
   o evento minoritario (manter ~75-85%, trocar ~15-25%), preferindo pontos de
   inflexao. Uma voz por turno, sem rotulo.
3. **Separar estilo de substancia.** A voz e so user-facing (PT-BR). Codigo, commits,
   prompts de agente, docs, ADRs e strings de erro permanecem neutros. A erudicao
   serve ao argumento e nunca substitui evidencia; citacao so quando exata e
   verificavel; zero citacao fabricada.
4. **Codificar a disciplina epistemica do parecer** nas diretrizes de engenharia:
   nao elogiar o operador, tratar afirmacao do usuario como hipotese, metodo
   obrigatorio antes/depois de editar, criterio de aceitacao da resposta.
5. **Formalizar o pipeline de validacao** (CLAUDE.md secao 7) reusando os agentes
   existentes e adicionando `revisor-critico` como portao adversarial final, que
   tambem audita disciplina epistemica (inclusive a saida dos outros agentes).
6. **Reforco de hook.** `no-emoji.sh` evolui para `artifact-discipline.sh`: alem de
   emoji, bloqueia o vazamento do lexico de hype/bajulacao para artefatos nao-meta.

## Alternativas consideradas

- **Manter ET1155 como 4o modo raro** (so para vitoria tecnica): descartada. O tom de
  hype contradiz a disciplina anti-bajulacao; coexistir abre brecha para o vies.
- **Uma unica voz filosofica** (ex.: so Karnal): descartada. O operador pediu
  explicitamente a oscilacao bipolar entre os tres.
- **Oscilacao com rotulo** (assinar quem fala): descartada. Menos imersiva; a erudicao
  e as referencias ja denunciam a voz.
- **Oscilacao por turno sem persistencia**: descartada apos refinamento do operador.
  Trocar a cada turno deixa a persona instavel (pinball). Persistencia sticky resolve.
- **Hook que escaneia o chat por bajulacao**: descartada. Hooks de Write/Edit nao veem
  o texto do chat; um hook de Stop que forca revisao geraria loop. A defesa primaria
  contra sycophancy e textual (CLAUDE.md) + `revisor-critico`; o hook so guarda
  artefato. Vende-lo como mais que isso seria teatro, o que o proprio parecer condena.

## Consequencias

- Positivas: persona coerente com o eixo cetico-rigoroso; referencias verificaveis;
  disciplina anti-sycophancy explicita e parcialmente enforcada; pipeline de revisao
  com portao final adversarial; backups preservados.
- Custos/limites: o pipeline completo multiplica tokens (varios agentes opus) — usar
  so quando a tarefa justifica (CLAUDE.md secao 13). A oscilacao sem RNG e qualitativa,
  nao estatisticamente garantida. O hook cobre artefato, nao o chat.

## Revisao adversarial e hardening (2026-06-15)

Os artefatos passaram por tres revisores (cetico, revisor-consistencia e o portao
revisor-critico em dogfood), com evidencia executada. Defeitos confirmados foram
corrigidos na fonte (politica de bug pre-existente, secao 2.1 do CLAUDE.md):

- Hook fail-open silencioso sem jq -> agora fail-closed (exit 2 com mensagem acionavel).
- Isencao meta ampla demais (`*/agents/*`, `*/hooks/*`, `*/docs/adr/*` casavam qualquer
  projeto) -> ancorada em `*/.claude/*`. Codigo de projeto sob `src/agents/`,
  `docs/adr/`, `hooks/` fica sujeito a Regra 2.
- MultiEdit (`edits[].new_string`) e NotebookEdit (`new_source`) nao inspecionados ->
  adicionados ao jq; matcher explicitado para `Write|Edit|MultiEdit|NotebookEdit`.
- Range de emoji incompleto (estrela U+2B50 e outros escapavam) -> estendido
  (`2B00-2BFF`, `1F000-1F2FF`, `FE0F`).
- Falso-positivo "excelente ponto de partida" -> termos ambiguos removidos do lexico;
  lexico do hook reconciliado com o CLAUDE.md (hook = subconjunto inequivoco; a
  disciplina anti-bajulacao plena do chat fica na secao 3).
- Citacao: rotulo "verified" sem fonte rebaixado para "researched attribution"; Cortella
  deixou de ser cravado como nao-catolico (posicao publicamente ambigua); etimologia
  sanskrita fragil de criterio/critica removida; "quem nao vive para servir" descrita
  como apocrifa (a atribuicao a Gandhi e ela propria contestada).
- `revisor-critico` revisava `git diff` vazio em branch ja commitada -> instruido a
  comparar contra a base (`<base>...HEAD` / `--staged`) e nunca julgar diff vazio.
- Pipeline global vs gate de projeto reconciliados (a skill `quality-gates` do DEBTHUB
  tem precedencia; `revisor-critico` e o default quando o projeto nao define o seu).
- `no-emoji.sh` removido de `hooks/` (dead file re-wirable); backup preservado.

Riscos residuais assumidos (nao corrigiveis por hook): a oscilacao 75-85/15-25 e
qualitativa (LLM sem RNG/estado); a eficacia anti-sycophancy no chat nao tem enforcement
mecanico, depende de o modelo seguir o texto.

## Arquivos afetados

- `~/.claude/CLAUDE.md` (reescrito; backup em `~/.claude/backups/`)
- `~/.claude/agents/revisor-critico.md` (novo)
- `~/.claude/hooks/artifact-discipline.sh` (novo; supersede `no-emoji.sh`)
- `~/.claude/settings.json` (PreToolUse aponta para o novo hook)
- `~/.claude/docs/adr/0001-persona-triade-e-disciplina-epistemica.md` (este arquivo)
