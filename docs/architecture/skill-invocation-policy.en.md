# Skill invocation policy

Status: **CANDIDATE — depends on CI/merge**  
Date: 2026-08-25  
Related: #33

## Principle

The target is not to maximize how many Skills get used. It is to maximize correct selection and marginal utility.

```text
INSTALLED != TRIGGERED != USEFUL
```

A rare Skill may be correct if eligible tasks are rare. Forcing usage turns routing into ritual.

## Side effects

Workflows that mutate external state and whose timing should remain user-controlled are manual-only. Claude Code represents this with:

```yaml
disable-model-invocation: true
```

The flag also removes the Skill description from automatic context, reducing both accidental triggering surface and context cost for manual workflows.

### Current decision

`prd-to-issues` contains `gh issue create` and creates remote GitHub state. It becomes manual-only.

This decision is **not** generalized by analogy to every other Skill. `graphify`, for example, remains eligible for automatic routing while routing/utility are evaluated.

## E_A — activation evaluation

For model-invocable Skills, measure separately:

```text
TriggerRecall    = TP / (TP + FN)
TriggerPrecision = TP / (TP + FP)
UtilityDelta     = Q_with - Q_without
CostDelta        = tokens/latency_with - baseline
```

Development and held-out trigger prompts must be separate. Editing a description until it passes the prompts used to write it and calling that “better routing” is overfitting.

## What this PR proves

The narrow oracle protects only two current decisions:

1. the known Skill that executes `gh issue create` is manual-only;
2. `graphify` was not disabled as a collateral blanket fix.

It does not attempt to semantically infer every possible side effect using regex.

## Limits

- manual-only does not establish internal implementation safety;
- manual-only does not establish utility;
- automatic routing of other Skills remains NOT_VERIFIED until #33 experiments it;
- a local/temporary side effect is not automatically equivalent to an irreversible remote side effect.
