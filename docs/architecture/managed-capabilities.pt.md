# Capabilities managed-native no Claude Code

Estado: **PROPOSTA / NÃO IMPLEMENTADA**  
Data: 2026-08-25  
Relacionado: #32, G24, G25, G6b

## Problema

O Tollens já possui um plano managed para política técnica (`/etc/claude-code/managed-settings.json` e `/opt/tollens/{hooks,adapters,document-tools}`), mas `CLAUDE.md`, agents e Skills ainda são projetados principalmente para `~/.claude`. Isso mistura quatro propriedades diferentes:

1. **INSTALLED** — os bytes esperados existem;
2. **ENFORCED** — o ator governado não consegue substituir a versão efetiva;
3. **ACTIVATED** — o runtime realmente carregou/selecionou a capability;
4. **USEFUL** — a capability melhora um outcome independente pelo custo aceitável.

`install/verify.sh` prova principalmente (1). Não deve ser usado como evidência de (2)–(4).

## Decisão proposta

Usar as primitives managed nativas do Claude Code para a projeção organizacional, mantendo o repositório como fonte canônica:

```text
/etc/claude-code/CLAUDE.md
/etc/claude-code/.claude/agents/
/etc/claude-code/.claude/skills/
```

O escopo pessoal `~/.claude` continua disponível para preferências e capacidades não governadas. A migração **não** transforma todo `~/.claude` em root-owned.

## Invariantes

### M1 — uma fonte canônica

A origem continua em:

```text
execution/config/CLAUDE.md
execution/agents/*.md
execution/skills/*/
```

O instalador gera projeções. É proibido manter uma segunda cópia manual como fonte de verdade.

### M2 — deploy transacional

A projeção managed deve seguir o mesmo modelo do instalador privilegiado atual:

```text
source snapshot
  -> staging
  -> digest/schema/mode/owner checks
  -> publish
```

Falha observada antes do commit não pode deixar estado ativo parcialmente atualizado.

### M3 — sem duplicata ativa

Depois de demonstrada a precedência managed no binário suportado, a projeção user-scope equivalente deve ser removida. Duas cópias com o mesmo nome reabrem a pergunta “qual foi carregada?”.

### M4 — ativação é observada, não inferida

- CLAUDE.md: `InstructionsLoaded` com path/tipo esperados;
- agent: `SubagentStart`/transcript com `agent_type` esperado;
- Skill: evento/tool-use de Skill, ou preload explicitamente configurado no agent.

Ausência do observável é `NOT_VERIFIED`, não “provavelmente carregou”.

### M5 — utilidade não deriva da ativação

Uma capability pode ser ativada corretamente e piorar qualidade/custo. `ACTIVATED` não paga `E_U`.

## Manifesto alvo

O schema atual deve ser estendido para distinguir projeção de lifecycle. Exemplo conceitual:

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

`state`, `installed` e `projection` são dimensões distintas.

## Probes obrigatórios antes de merge

### P1 — managed CLAUDE

Com user CLAUDE conflitante e managed CLAUDE sentinela, o runtime deve registrar `InstructionsLoaded` para o managed esperado e o comportamento observado deve corresponder à precedência documentada.

### P2 — managed agent

Criar agent com mesmo `name` em user e managed, com marcadores distinguíveis. A invocação deve executar o managed. O probe deve observar `SubagentStart` e output discriminante.

### P3 — managed Skill

Criar Skill de fixture com mesmo nome em user e managed e outcome discriminante. Confirmar precedência. Separadamente, medir routing automático; existência e precedência não provam trigger.

### P4 — rollback

Após deploy managed, `--revert` deve restaurar exatamente o estado anterior e não apagar política preexistente de terceiro.

### P5 — mutação

Para cada propriedade acima, remover a garantia do código/config de fixture e exigir que o teste reprove. Controle inerte deve permanecer verde.

## Relação com G25

Esta migração **não fecha G25 por si só**. Um hook root-owned que executa doctool user-writable continua furando a trust root. A cadeia transitiva deve ser corrigida antes de usar “ENFORCED” como claim ampla.

## Skills: não confundir disponibilidade com uso

A telemetria recente mostrou oito Skills Tollens instaladas e zero invocações próprias entre 89 invocações de Skill observadas; um probe com controle positivo também registrou zero Skill calls para uma tarefa explicitamente relacionada a grafo/blast-radius.

A resposta não é “forçar todas a rodar”. O objetivo é medir:

```text
TriggerRecall
TriggerPrecision
UtilityDelta
TokenDelta
LatencyDelta
```

A descrição só deve ser alterada contra conjunto development + held-out, para evitar overfit ao prompt de teste.

## Critério de conclusão

Esta proposta só muda para **IMPLEMENTADA** quando:

- manifesto e instalador representam as projeções managed;
- `--dry-run`, deploy, verify e revert cobrem as novas projeções;
- ownership/mode e trust root são verificáveis;
- P1–P5 passam;
- duplicatas user-scope foram removidas de modo verificável;
- documentação PT/EN e HANDOFF refletem o mesmo contrato;
- CI externa passa no SHA exato.

Até lá: **managed-native = desenho proposto, não garantia entregue**.
