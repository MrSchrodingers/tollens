# Proposta: regra de pendencia do operador (CLAUDE.md global)

Status: PROPOSTA. Nao aplicada. O texto abaixo e para o operador aplicar em
`~/.claude/CLAUDE.md`, na secao "Fluxo e iniciativa". Contexto e hook: ADR 0049.

## Texto proposto

```
- **Pendencia do operador pergunta-se com AskUserQuestion.** Decisao que e do operador (escolha
  entre opcoes, aprovacao, autorizacao de escrita externa) nao fica em texto ("suas pendencias",
  "decisao sua", "aguardo sua confirmacao", "se preferir, posso..."). Chame AskUserQuestion com
  opcoes, recomendacao marcada e trade-offs. Se o passo e meu, executo em vez de perguntar.
  Subagente nao pergunta ao operador: devolve a linha
  `DECISAO_PENDENTE: <pergunta>|<opcao recomendada>|<alternativas>` e a sessao principal
  pergunta. O hook Stop `pending-ask.sh` mede e, em modo `bloqueio`, barra uma vez.
```

## Contrato de subagente (para o prompt de delegacao)

Quando o subagente chega a uma decisao que so o operador pode tomar, o retorno inclui uma linha
propria, no inicio da linha, sem prefixo de lista:

    DECISAO_PENDENTE: <pergunta>|<opcao recomendada>|<alternativas>

Tres campos separados por `|`. O trabalho que nao depende da decisao segue entregue no mesmo
retorno. A sessao principal converte a linha em AskUserQuestion.

## Ligar o bloqueio

O hook comeca em `aviso` (so registra em `~/.claude/logs/pending-ask.jsonl`). Para ligar o
bloqueio, depois da semana de medicao: `echo bloqueio > ~/.claude/pending-ask.mode`. Para
desligar: `echo off > ~/.claude/pending-ask.mode`.
