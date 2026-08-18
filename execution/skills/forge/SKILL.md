---
name: forge
description: Cria skill de dominio ou agente novo, com gatilho estreito e BENCHMARK obrigatorio antes de virar permanente. Acionar com /forge quando o usuario pedir uma skill ou um agente novo, ou quando um padrao especifico do projeto (Temporal, Django, Pipedrive, Grafana) se repetir a ponto de justificar conhecimento dedicado.
disable-model-invocation: false
---

# /forge - criar skill ou agente sem piorar o sistema

Funde os antigos `skill-builder` e `agent-builder`. A duplicacao de construtores degrada a
instrucao: quando quatro caminhos criam a mesma coisa, nenhum e seguido de forma consistente.

## Regra zero: o default e NAO criar

Medido em 49 skills sobre ~565 tarefas reais de engenharia de software (SWE-Skills-Bench,
arXiv:2603.15401): **39 nao produziram ganho algum**, o ganho medio foi **+1.2%**, e **3
DEGRADARAM** o desempenho. Ganho relevante (ate +30%) apareceu so em skills de dominio
especifico com bom encaixe.

Consequencia: skill nova comeca com **expectativa negativa**. O onus e de quem cria.

Antes de escrever qualquer arquivo, responda por escrito:
1. **Ja existe?** Liste as skills e agentes atuais. Dominio ja coberto -> NAO crie; aponte o
   existente, ou estenda so o delta.
2. **E dominio ou e generico?** "Escrever bons testes" e generico e nao paga. "Como este repo
   registra activity e workflow no Temporal, com os nomes de fila e a politica de retry que ja
   usamos" e dominio e paga. Conhecimento que o modelo ja tem nao vira skill.
3. **Qual o gatilho ESTREITO?** Descricao ampla ("qualquer pergunta sobre o codebase") faz a
   skill carregar quando nao deveria, e o corpo dela fica em contexto ate o fim da sessao.
4. **Deveria ser hook em vez de skill?** Se a regra e verificavel de forma deterministica
   (caminho existe, lint passa, formato do retorno), hook custa ZERO contexto e nao depende de
   o modelo lembrar. Regra vira hook; conhecimento vira skill.

## Se, e so se, passar na regra zero

**Estrutura.** `~/.claude/skills/<nome>/SKILL.md` com frontmatter `name` e `description`.
Corpo enxuto: uma vez invocada, a skill fica em contexto pelo resto da sessao - cada linha e
custo recorrente. Detalhe longo vai para `references/*.md`, que so e lido quando preciso.

**Frontmatter que importa:**
- `description` - o roteador. Diga QUANDO usar e quando NAO usar. E o campo que decide se a
  skill dispara na hora errada.
- `paths` - globs que limitam a ativacao (ex.: `**/workflows/**,**/activities/**`). E o
  mecanismo certo para a skill de dominio: fora dos arquivos que importam, custo zero.
- `disable-model-invocation: true` - para o que tem efeito colateral (deploy, commit, envio).
  Tira a descricao do contexto e so voce dispara.
- `allowed-tools` - pre-aprova ferramentas so no turno da invocacao.
- `context: fork` + `agent:` - roda a skill em subagente isolado, sem herdar a conversa.

**Conteudo.** Fato concreto do dominio: nomes reais de modulo, convencao de import, armadilha
ja encontrada, comando exato. Nao reescreva o manual da biblioteca - para documentacao de
biblioteca, use `context7`. Instrucao imperativa e curta; sem narrativa de por que.

## Portao: medir antes de tornar permanente

Skill sem medicao e aposta com expectativa negativa. Use o `skill-creator` oficial:

```
/plugin install skill-creator@claude-plugins-official      # se ainda nao instalado
```
Peca a avaliacao da skill nova. Ele roda o laco que importa:
- casos de teste em `evals/evals.json`;
- execucao ISOLADA por subagente (contexto limpo, senao o contexto da autoria mascara as
  lacunas da instrucao escrita), registrando tokens e duracao;
- `benchmark.json` com taxa de acerto **com** vs **sem** a skill, para comparar o ganho contra
  o custo de token;
- ajuste de descricao: gera prompts que DEVEM e que NAO DEVEM disparar e mede o acerto do
  roteamento.

**Criterio de aceite:** a skill so fica se o ganho de taxa de acerto superar o custo de token
e de latencia, e se o roteamento nao disparar onde nao deve. Sem ganho medido, arquive. Nao
existe "mantem porque parece util" - foi exatamente assim que se acumulam 39 skills inuteis.

## Criar AGENTE em vez de skill

Agente se justifica por **isolamento de contexto** ou por **ferramenta propria**, nunca por
"papel" ou personalidade. O criterio decisivo e um so: a colaboracao introduz INFORMACAO NOVA
que a sessao principal nao teria durante a geracao?

- Reler a propria saida em outro papel: **nao** ha informacao nova - costuma ser inutil ou
  prejudicial.
- Agentes debatendo o mesmo texto: **nao** ha informacao nova - equivale a um agente com o
  mesmo orcamento de computacao.
- Revisor que usa **resultado de execucao**, **screenshot renderizado** ou **ferramenta
  externa**: **ha** informacao nova - melhora de forma significativa.

Se o agente proposto nao entra na terceira categoria, ele nao deve existir: vira uma checklist
no prompt. E o custo nao e pequeno - um sistema multi-agente pode consumir cerca de 15x os
tokens de uma conversa normal, e o proprio volume de tokens explica a maior parte da diferenca
de desempenho. O ganho precisa cobrir esse fator.

Arquivo em `~/.claude/agents/<nome>.md`, frontmatter com `name`, `description` (o gatilho),
`tools` (o minimo necessario), `model`. O corpo termina exigindo o contrato
RESULTADO / EVIDENCIA / RISCOS / PROPAGACAO - o hook `subagent-contract.sh` verifica a ancora.

## Depois de criar

Registre em `docs/` o que foi criado, o gatilho, e o numero de benchmark que justificou.
Skill ou agente sem essa linha e divida, nao capacidade.

## O ciclo nao termina na criacao

`/forge` e metade do ciclo. A outra e `/depreciar`, que mede uso REAL e propoe remocao.
Criar exige benchmark; **manter exige uso**. Sem a segunda metade, a config so cresce - e foi
assim que a versao anterior chegou a 25 skills das quais 22 nunca haviam sido invocadas,
pagando descricao no system prompt de toda sessao por capacidade inexistente.

Ao criar, ja registre a data. `/depreciar` precisa dela para aplicar a ressalva "a skill e
nova?" - sem data, zero uso e ambiguo entre "inutil" e "recem-criada".
