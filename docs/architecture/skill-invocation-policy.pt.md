# Política de invocação de Skills

Estado: **CANDIDATO — depende de CI/merge**  
Data: 2026-08-25  
Relacionado: #33

## Princípio

O objetivo não é maximizar o número de Skills usadas. É maximizar seleção correta e utilidade marginal.

```text
INSTALLED != TRIGGERED != USEFUL
```

Uma Skill rara pode estar correta se raramente houver tarefa elegível. Forçar uso transforma routing em ritual.

## Side effects

Workflows que alteram estado externo e cujo timing deve permanecer sob controle do usuário são manual-only. No Claude Code isso é representado por:

```yaml
disable-model-invocation: true
```

A flag também retira a descrição da Skill do contexto automático. Portanto reduz simultaneamente risco de acionamento e custo de contexto para workflows manuais.

### Decisão atual

`prd-to-issues` contém `gh issue create` e cria estado remoto no GitHub. Ela passa a ser manual-only.

A decisão **não** é aplicada por analogia às demais Skills. `graphify`, por exemplo, continua elegível ao routing automático enquanto sua utilidade/routing são medidos.

## E_A — avaliação de ativação

Para Skills auto-invocáveis, medir separadamente:

```text
TriggerRecall    = TP / (TP + FN)
TriggerPrecision = TP / (TP + FP)
UtilityDelta     = Q_with - Q_without
CostDelta        = tokens/latency_with - baseline
```

Conjuntos de prompts de desenvolvimento e held-out devem ser distintos. Ajustar a `description` até passar nos próprios exemplos e chamá-lo de routing melhor é overfit.

## O que este PR prova

O oráculo estreito verifica apenas duas decisões atuais:

1. a Skill conhecida por executar `gh issue create` está manual-only;
2. `graphify` não foi desabilitada como consequência colateral.

Ele não tenta inferir semanticamente todos os side effects possíveis por regex.

## Limites

- manual-only não prova segurança da implementação interna;
- manual-only não prova utilidade;
- routing automático de outras Skills continua NOT_VERIFIED até o experimento de #33;
- side effect local/temporário não é automaticamente equivalente a side effect remoto irreversível.
