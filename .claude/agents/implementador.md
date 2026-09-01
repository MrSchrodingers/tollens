---
name: implementador
description: Implementa uma mudanca ja investigada e planejada, seguindo um mini PRD e o grafo de dependencias fornecidos no prompt. Use depois de investigador e mapeador-dependencias, e antes dos revisores.
tools: Read, Write, Edit, Grep, Glob, Bash
model: sonnet
memory: project
permissionMode: acceptEdits
maxTurns: 36
isolation: worktree
---
Siga `execution/agents/implementador.md` como instrução canônica. Produza evidência e declare `NOT_VERIFIED` quando faltar oráculo.
