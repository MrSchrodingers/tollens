# Revisão de evidência — skills e agentes de software (2026)

## Pergunta

Quais propriedades de uma arquitetura de skills/subagentes são sustentadas por evidência recente, e quais continuam hipóteses?

## Evidência convergente

### 1. Skills não são universalmente benéficas

SWE-Skills-Bench (Han et al., arXiv:2603.15401) avalia 49 skills SWE em aproximadamente 565 instâncias, com repositórios reais fixados em commits, requisitos explícitos e verificadores determinísticos. O ganho médio reportado é pequeno (+1,2 pp); 39/49 skills não alteram pass rate e três apresentam regressão, atribuída em parte a incompatibilidade/versionamento e interferência contextual.

SkillsBench (Li et al., arXiv:2602.12670) também reporta forte heterogeneidade, inclusive deltas negativos, e encontra melhor resultado para skills focadas do que para documentação abrangente em parte do benchmark.

**Decisão:** default de skill = off; seleção por gatilho observável; uma skill por tarefa até existir evidência de composição; promoção somente após avaliação pareada.

### 2. Custo e correção são dimensões distintas

SWE-Skills-Bench mostra que overhead de tokens pode variar fortemente sem mudança de pass rate. Logo, “mais raciocínio” ou “mais contexto” não é proxy de correção.

**Decisão:** medir correção, tokens, latência, tool calls e execuções de teste separadamente. Não otimizar um escalar composto sem publicar os componentes.

### 3. Contexto relevante também pode causar dano

O estudo documenta surface anchoring, hallucination e concept bleed quando templates próximos, mas incompatíveis, competem com o contexto real da tarefa.

**Decisão:** skills devem declarar domínio e versões suportadas; avaliação inclui near-miss incompatível; regressão por interferência leva à quarentena/depreciação.

### 4. O scaffold é variável experimental

SWE-agent (Yang et al., NeurIPS 2024) demonstra que o desenho da interface agente–computador altera desempenho em SWE. O próprio SWE-Skills-Bench reconhece como limitação usar um único agente/modelo e propõe avaliação multi-modelo e multi-scaffold.

**Decisão:** separar `skill utility` de `scaffold utility`; todo resultado é estratificado por modelo e scaffold antes de qualquer agregação.

### 5. Evolução de skills deve ser evaluation-driven

Ding et al. (arXiv:2606.11435) organiza evolução de skills em paradigmas guiados por feedback, distilação, compressão e RL, e destaca lacunas de segurança, eficiência e generalização.

**Decisão:** nenhuma skill auto-gerada entra diretamente em produção; estado inicial é `quarantine`, e promoção exige evidência externa.

### 6. Proveniência e ciclo de vida são controles de segurança

Xu & Yan (arXiv:2602.12430) tratam skills como camada de capacidade com riscos próprios de proveniência, permissão e supply chain.

**Decisão:** lifecycle explícito (`quarantine`, `candidate`, `promoted`, `deprecated`, `rejected`), compatibilidade de versão e regressão de segurança como critérios de depreciação.

## O que a literatura não prova sobre este repositório

Nenhum desses trabalhos demonstra que o `tollens` melhora qualidade, segurança ou custo. Eles fundamentam decisões de desenho e desenho experimental. A eficácia deste harness continua uma hipótese até existir corpus próprio com baseline, trials repetidos, verificadores independentes e análise de incerteza.

## Critérios adotados para claims

- mecanismo observado != eficácia generalizável;
- uma execução != estimativa de probabilidade;
- um modelo != população de modelos;
- um scaffold != população de scaffolds;
- ausência de falha != evidência de completude;
- autoavaliação != certificação independente;
- teste estático != verificação comportamental quando comportamento é observável.

## Referências

- Tingxu Han et al. SWE-Skills-Bench: Do Agent Skills Actually Help in Real-World Software Engineering? arXiv:2603.15401, 2026.
- Xiangyi Li et al. SkillsBench: Benchmarking How Well Agent Skills Work Across Diverse Tasks. arXiv:2602.12670, 2026.
- John Yang et al. SWE-agent: Agent-Computer Interfaces Enable Automated Software Engineering. NeurIPS 2024.
- Kexin Ding et al. Agent Skill Evaluation and Evolution: Frameworks and Benchmarks. arXiv:2606.11435, 2026.
- Renjun Xu and Yang Yan. Agent Skills for Large Language Models: Architecture, Acquisition, Security, and the Path Forward. arXiv:2602.12430, 2026.
