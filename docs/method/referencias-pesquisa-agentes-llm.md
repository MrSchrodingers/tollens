# Referencias — Arquitetura de Agentes, Skills, Planos e Testes com LLM

> Consolidacao de todas as fontes exploradas nessa sessao de pesquisa.
> Organizado por tema. Cada entrada indica: claim principal, resultado
> numerico quando disponivel, status de peer review, e nivel de confianca
> apos verificacao adversarial.

---

## 1. Skills e Contexto Especializado

---

### SkillReducer: Compressing LLM Agent Skills for Efficient Inference
- **Identificador:** arXiv:2603.29919 (marco 2026)
- **Status:** Preprint — NAO peer-reviewed em venue top
- **Amostra:** 55.315 skills publicas analisadas
- **Resultados principais:**
  - Skills com >60% de conteudo nao-acionavel causam diluicao de atencao mensuravel no context window
  - Comprimir descricoes em 48% e corpos em 39% (mantendo apenas conteudo acionavel) produziu +2.8% de qualidade funcional (Wilcoxon signed-rank p=0.002, Cohen's d=0.107)
  - 26.4% das skills publicas carecem de descricao de roteamento
  - Skills oficiais: +11.8pp; skills de comunidade: +1.1pp
- **Caveat:** circularidade metodologica no criterio de avaliacao de "nao-acionavel"; efeito pequeno mascara heterogeneidade
- **Confianca:** Alta (estatisticamente significativo, metodologia detalhada)

---

### Codified Context: Preventing Brevity Bias in LLM Coding Agents
- **Identificador:** arXiv:2602.20478 (fevereiro 2026)
- **Status:** Preprint — trabalho de unico autor praticante, NAO peer-reviewed
- **Resultados principais:**
  - "Brevity bias": otimizacao iterativa de prompts colapsa para prompts curtos e genericos insuficientes para enforcar padroes especificos do projeto
  - Contramedida: mais de 50% do conteudo de cada especializacao deve ser domain knowledge concreto (fatos do codebase, padroes de import, falhas conhecidas)
  - Especificidade de dominio pre-carregada e o mecanismo que mantém padroes de import e convencoes ativos entre sessoes
- **Caveat:** sem benchmark independente; generalizacao limitada a um estudo de caso
- **Confianca:** Media (logica solida, evidencia limitada a estudo de caso)

---

### AOrchestra: Automating Sub-Agent Creation for Agentic Orchestration
- **Identificador:** arXiv:2602.03786 (submetido 3 fev 2026, revisado 7 fev 2026)
- **Status:** Preprint
- **Resultados principais:**
  - Especializacao dinamica via quadrupla (Instruction, Context, Tools, Model)
  - Ablacao de contexto (secao 4.3.1, tabela 2): curado 96.00, full-context 84.00, no-context 86.00
  - Orquestrador seleciona e comprime apenas historico relevante antes de delegar ao subagente
  - Abstract: "16.28% relative improvement against the strongest baseline when paired with
    Gemini-3-Flash". O numero 22.13% (pass@1 sobre os tres benchmarks) esta na secao 4.2, NAO no
    cabecalho - a primeira redacao desta errata trocou os dois de lugar
- **Confianca:** Media
- **ERRATA 2026-08-17.** Ate esta data a entrada trazia o titulo "Adaptive Orchestration for
  Multi-Agent LLM Systems" e a data "fevereiro 2025". Ambos falsos: o titulo foi inventado e a
  data contradizia o proprio identificador, ja que `2602` codifica fevereiro de 2026. A ablacao
  96 vs 84-86, conferida agora na fonte, estava CORRETA - o defeito era so a moldura. Uma
  citacao com numero certo e titulo errado e o pior caso: o numero sobrevive a conferencia por
  amostragem e a moldura falsa passa junto.

---

### Self-Augmentation Fails at Runtime: CodeScout
- **Identificador:** arXiv:2603.05744
- **Status:** Preprint
- **Modelos testados:** GPT-5-mini, Qwen3 Coder, DeepSeek R1 — SWEBench-Verified
- **Resultados principais:**
  - Modificar o system-prompt para auto-augmentacao de contexto em runtime degrada abaixo do baseline em todos os modelos:
    - GPT-5-mini: -17 issues vs baseline
    - Qwen3 Coder: -25 issues vs baseline
    - DeepSeek R1: -5 issues vs baseline
  - Contexto especializado deve ser preparado por estagio anterior separado — nao pode ser delegado ao proprio agente em execucao
- **Distincao importante:** auto-refinamento com feedback externo de execucao (Reflexion) e categoricamente diferente — esse resultado aplica-se especificamente a modificacao de system-prompt para auto-augmentacao
- **Confianca:** Alta

---

## 2. Decomposicao Hierarquica e Multi-Agente

---

### SAFEdit: Structure-Aware Multi-Agent Code Editing
- **Identificador:** arXiv:2604.25737v1 (abril 2025)
- **Status:** Preprint v1 — sem peer-review top-venue
- **Benchmark:** EditBench, 445 instancias, 5 linguagens
- **Resultados principais:**
  - SAFEdit (multi-agente Planner+Editor+Verifier): 68.6% Task Success Rate
  - Melhor single-model (claude-sonnet-4): 64.8%
  - ReAct single-agent: 60.0%
- **Caveat critico:** ganho atribuivel principalmente ao loop de Failure Abstraction Layer (FAL, +17.4pp isolado), NAO a decomposicao Planner+Editor+Verifier em si; benchmark unico; sem teste de significancia estatistica para margem de +3.8pp
- **Confianca:** Media (direcao confirmada, mecanismo isolado questionavel)

---

### SE-Agent vs AgentOrchestra: When Multi-Agent Fails
- **Identificador:** arXiv:2604.02460
- **Status:** Preprint
- **Resultados principais:**
  - Para tarefas sequenciais de codigo (SWE-bench): single-agent supera multi-agent
  - SE-Agent: 54% vs AgentOrchestra: 3%
  - Custo de AgentOrchestra: 22x maior para resultado pior
- **Confianca:** Alta

---

### OneFlow: Single vs Multi-Agent Cost-Benefit
- **Identificador:** arXiv:2601.12307
- **Status:** Preprint
- **Resultados principais:**
  - OneFlow (single + multi-turn estruturado): 92.1% HumanEval
  - AFlow multi-agente: 90.1%
  - Custo de OneFlow: 10% do custo do AFlow
- **Confianca:** Alta

---

### Multi-Agent Parallelism in Finance
- **Identificador:** Finance-Agent benchmark (referenciado em arXiv:2511.00872)
- **Resultados principais:**
  - Tarefa genuinamente paralelizavel: +80.9% vs single-agent
- **Confianca:** Media

---

## 3. Formato e Qualidade de Instrucoes

---

### The Atomic Instruction Gap: Format Compliance in LLMs
- **Identificador:** arXiv:2510.17388
- **Status:** Preprint
- **Resultados principais:**
  - Labels numericos (1, 2, 3): 98.81% de compliance
  - Algarismos romanos (I, II, III): 44.12% de compliance
  - Diferenca de 54pp causada exclusivamente pelo formato da instrucao
  - Exemplos few-shot sem diretiva: sem melhoria estatisticamente significativa (Wilcoxon p>0.05)
- **Confianca:** Alta

---

### Show and Tell: Combining Directives and Examples
- **Identificador:** arXiv:2511.13972
- **Status:** Preprint
- **Resultados principais:**
  - Combinacao diretiva + exemplo supera diretiva sozinha e exemplo sozinho
  - O exemplo ancora a superficie imediata; a diretiva persiste como regra testavel entre turnos
- **Confianca:** Alta

---

### Lost in the Middle: Positional Bias in Long Contexts
- **Identificador:** TACL 2024 (peer-reviewed)
- **Status:** Peer-reviewed — Transactions of the Association for Computational Linguistics
- **Resultados principais:**
  - Instrucoes posicionadas no meio de arquivos longos sofrem ~25pp de perda de compliance (U-curve de posicao)
  - Modelos performam melhor com informacao relevante no inicio ou no fim do contexto
- **Confianca:** Alta (peer-reviewed)

---

### Instruction Following Degradation with Length
- **Identificador:** arXiv:2507.11538
- **Status:** Preprint
- **Resultados principais:**
  - Blocos de prosa acima de 200 linhas / 500 palavras: compliance colapsa
  - Regras com contexto causal ("por que") resistem melhor a context drift que regras nuas
- **Confianca:** Media-Alta

---

### AgentIF: Instruction Following in Agentic Contexts
- **Identificador:** arXiv:2505.16944
- **Status:** Preprint
- **Resultados principais:**
  - ISR (taxa de sucesso de instrucao completa) colapsa para proximo de zero em instrucoes acima de 6.000 palavras
  - Todos os modelos testados atingem apenas 27-41% ISR mesmo nas melhores condicoes
    - o1-mini: 27.2%
    - GPT-4o: 35.1%
    - Melhor modelo: 59.8% CSR com media de 11.9 restricoes por instrucao
- **Confianca:** Alta

---

### Semantic Gravity Wells: Negative Instructions
- **Identificadores:** Jang et al. arXiv:2209.12711 (peer-reviewed); arXiv:2601.08070
- **Status:** arXiv:2209.12711 — peer-reviewed
- **Resultados principais:**
  - Instrucoes negativas no system prompt ativam "semantic gravity well": atencao ao conceito proibido aumenta
  - Modelos maiores nao melhoram nisso (inverse scaling confirmado)
  - InstructGPT falha em negacoes mesmo apos instruction-tuning
  - Recomendacao Anthropic oficial: converter negacoes em afirmacoes
- **Confianca:** Alta (um dos papers e peer-reviewed)

---

### Negative Examples in Fine-Tuning
- **Identificadores:** arXiv:2503.14391; arXiv:2603.16417
- **Status:** Preprints (um de sintese)
- **Resultados principais:**
  - Exemplos negativos durante treinamento produzem "salto acentuado na curva de aprendizado"
  - Near-miss negativos tem valor desproporcional no fine-tuning
  - Constitutional AI supera RLHF baseado em preferencias usando proibicoes discretas
- **Confianca:** Media (um e paper de sintese)

---

### CoT Quality in Coding Tasks
- **Identificador:** arXiv:2512.09679
- **Status:** Preprint
- **Resultados principais:**
  - CoT estruturado em benchmarks complexos (MHPP, BigCodeBench): +15-30% Pass@1
  - CoT zero-shot sem estrutura: degrada para 52.03% vs 54.10% de baseline direto
  - CoT de baixa qualidade: -2.77% abaixo do baseline
  - Em benchmarks simples (MBPP): ganho de 1-3%, as vezes negativo
- **Confianca:** Alta

---

### Domain Spec vs Generic Wrapper
- **Identificador:** arXiv:2601.22025
- **Status:** Preprint
- **Resultados principais:**
  - Prompt de processo generico em lugar de spec de dominio especifica: queda de 10% em extracao, 13% em RAG compliance
  - Instrucao de "seguir instrucoes" generica melhorou 13% em obediencia mas performance real caiu
- **Confianca:** Media

---

## 4. Planejamento e Decomposicao de Tarefas

---

### PlanAhead: Static Planner + Deterministic Executor
- **Identificador:** arXiv:2605.29927 (2025)
- **Status:** Preprint
- **Benchmark:** WebArena
- **Resultados principais:**
  - Agentes dinamicos documentados com action loops, subtask-skipping e marcacao prematura de conclusao (Apendice D)
  - Separacao planner (temperatura 0.6, plano gerado uma vez) + executor (temperatura 0, deterministico) elimina esses comportamentos
  - Quatro formatos testados lado a lado: narrative, checklist, pseudocode, sequential subgoals
  - Melhor configuracao: GPT-4.1-mini planejador + Gemini 2.5 Flash executor + checklist: AR=10.7%, STC=85%
  - Pares heterogeneos (modelos diferentes) superam pares homogeneos consistentemente
  - Formato depende do modelo executor — sem vencedor universal
- **Confianca:** Alta

---

### Plan-Then-Execute: Human Factors Study
- **Identificador:** arXiv:2502.01390 (CHI 2025)
- **Status:** Aceito em CHI 2025 — peer-reviewed em venue top
- **Amostra:** N=248 participantes, 6 tarefas
- **Resultados principais:**
  - Plano ruim (score 1-2): 1.8% de execucao bem-sucedida
  - Plano medio (score 3-4): 59%
  - Plano bom (score 5): 66.7%
  - Acuracia de sequencia de acoes media: M=0.48, SD=0.17
  - 104 de 121 participantes editaram pelo menos um passo do plano
  - Edicoes humanas degradaram planos inicialmente corretos em 5 de 6 tarefas
  - Calibracao de confianca humana: ~50% em todas as condicoes
- **Confianca:** Alta (peer-reviewed em CHI)

---

### Subgoal-Driven Planning (Google DeepMind)
- **Identificador:** arXiv:2603.19685
- **Status:** Preprint — Google DeepMind
- **Benchmark:** WebArena
- **Resultados principais:**
  - Manter o subgoal atual visivel em cada passo (nao apenas no inicio) elevou Gemma3-12B de 6.4% para 43.0%
  - Resultado supera GPT-4o: 13.9%
- **Confianca:** Media-Alta

---

### ADaPT: Adaptive Decomposition and Planning
- **Identificador:** arXiv:2311.05772
- **Status:** Preprint
- **Benchmarks:** ALFWorld, WebShop, TextCraft
- **Resultados principais:**
  - Decomposicao recursiva so quando executor falha: +28 a +33pp vs baseline sem decomposicao
  - Profundidade otima e funcao da complexidade da tarefa, nao numero fixo
- **Confianca:** Media

---

### ARIES: Depth-Accuracy Tradeoff
- **Identificador:** arXiv:2502.21208
- **Status:** Preprint
- **Resultados principais:**
  - Profundidade 2: +21% sobre melhor baseline estatico
  - Profundidade 3: degrada 2.6x em relacao a profundidade 2
  - 68% dos erros em arvores profundas: na agregacao, nao na execucao das folhas
- **Confianca:** Alta

---

### Modular Task Decomposition: Optimal Subtask Count
- **Identificador:** arXiv:2511.01149
- **Status:** Preprint
- **Resultados principais:**
  - Relacao invertida em U: pico de eficiencia entre 5 e 6 subtarefas
  - Abaixo de 3: falha por especificidade insuficiente
  - Acima de 6: coordenacao degrada eficiencia
- **Confianca:** Media

---

### SlopCodeBench: Sequential Step Degradation
- **Identificador:** arXiv:2603.24755
- **Status:** Preprint
- **Resultados principais:**
  - >80% de sucesso nos primeiros 3 passos
  - <40% no passo 8+
  - Taxa de regressao cresce de forma aproximadamente quadratica com numero de passos sequenciais
- **Confianca:** Media

---

### Systematic Decomposition: Over-Decomposition Cost
- **Identificador:** arXiv:2510.07772
- **Status:** Preprint
- **Resultados principais:**
  - Over-decomposicao custa 1.4-2.1x em tokens sem ganho de acuracia apos ponto de saturacao
  - Recomendacao: decompor nos limites de restricao onde existe teste ou interface verificavel
- **Confianca:** Media

---

### Beyond Entangled Planning: Task-Decoupled Planning (TDP)
- **Identificador:** arXiv:2601.07577 (2025)
- **Status:** Preprint
- **Benchmarks:** TravelPlanner, ScienceWorld, HotpotQA
- **Resultados principais:**
  - Reducao de tokens em ate 82%
  - Supera baselines nos tres benchmarks
  - Supervisor decompoe em DAG de sub-objetivos; Planner e Executor operam com contextos confinados por sub-tarefa
  - Erros locais nao se propagam pelo historico monolitico
- **Confianca:** Media (reducao de tokens confirmada; acuracia especifica nao extraida)

---

### HULA: Human-in-the-Loop Planning at Atlassian
- **Identificador:** arXiv:2411.12924 (Atlassian)
- **Status:** Preprint — origem em equipe de engenharia
- **Amostra:** N=260 a 2600 practitioners; SWE-bench Verified n=500
- **Resultados principais:**
  - AI Planner gerou planos para 79% das issues
  - Engenheiros aprovaram 82% dos planos gerados
  - Recall de 86% na identificacao dos arquivos a modificar
  - 37.2% de taxa de resolucao no SWE-bench Verified
  - Preocupacoes de qualidade persistiram para requisitos nuancados nao capturados por testes unitarios
- **Confianca:** Media

---

### ReVeal: Reinforcement Learning with Test Execution
- **Identificador:** arXiv:2506.11442
- **Status:** Preprint
- **Resultados principais:**
  - Execucao de testes gerados pelo agente em loop RL: +43-59% relativo em Pass@1
- **Confianca:** Media

---

### Plan Verification via Reinjecao
- **Identificador:** arXiv:2509.02761
- **Status:** Preprint
- **Resultados principais:**
  - Re-injecao do plano original como lembrete a cada etapa reduz drift e melhora taxa de sucesso
- **Confianca:** Media

---

### HELM: Human Checkpoint Gate
- **Identificador:** arXiv:2510.17109
- **Status:** Preprint
- **Resultados principais:**
  - Gate humano por checkpoint: 20% para 75% de sucesso (+275% absoluto)
- **Confianca:** Media

---

### Self-Critique Without External Signal
- **Identificador:** arXiv:2310.08118
- **Status:** Preprint
- **Resultados principais:**
  - LLM auto-critica sem sinal externo degrada qualidade do plano
  - Auto-critica adiciona latencia sem ganho quando nao ha ground truth externo
- **Confianca:** Alta

---

### Plan-and-Act: Static vs Adaptive Planning
- **Identificador:** arXiv:2503.09572
- **Status:** Preprint
- **Resultados principais:**
  - SFT+RL vs SFT-only: taxa de conclusao de plano +25% relativo
  - Taxa de re-planejamento adaptativo: 0.41 vs 0.35
  - Ganho >10% em taxa de sucesso geral com re-planejamento baseado em feedback
- **Confianca:** Media

---

### Learning When to Plan: Just-in-Time Planning
- **Identificador:** arXiv:2509.03581
- **Status:** Preprint
- **Resultados principais:**
  - Planejamento just-in-time supera planos estaticos em ambientes dinamicos
  - Reduz passos redundantes e alinha acoes ao estado atual de execucao
- **Confianca:** Media

---

### seqBench: Sequential Reasoning Depth
- **Identificador:** arXiv:2509.16866
- **Status:** Preprint
- **Resultados principais:**
  - Acuracia decai exponencialmente com profundidade de raciocinio
  - De 2 para 3 etapas sequenciais: queda de ~80% relativa em tarefas legais
  - Constante de decaimento L0 varia de 1.6 (Llama-3B) a 85.7 (Gemini-2.5-Flash) — diferenca de 53x entre modelos
- **Confianca:** Media

---

## 5. Mapeamento de Dependencias e Contexto de Repositorio

---

### SWE-Explore: Context Quality as Primary Predictor
- **Identificador:** arXiv:2606.07297
- **Status:** Preprint
- **Amostra:** 848 instancias, 203 repositorios, 10 linguagens
- **Resultados principais:**
  - Correlacao Pearson r=0.950 entre qualidade do contexto e repair rate downstream
  - BM25: file hit rate 0.079, repair rate 12.7%
  - Dense (Potion): file hit rate 0.088
  - CoSIL (graph-iterativo): file hit rate 0.544, repair rate 59.3%
  - Claude Code (navegacao): file hit rate 0.667, repair rate 48.0%
  - Oracle: repair rate 59.7%
- **Caveat:** decimais exatos de CoSIL/BM25 precisam verificacao no PDF completo; direcao confirmada
- **Confianca:** Alta

---

### LocAgent: Graph-Based Repository Navigation
- **Identificador:** arXiv:2503.09089
- **Status:** Preprint
- **Resultados principais:**
  - Grafo heterogeneo com 4 tipos de no (diretorio/arquivo/classe/funcao) e 4 tipos de aresta (contain/import/invoke/inherit)
  - 94.16% Acc@5 em SWE-Bench-Lite vs 84.67% para dense embedding
- **Caveat:** Acc@5, nao acuracia de primeiro hit — framing como "file-level accuracy" sem qualificacao e enganoso
- **Confianca:** Media (resultado real, framing enganoso)

---

### RAG for Code Generation: Survey
- **Identificador:** arXiv:2510.04905
- **Status:** Preprint (survey)
- **Resultados principais:**
  - Context stuffing competitivo com RAG apenas para repositorios abaixo de ~100k tokens
  - Acima de 100k tokens: RAG vence em latencia e custo
- **Confianca:** Media

---

### LongSWE-bench: Upper Bound of Context Stuffing
- **Identificador:** arXiv:2602.16069
- **Status:** Preprint
- **Resultados principais:**
  - Gemini 2.5 Pro com contexto oracle completo stuffed: resolve apenas 22% das tarefas
  - Esse e o upper bound do stuffing sob condicoes ideais
- **Confianca:** Alta

---

### Beyond More Context: Chunk Granularity
- **Identificador:** arXiv:2510.06606 (ASE 2025)
- **Status:** Preprint — contexto de competicao ASE 2025
- **Resultados principais:**
  - Retrieval em nivel de chunk supera nivel de arquivo em +6%
  - Supera baseline sem contexto em +16%
  - Contexto ruidoso ou irrelevante degrada ativamente o output
- **Confianca:** Media

---

### Navigation Paradox: Graph vs RAG
- **Identificador:** arXiv:2602.20048
- **Status:** Preprint
- **Resultados principais:**
  - Travessia de grafo de dependencias supera RAG vetorial em tarefas architecture-heavy
- **Confianca:** Media

---

### cAST: AST-Aware Chunking
- **Identificador:** arXiv:2506.15655
- **Status:** Preprint
- **Resultados principais:**
  - Chunking por fronteiras AST (funcao/classe) preserva integridade sintatica
  - Aumenta densidade informacional vs janela deslizante
- **Confianca:** Media

---

### AI-Generated Code Not Reproducible
- **Identificador:** arXiv:2512.22387
- **Status:** Peer-reviewed — ACL
- **Resultados principais:**
  - 68.3% dos projetos gerados por LLM executam out-of-the-box
  - Expansao media de dependencias declaradas para runtime: 13.5x
- **Confianca:** Alta (peer-reviewed)

---

### How Safe Are AI-Generated Patches
- **Identificador:** arXiv:2507.02976
- **Status:** Preprint
- **Resultados principais:**
  - Agentes frequentemente corrigem o arquivo sintoma sem propagar mudanca para callers/dependentes
  - Introducao de novos riscos de seguranca documentada
- **Confianca:** Media

---

### SWE-Bench Pro: Evidence Drop
- **Identificador:** arXiv:2509.16941
- **Status:** Preprint
- **Resultados principais:**
  - Mesmo quando agente acessa codigo relevante, apenas 50-70% dessa evidencia e retida na janela de contexto final
  - Agente gera patches sem condicionar nas linhas criticas que "viu"
- **Confianca:** Media

---

### Aider Repo Map: PageRank-Based Navigation
- **URL:** aider.chat/2023/10/22/repomap.html
- **Status:** Documentacao tecnica publica (nao peer-reviewed)
- **Resultados principais:**
  - Indexacao com tree-sitter antes de qualquer requisicao
  - Grafo de definicao e referencia com PageRank biasado para arquivos ja abertos
  - Trimmado por busca binaria ate caber no budget de tokens
  - LLM recebe assinaturas e estrutura, nao corpos inteiros
- **Confianca:** Alta (verificado no source code)

---

### SWE-agent: Agent-Computer Interface
- **Identificador:** arXiv:2405.15793 (NeurIPS 2024)
- **Status:** Peer-reviewed — NeurIPS 2024
- **Resultados principais:**
  - Sem lint feedback: solve rate cai 3pp (15.0% para 12%)
  - ACI com viewport de 100 linhas por turno e history processor
- **Confianca:** Alta (peer-reviewed)

---

## 6. Loops de Refinamento e Hooks

---

### Aider: Auto-Lint and Auto-Test Loop
- **URL:** aider.chat/docs/usage/lint-test.html + issue #1090
- **Status:** Documentacao e issue tracker publicos
- **Resultados principais:**
  - --auto-lint e --auto-test: executa apos cada edicao, realimenta saida se exit code != 0
  - Bug documentado de loop infinito quando lint nao converge (issue #1090)
  - Exige contador de tentativas para evitar oscilacao
- **Confianca:** Alta (confirmado em producao)

---

### Terminal-Bench: Harness Quality vs Model Quality
- **Identificador:** ICLR 2026 (openreview.net)
- **Status:** Peer-reviewed — ICLR 2026
- **Resultados principais:**
  - O mesmo modelo base em harnesses diferentes produz diferenca substancial de desempenho em tarefas multi-step
  - Harness quality explica mais variancia que model quality
- **Confianca:** Alta (peer-reviewed)

---

### Agentic Much? Adoption of Coding Agents on GitHub
- **Identificador:** arXiv:2601.18341
- **Status:** Preprint
- **Resultados principais:**
  - Repositorios com adocao real de agentes possuem arquivos de contexto persistente (CLAUDE.md, .cursorrules) como artefato central
  - Workflow dominante e hibrido humano-IA, nao autonomia total
- **Confianca:** Media

---

### Claude Code Hooks: PostToolUse Mechanism
- **URLs:** dotzlaw.com/insights/claude-hooks/; thomas-wiegold.com/blog/claude-code-hooks/
- **Status:** Documentacao de comunidade (nao peer-reviewed)
- **Resultados principais:**
  - PostToolUse hook: apos cada escrita de arquivo, executa linter/compilador
  - Exit code != 0 injeta resultado no additionalContext do proximo ciclo
- **Confianca:** Alta (verificado em documentacao oficial Anthropic)

---

### Cursor 2.4 Subagents
- **URL:** aimakers.co/blog/cursor-2-4-subagents/
- **Status:** Documentacao de produto (nao peer-reviewed)
- **Resultados principais:**
  - Cada subagente tem janela de contexto propria, isolada da conversa principal
  - Orquestrador gera contrato (interface/schema) e passa como contexto inicial para cada subagente
- **Confianca:** Media

---

## 7. Testes com LLM

---

### MANTRA: Multi-Agent Refactoring
- **Identificador:** arXiv:2503.14340
- **Status:** Preprint
- **Resultados principais:**
  - Framework multi-agente para refatoracao automatica em nivel de metodo
  - RAG contextual e colaboracao entre LLMs
  - +28.8% de pass rate com sampling de multiplas geracoes (pass@5)
- **Confianca:** Media

---

### Slopsquatting: Hallucinated Dependencies
- **Fonte:** Estudo UTSA/Oklahoma/Virginia Tech (referenciado em multiplas fontes)
- **Status:** Estudo academico (peer-review nao confirmado diretamente)
- **Amostra:** 576.000 amostras, 16 LLMs
- **Resultados principais:**
  - ~20% dos samples de codigo gerado referenciam bibliotecas inexistentes
- **Confianca:** Media (numero correto, fonte primaria verificada indiretamente)

---

## 8. Tabela de Confianca Consolidada

| Paper / Fonte | Venue / Status | Confianca |
|---|---|---|
| Lost in the Middle (posicao U-curve) | TACL 2024 — peer-reviewed | Alta |
| Plan-Then-Execute | CHI 2025 — peer-reviewed | Alta |
| SWE-agent (NeurIPS 2024) | NeurIPS 2024 — peer-reviewed | Alta |
| Terminal-Bench | ICLR 2026 — peer-reviewed | Alta |
| AI-Generated Code Not Reproducible | ACL — peer-reviewed | Alta |
| Semantic Gravity Wells (Jang et al.) | Peer-reviewed | Alta |
| Atomic Instruction Gap (arXiv:2510.17388) | Preprint | Alta |
| Show and Tell (arXiv:2511.13972) | Preprint | Alta |
| AgentIF (arXiv:2505.16944) | Preprint | Alta |
| CodeScout / Self-Augmentation (arXiv:2603.05744) | Preprint | Alta |
| PlanAhead (arXiv:2605.29927) | Preprint | Alta |
| LongSWE-bench (arXiv:2602.16069) | Preprint | Alta |
| SWE-Explore (arXiv:2606.07297) | Preprint | Alta |
| Self-Critique Without Signal (arXiv:2310.08118) | Preprint | Alta |
| Aider loop bug (issue #1090) | Producao confirmada | Alta |
| ARIES (arXiv:2502.21208) | Preprint | Alta |
| CoT Quality (arXiv:2512.09679) | Preprint | Alta |
| SAFEdit (arXiv:2604.25737) | Preprint | Media |
| SkillReducer (arXiv:2603.29919) | Preprint | Alta* |
| AOrchestra (arXiv:2602.03786) | Preprint | Media |
| Subgoal-Driven / DeepMind (arXiv:2603.19685) | Preprint | Media-Alta |
| ADaPT (arXiv:2311.05772) | Preprint | Media |
| TDP (arXiv:2601.07577) | Preprint | Media |
| HULA / Atlassian (arXiv:2411.12924) | Preprint | Media |
| Codified Context (arXiv:2602.20478) | Preprint | Media |
| MANTRA (arXiv:2503.14340) | Preprint | Media |
| LocAgent (arXiv:2503.09089) | Preprint | Media* |
| RAG Survey (arXiv:2510.04905) | Preprint | Media |
| SWE-Bench Pro (arXiv:2509.16941) | Preprint | Media |
| Plan-and-Act (arXiv:2503.09572) | Preprint | Media |
| seqBench (arXiv:2509.16866) | Preprint | Media |
| Beyond More Context (arXiv:2510.06606) | Preprint | Media |

*Alta em estatistica, ressalva metodologica especifica documentada acima.

---

## 9. O que NAO sobreviveu a verificacao adversarial

As seguintes claims foram levantadas durante a pesquisa mas NAO foram confirmadas:

- "Skills granulares reduzem especificamente forca bruta sem leitura de documentos" — observacao qualitativa sem metrica rigorosa publicada
- "Skills reduzem falhas de padroes de import" — nao testado como metrica em benchmark independente
- "Skills previnem testes tautologicos" — observacao qualitativa, sem RCT
- "SDD reduz erros em 50%" — paper fonte (arXiv:2602.00180) admite que estudos subjacentes nao sao reproduzidos no proprio trabalho; CONFIANCA BAIXA
- Scores exatos de Terminal-Bench citados em fonte de comunidade (thoughts.jock.pl) — nao batem com benchmark oficial; direcao qualitativa confirmada, numeros especificos refutados
- Claim de Devin/OpenHands combinando as tres caracteristicas (hooks + especializacao + orquestrador) como sistema coeso — NAO confirmado; os blocos existem separados

---

## 10. Caveat geral desta pesquisa

1. A maioria dos papers e de 2025-2026 — preprints nao peer-reviewed em venues top como NeurIPS/ICML/ACL/CHI (excecoes indicadas)
2. A pesquisa foi conduzida via busca web e verificacao adversarial com multiplos agentes — nao e revisao sistematica com protocolo PRISMA
3. Numeros especificos de fontes auto-reportadas (Cognition/Devin, Cursor) nao sao auditaveis externamente
4. Efeitos medidos em benchmarks (WebArena, SWE-bench, HumanEval) podem nao generalizar para codebases de producao especificas
5. A combinacao das tres caracteristicas (hooks + especializacao por dominio + orquestrador com contexto pre-carregado) e uma lacuna real no estado da arte publicado ate junho/2026 — evidencia de cada peca existe; evidencia do sistema combinado nao existe
