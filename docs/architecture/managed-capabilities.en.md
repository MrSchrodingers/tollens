# Managed-native capabilities in Claude Code

Status: **PROPOSAL / NOT IMPLEMENTED**  
Date: 2026-08-25  
Related: #32, G24, G25, G6b

## Problem

Tollens already has a managed policy plane (`/etc/claude-code/managed-settings.json` and `/opt/tollens/{hooks,adapters,document-tools}`), while `CLAUDE.md`, agents and Skills are still primarily projected into `~/.claude`. That collapses four different properties:

1. **INSTALLED** — expected bytes exist;
2. **ENFORCED** — the governed actor cannot replace the effective version;
3. **ACTIVATED** — the runtime actually loaded/selected the capability;
4. **USEFUL** — the capability improves an independent outcome at acceptable cost.

`install/verify.sh` mainly establishes (1). It must not be used as evidence for (2)–(4).

## Proposed decision

Use Claude Code's native managed primitives for the organizational projection while keeping the repository as the canonical source:

```text
/etc/claude-code/CLAUDE.md
/etc/claude-code/.claude/agents/
/etc/claude-code/.claude/skills/
```

The personal `~/.claude` scope remains available for non-governed preferences/capabilities. The migration does **not** make the entire user scope root-owned.

## Invariants

### M1 — one canonical source

Canonical inputs remain:

```text
execution/config/CLAUDE.md
execution/agents/*.md
execution/skills/*/
```

The installer renders projections. A second hand-maintained copy is forbidden as a source of truth.

### M2 — transactional deployment

Managed projection must follow the current privileged installer model:

```text
source snapshot
  -> staging
  -> digest/schema/mode/owner checks
  -> publish
```

An observed pre-commit failure must not leave the active state partially updated.

### M3 — no active duplicate

After managed precedence has been demonstrated on the supported runtime, the equivalent user-scope projection must be removed. Two active copies with the same name reopen the question “which one was loaded?”.

### M4 — activation is observed, not inferred

- CLAUDE.md: `InstructionsLoaded` with the expected path/type;
- agent: `SubagentStart`/transcript with the expected `agent_type`;
- Skill: Skill event/tool-use, or explicit preload configured on an agent.

Missing observability means `NOT_VERIFIED`, not “probably loaded”.

### M5 — usefulness does not follow from activation

A capability may trigger correctly and still worsen quality or cost. `ACTIVATED` does not pay `E_U`.

## Target manifest model

The current schema should distinguish projection from lifecycle. Conceptual example:

```yaml
id: refutador
kind: agent
source: execution/agents/refutador.md
projections:
  claude_user:
    installed: false
  claude_managed:
    installed: true
  codex:
    installed: true
```

`state`, `installed`, and `projection` are separate dimensions.

## Required probes before merge

### P1 — managed CLAUDE

With a conflicting user CLAUDE and a sentinel managed CLAUDE, the runtime must record the expected managed `InstructionsLoaded` event and observed behavior must match the documented precedence.

### P2 — managed agent

Create user and managed agents with the same `name` and distinguishable markers. Invocation must execute the managed one. The probe must observe `SubagentStart` plus a discriminating output.

### P3 — managed Skill

Create a fixture Skill with the same name in user and managed scopes and a discriminating outcome. Confirm precedence. Measure automatic routing separately: existence/precedence do not prove triggering.

### P4 — rollback

After managed deployment, `--revert` must restore the previous state exactly and must not delete third-party pre-existing policy.

### P5 — mutation

For every property above, remove the guarantee in the fixture/config and require the test to fail. An inert control mutation must remain green.

## Relationship to G25

This migration does **not** close G25 by itself. A root-owned hook that executes an actor-writable doctool still breaks the trust root. The transitive chain must be fixed before making a broad `ENFORCED` claim.

## Skills: availability is not use

Recent telemetry found eight Tollens Skills installed and zero Tollens Skill invocations among 89 observed Skill invocations; a positive-control probe also recorded zero Skill calls for a task explicitly about dependency graphs/blast radius.

The response is not “force every Skill to run”. The target is to measure:

```text
TriggerRecall
TriggerPrecision
UtilityDelta
TokenDelta
LatencyDelta
```

Descriptions should only be changed against development + held-out prompt sets to avoid overfitting to the evaluation prompts.

## Completion criterion

This proposal becomes **IMPLEMENTED** only when:

- the manifest and installer model managed projections;
- `--dry-run`, deploy, verify and revert cover them;
- ownership/mode and the trust root are verifiable;
- P1–P5 pass;
- equivalent user-scope duplicates are removed verifiably;
- PT/EN docs and HANDOFF describe the same contract;
- external CI passes on the exact SHA.

Until then: **managed-native is a proposed design, not an delivered guarantee**.
