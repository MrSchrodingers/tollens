# Transitive trust root for managed guidance

Status: **CANDIDATE — depends on PR #35 merge/CI**  
Date: 2026-08-25  
Related: G25, issue #31

## The defect

The first G25 description said the managed `read-budget.sh` hook directly executed a user-writable doctool. That wording was too strong.

The actual behavior was:

```text
root-owned managed hook
  -> reads the adapter registry
  -> builds a blocking message
  -> publishes a recipe containing a doctool path
  -> the agent may execute that recipe later
```

The defect is still material: enforced guidance could direct the agent to an executable inside the governed actor's writable space. The correct property is **guidance-to-executable**, not direct hook execution.

## Invariant

When `read-budget.sh` runs from a managed tree whose physical hook directory ends in `/opt/tollens/hooks`:

```text
DOCTOOL = <same trust root>/document-tools/doctool.sh
DOCREG  = <same trust root>/adapters/documents
```

Actor-supplied `HOME`, `DOCTOOL_BIN`, and `DOC_ADAPTERS_DIR` must not change those two referents in managed mode.

Outside the managed tree, user-scope behavior is preserved and explicit overrides remain valid.

## Why derive from the hook location

Classification does not depend on a caller-controlled `managed=true` label. It is derived from the installed hook's physical location. Test prefixes also end in `/opt/tollens/hooks`, so the property can be exercised without sudo.

This follows the principle:

```text
Observe/derive > trust declaration
```

## Oracle

`tests/unit/managed-transitive-trust.sh` creates at the same time:

- a managed fixture tree;
- a managed registry and doctool;
- hostile-looking but valid `HOME` + override paths;
- a user-scope control copy.

The managed case must publish only the adapter/doctool from its trust root. The user-scope control must still use its configured paths.

`tests/mutation/managed-transitive-trust.sh` makes the managed-location branch unreachable. The suite must fail. An inert edit must remain green.

## Limits

This mechanism does not establish:

- a Bash sandbox;
- that the model always follows or never follows the recipe;
- safety of all guidance;
- causal utility of `read-budget`;
- integrity of capabilities that still live in user scope.

It establishes a narrower property: **the recipe emitted by managed `read-budget` does not derive its helper/registry from the user's writable space**.
