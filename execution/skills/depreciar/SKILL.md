---
name: depreciar
description: Mede o uso REAL de cada skill e agente a partir dos transcripts e propoe depreciacao com evidencia. Acionar com /depreciar periodicamente, quando as skills instaladas passarem de ~10, quando o custo de descricao no system prompt incomodar, ou antes de instalar algo novo. Nunca arquiva sozinho - propoe e mostra a evidencia.
disable-model-invocation: true
---

# /depreciar - fechar o ciclo de vida

Skill acumula. Nada as remove. E assim que uma config chega a 25 skills das quais 22 nunca
foram usadas, pagando descricao no system prompt de toda sessao por capacidade que nao existe.

Este e o outro lado do `/forge`: criar exige benchmark, manter exige **utilidade sobre
oportunidade elegivel**.

A formulacao anterior era "manter exige uso", e o denominador estava errado. Uma capability de
recuperacao de desastre com zero uso em doze meses pode estar perfeita - nao houve desastre. O
que se mede e:

    TriggerRecall    = disparos elegiveis / oportunidades elegiveis
    TriggerPrecision = disparos elegiveis / disparos totais
    UtilidadeMarginal = Q_com - Q_sem

`sessoes` nao e denominador: uma capability especializada deve ficar em silencio quando nenhuma
tarefa elegivel ocorreu, e silencio nesse caso e o comportamento CORRETO.

## Passo 1 - MEDIR, os dois canais

```
bash evidence/telemetry/medir-skills.sh
```

**A armadilha que este passo existe para evitar, e ela ja custou uma decisao errada:** skill
tem dois canais de invocacao e eles aparecem de formas DIFERENTES no transcript.

| Canal | Como aparece | Consultar so este da |
|---|---|---|
| Modelo invoca | `tool_use` com `name="Skill"` | falso "nunca usada" para skill que o usuario chama |
| Usuario digita `/nome` | texto do usuario, **sem tool_use algum** | falso "nunca usada" para skill que o modelo aciona |

Caso real: `defesa-de-tese` tinha **0** no canal do modelo e **7** no canal do usuario. Foi
arquivada por engano, e o erro so apareceu ao consultar o segundo canal.

## Passo 2 - As tres ressalvas. Zero uso NAO e prova de inutilidade

Aplicar cada uma, por escrito, antes de propor:

**(a) A skill e nova?** Sem tempo de uso, zero e ausencia de dado, nao evidencia. Regra: menos
de 30 dias ou menos de ~20 sessoes desde a criacao -> nao proponha.
   Estes dois numeros sao DEFAULT OPERACIONAL PROVISORIO, nao limiar empiricamente validado.
   Nao ha medicao que os sustente; eles existem para impedir depreciacao apressada, e devem
   ceder a contagem de oportunidades elegiveis assim que ela existir.

**(b) O gatilho da `description` esta errado?** A skill pode ser util e nunca disparar porque a
descricao nao casa com o jeito que voce pede. Aqui o defeito e de ROTEAMENTO, e depreciar seria
jogar fora capacidade por erro de rotulo. Teste: escreva 3 pedidos que DEVERIAM aciona-la e
veja se a descricao os cobre. O `skill-creator` oficial automatiza isso (gera prompts
should-trigger e should-not-trigger e mede o acerto).

**(c) Existe ARTEFATO no disco que ela produziria?** Procure a SAIDA, nao so a chamada. Um PRD,
um plano, um relatorio. Se o artefato existe e a invocacao nao, provavelmente o trabalho foi
feito sem a skill - o que e evidencia de que ela e dispensavel, OU de que o gatilho falhou
(volta ao item b). Distinga os dois antes de concluir.

Exemplo real de (c) mudando a decisao: `design-system-proposal` tinha zero invocacao, mas havia
`design-system-proposal-skill.zip` e `design-system-lab-prompt.md` no disco. Foi mantida.

## Passo 3 - PROPOR, nunca arquivar sozinho

Apresente ao usuario, para cada candidata:

```
<nome>   uso: 0 (modelo) + 0 (/cmd)   custo: <N> B/sessao   idade: <dias>
  ressalva (a) nova?           <sim/nao, com a data>
  ressalva (b) gatilho ok?     <os 3 pedidos testados>
  ressalva (c) artefato?       <caminho encontrado, ou "nenhum">
  proposta: ARQUIVAR | MANTER | CORRIGIR DESCRICAO
```

**Arquivar e sempre REVERSIVEL, e o git ja e o mecanismo:** APAGAR o diretorio da capability e
registrar o tombstone em `orchestration/registry.json:capabilities` (`state: deprecated`,
`retired_at`, `superseded_by`, `reason`). `git revert` devolve o conteudo em um comando.
NAO criar `backups/skills-arquivadas-<data>/`: manter capability aposentada na arvore ativa e
cemiterio, e este repositorio ja pagou por isso - `defesa-de-tese` sobreviveu meses depois de
declarada absorvida, com SKILL.md executavel intacto.

## O mesmo vale para AGENTE

Agente custa descricao no system prompt igual a skill, e o criterio e mais duro: ele so existe
se tiver **fonte de sinal externo** (execucao, render, ferramenta, contexto separado). Agente
sem fonte de sinal e sem uso nao e candidato a depreciacao - e erro de desenho, e sai.

Meca com o log da sonda:

```
jq -r 'select(.hook_event_name=="SubagentStop" and (.agent_type//"")!="") | .agent_type' \
  ~/.claude/logs/subagent-probe.jsonl | sort | uniq -c | sort -rn
```

## O mesmo vale para PLUGIN, e o canal e OUTRO

Plugin nao aparece no log de ativacao: o registrador cobre `PreToolUse(Skill)`, `SubagentStart` e
`InstructionsLoaded`, e a ferramenta de um plugin MCP ou LSP nao passa por nenhum dos tres. Medir
plugin pelo log de ativacao devolve zero para todos, e zero ali nao significa nada.

O canal certo sao os TRANSCRIPTS em `~/.claude/projects/**/*.jsonl`, onde o nome da ferramenta
aparece como `"name":"..."`. Conte por SUBSTRING INTEIRA do nome do plugin
(`mcp__plugin_context7`, `mcp__plugin_playwright`, `"name":"LSP"`), e para skill conte
`"skill":"<nome>"`.

CUIDADO COM O GRUPO DA REGEX - a armadilha ja ocorreu. Medindo em 2026-09-01 com
`mcp__plugin_([a-z0-9_]+)_[^"]+` e agrupando pelo grupo 2, o `context7` apareceu com 5 chamadas:
o grupo cortava o nome e espalhava a contagem por variantes. Com a substring inteira sao
**744 chamadas em 144 sessoes**. A sonda dizia "quase nao usado" sobre o plugin MAIS usado da
maquina. Confira a soma contra uma contagem por substring simples ANTES de propor desligamento.

O ESTADO MORA EM `~/.claude/settings.json`, chave `enabledPlugins`. Desligar e por o valor em
`false`, nao remover a entrada - remover perde o registro de que a decisao foi tomada. Faca backup
antes: o arquivo carrega permissoes e hooks.

A TERCEIRA RESSALVA MUDA DE PESO AQUI. Para skill, zero uso costuma ser oportunidade que nao
ocorreu. Para um LSP de linguagem que o operador usa TODO DIA, oportunidade houve as centenas -
medido: `LSP` com ZERO chamadas em 1077 transcripts, numa maquina com trabalho diario em Python e
TypeScript. Ali zero e evidencia, nao ausencia dela. Diga QUAL das duas voce esta afirmando, e
mostre o denominador.

## O que NAO fazer

- Nao deprecie por "parece redundante". Meca.
- Nao deprecie por tamanho do corpo: o corpo so entra em contexto quando invocada. O que custa
  em toda sessao e a **descricao**.
- Nao conte "nao vi usar" como dado. `n` pequeno e ausencia de evidencia, e a diferenca importa:
  com 9 observacoes e zero eventos, a regra de tres da 33% de limite superior.
