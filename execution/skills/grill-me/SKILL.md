---
name: grill-me
description: Entrevista o usuario implacavelmente sobre um plano ou design ate atingir entendimento compartilhado, resolvendo cada galho da arvore de decisao. Usar quando o usuario quiser stress-testar um plano, ser questionado sobre seu design, ou mencionar "grill me" ou "me questiona". Pode ser invocada como sub-etapa de qualquer outra skill.
---

# Entrevista Implacavel

Entreviste o usuario implacavelmente sobre CADA aspecto do plano ate atingir entendimento compartilhado. Percorra cada galho da arvore de decisao, resolvendo dependencias entre decisoes uma a uma.

## Pipeline (Skills Relacionadas)

Esta skill pode ser invocada como sub-etapa de qualquer outra skill:

```
/write-a-prd ──────→ usa /grill-me na etapa de entrevista
um plano de refatoracao dedicado → usa /grill-me na etapa de entrevista
/prd-to-plan ──────→ usa /grill-me para validar fases
```

No contexto do projeto DEBTHUB, esta skill cumpre o papel que la se chama entrevistador (nome de outro projeto, nao comando local).

---

## Regras

### 1. Explore antes de perguntar

Se uma pergunta pode ser respondida explorando o codebase, explore o codebase ANTES de perguntar ao usuario. Use o Agent tool com subagent_type=Explore.

Exemplos:
- "Quantos callers tem essa funcao?" → Explore, nao pergunte
- "Esse modulo tem testes?" → Explore, nao pergunte
- "Qual o padrao usado no modulo adjacente?" → Explore, nao pergunte
- "Voce quer usar feature flags?" → Pergunte (decisao de negocio)

### 2. Uma ramificacao por vez

NAO faca 5 perguntas de uma vez. Faca UMA pergunta, espere a resposta, e use a resposta para decidir a proxima pergunta. Cada resposta pode mudar a direcao da entrevista.

### 3. Categorias de perguntas

Percorra sistematicamente estas categorias (nao necessariamente nesta ordem — siga o fluxo natural):

**Funcionalidade:**
- O que acontece no happy path?
- Quais sao os fluxos alternativos?
- Quais sao os edge cases?

**Falha e Resiliencia:**
- O que acontece quando X falha?
- Qual o comportamento aceitavel durante degradacao?
- Precisa de retry? Circuit breaker? DLQ?
- Qual o plano de rollback?

**Concorrencia:**
- O que acontece se dois requests chegam ao mesmo tempo?
- Ha race conditions possiveis?
- Precisa de locks? Idempotencia?

**Integracao:**
- Quem produz os dados de entrada?
- Quem consome os dados de saida?
- Quais contratos de API existem?
- Quais fronteiras de servico sao cruzadas?

**Dados:**
- Qual o volume esperado?
- Precisa de migracao?
- Qual a estrategia de backup/restore?
- Retencao de dados?

**Observabilidade:**
- Como saber se esta funcionando?
- Quais metricas importam?
- Quais alertas configurar?
- Qual o SLA esperado?

**Seguranca:**
- Quem pode acessar?
- Precisa de autorizacao granular?
- Dados sensiveis envolvidos?
- Auditoria necessaria?

**Performance:**
- Qual a latencia aceitavel?
- Qual o throughput esperado?
- Precisa de cache?
- Precisa de paginacao?

### 4. Quando parar

Pare quando TODAS estas condicoes forem verdadeiras:
- [ ] Todas as ramificacoes da arvore de decisao foram resolvidas
- [ ] Nao ha ambiguidades restantes
- [ ] O usuario confirma que o entendimento esta completo
- [ ] Voce consegue resumir o plano em 3-5 frases sem perder informacao critica

### 5. Encerramento

Ao final, apresente um resumo estruturado das decisoes tomadas:

```
## Resumo das Decisoes

1. **[Topico]**: [Decisao] — Motivo: [justificativa]
2. **[Topico]**: [Decisao] — Motivo: [justificativa]
...

## Pontos em Aberto
- [Se algum ficou para resolver depois]

## Proximos Passos Sugeridos
- [Qual skill invocar em seguida]
```
