---
name: depreciar
description: Mede o uso REAL de cada skill e agente a partir dos transcripts e propoe depreciacao com evidencia. Acionar com /depreciar periodicamente, quando as skills instaladas passarem de ~10, quando o custo de descricao no system prompt incomodar, ou antes de instalar algo novo. Nunca arquiva sozinho - propoe e mostra a evidencia.
disable-model-invocation: false
---

# /depreciar - fechar o ciclo de vida

Skill acumula. Nada as remove. E assim que uma config chega a 25 skills das quais 22 nunca
foram usadas, pagando descricao no system prompt de toda sessao por capacidade que nao existe.

Este e o outro lado do `/forge`: criar exige benchmark, **manter exige uso**.

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

**Arquivar e sempre REVERSIVEL:** mover para `backups/skills-arquivadas-<data>/`, nunca apagar.
Uma skill arquivada por engano precisa voltar em um comando - e ja precisou.

## O mesmo vale para AGENTE

Agente custa descricao no system prompt igual a skill, e o criterio e mais duro: ele so existe
se tiver **fonte de sinal externo** (execucao, render, ferramenta, contexto separado). Agente
sem fonte de sinal e sem uso nao e candidato a depreciacao - e erro de desenho, e sai.

Meca com o log da sonda:

```
jq -r 'select(.hook_event_name=="SubagentStop" and (.agent_type//"")!="") | .agent_type' \
  ~/.claude/logs/subagent-probe.jsonl | sort | uniq -c | sort -rn
```

## O que NAO fazer

- Nao deprecie por "parece redundante". Meca.
- Nao deprecie por tamanho do corpo: o corpo so entra em contexto quando invocada. O que custa
  em toda sessao e a **descricao**.
- Nao conte "nao vi usar" como dado. `n` pequeno e ausencia de evidencia, e a diferenca importa:
  com 9 observacoes e zero eventos, a regra de tres da 33% de limite superior.
