# ADR 0007 - Topologia de execucao do pipeline e contrato de delegacao

- Data: 2026-06-23
- Status: Aceito
- Escopo: configuracao global de usuario (~/.claude/)
- Relaciona-se com: 0002 (reforma/pipeline), secoes 0, 6, 7, 9, 10, 13 do CLAUDE.md

## Contexto

Pedido do usuario: estudar e otimizar o alinhamento entre o orquestrador (sessao principal)
e os subagentes no "modo otimo" - como a execucao e conduzida quando repassada a agentes e a
background. A investigacao apurou tres fatos sobre o que de fato se propaga a um subagente, dois
deles VERIFICADOS EMPIRICAMENTE (nao por doc, que se mostrou falivel - ver abaixo).

## Fatos apurados (evidencia, nao suposicao)

1. **Subagentes custom HERDAM o contexto global automaticamente.** Teste empirico: um agente
   `general-purpose` (que nao e Explore/Plan) citou VERBATIM a primeira linha de `~/.claude/CLAUDE.md`,
   o nome da persona e a clausula anti-bajulacao, com ZERO leituras de arquivo (tool_uses=0),
   declarando que o conteudo chegou "via system-reminder". Logo: `~/.claude/CLAUDE.md` de usuario,
   `./CLAUDE.md` de projeto, `MEMORY.md` e git status sao injetados em todo agente custom sem
   configuracao. SO os agentes nativos Explore/Plan omitem ambos. Isto CORRIGE uma afirmacao
   anterior, exagerada, de que "subagentes nao recebem o CLAUDE.md" - vale apenas para Explore/Plan.

2. **`memory: user` e feature real e ativa, nao no-op.** O campo `memory:` aceita o enum
   `user`/`project`/`local`, habilitando memoria persistente do subagente em
   `~/.claude/agent-memory/<nome>/` (Read/Write/Edit auto-habilitados; o `MEMORY.md` do agente
   pre-carregado no system prompt). Teste empirico: o diretorio existe com 10 subpastas que batem
   exatamente com os 10 agentes que declaram `memory: user`, contendo memoria institucional
   acumulada real (o `investigador` tem 17 arquivos de conhecimento dos projetos do usuario). Os 3
   agentes sem o campo (implementador, tdd, continuidade) nao tem pasta. Decisao: MANTER nos 10.

   > **ERRATA, 2026-08-12 (onda 10).** A observacao acima permanece: ela esta CORRETA, e agora
   > confirmada na fonte primaria que este ADR nao tinha. Verbatim de
   > `https://code.claude.com/docs/en/sub-agents.md`, secao "Enable persistent memory":
   > "Read, Write, and Edit tools are automatically enabled so the subagent can manage its
   > memory files."
   >
   > O que muda e a DECISAO. "MANTER nos 10" foi revertida para os OITO agentes que
   > `orchestration/registry.json` declara com `writes: false`. A razao nao e evidencia nova
   > sobre memoria: e uma consequencia que este ADR registrou sem tirar. Se o campo
   > auto-habilita Write e Edit, entao todo agente que o declara TEM Write e Edit - e oito deles
   > se apresentam ao leitor como "Read-only, nunca corrige". A garantia estava no texto e
   > ausente no mecanismo, que e a forma que o ADR 0029 documenta nove vezes. `tdd` e
   > `implementador` mantem o campo: declaram `writes: true`, e para eles nao ha contradicao.
   >
   > Medido: `evidence/runtime-probes/declared-capabilities.py --repo-only` saia 1 com 16
   > violacoes (os oito, em arvore canonica e projecao) e agora sai 0; reintroduzir `memory: user`
   > em um unico agente devolve exit 1 nomeando-o.
   >
   > CUSTO ACEITO, e ele e real: os oito perdem a memoria acumulada. O caso material e o
   > `investigador`, com 17 arquivos segundo este mesmo ADR. Os diretorios em
   > `~/.claude/agent-memory/` NAO foram apagados - deixam de ser carregados, e voltam se o campo
   > voltar. O contrato de delegacao ja exige passar o contexto LOCAL no proprio prompt, que era
   > de onde o essencial deveria vir.
   >
   > LIMITE, que importa mais que a correcao: remover `memory:` fecha UM canal de escrita. NAO
   > torna ninguem read-only. Os oito tem `Bash`, que escreve por `>`, `tee`, `sed -i`,
   > `python3 -c` ou `git apply` - superficie estritamente maior que Write e Edit. Read-only como
   > MECANISMO depende de sandbox de filesystem, e em 2026-08-12 ele permanece NAO VERIFICADO
   > nesta maquina.

3. **Hooks disparam em tool-call de subagente.** Evidencia direta (transcript): o Write de um
   subagente acionou PreToolUse (emoji bloqueado) e PostToolUse (poka-yoke). Mecanismo: os hooks do
   `settings.json` sao herdados pelo subagente e executam no contexto dele. A disciplina de artefato
   e o poka-yoke, portanto, cobrem a escrita de subagente.

Nota de metodo: o agente que pesquisou a doc oficial ERROU duas vezes na sintese (negou que hooks
disparassem em subagente; classificou `memory: user` como no-op e recomendou remover). Ambos os
erros foram pegos por cruzamento com evidencia medida (transcript; listagem do disco). Licao
registrada: afirmacao de doc e hipotese ate o cross-check empirico - a doc decide o "como", o
artefato real decide o "se".

## Decisao

1. **Topologia de execucao (CLAUDE.md secao 7.1).** A lista da secao 7 e ordem de referencia, nao
   cadeia sequencial. Execucao otima segue o grafo de dependencia de DADOS: sequencial em
   investigador -> mapeador -> implementador; paralelo no design (mapeador || analista-otimalidade);
   FAN-OUT paralelo dos revisores read-only (sem dependencia entre si, lancados na mesma mensagem);
   BARREIRA no revisor-critico (que audita a saida dos demais, entao roda por ultimo e sozinho).
   Ganho = latencia (wall-clock O(soma)->O(maximo)), NAO custo de tokens. Aplica-se aos agentes
   gated-in, nao a todos por reflexo.

2. **Contrato de delegacao (CLAUDE.md secao 7.2).** Como a disciplina global e herdada, o prompt de
   Task a agente custom NAO a repete (redundante); carrega so o contexto de SESSAO, nao propagado:
   PRD, grafo, evidencia, saida de outros agentes, escopo e criterio de pronto. Para Explore/Plan,
   adiciona as regras criticas que eles ignoram. O prompt e artefato neutro - zero voz de persona.

## Limites honestos

- O paralelismo corta LATENCIA, nao tokens (mesmos N agentes opus). Afirmar "mais barato" seria
  afirmacao do consequente.
- O gating (quais agentes invocar) segue disciplina de julgamento, nao mecanismo enforcado (Diretriz
  13). A topologia otimiza a CONDUCAO dos agentes ja gated-in; nao decide o gating.
- A heranca de CLAUDE.md vale para agentes custom; ao usar Explore/Plan nativos, a regra critica
  ainda precisa ser repetida no prompt (Diretriz 10).

## Validacao

Tres testes empiricos citados acima (citacao verbatim do CLAUDE.md por subagente com tool_uses=0;
listagem de ~/.claude/agent-memory/ com 10 pastas e conteudo; transcript de hook disparando em
subagente). CLAUDE.md atualizado com 7.1 e 7.2. Sem alteracao nos agentes por conta de `memory:`.

## Corroboracao empirica (2026-06-23, ref: docs/research/referencias-pesquisa-agentes-llm.md)

- Auto-augmentacao de contexto em runtime DEGRADA; contexto deve vir de estagio anterior: CodeScout (arXiv:2603.05744, Alta) - sustenta o contrato de delegacao 7.2.
- Single-agent supera multi-agent em tarefa sequencial a fracao do custo: SE-Agent vs AgentOrchestra (arXiv:2604.02460, 1/22 do custo); OneFlow (arXiv:2601.12307, 10%) - sustenta o gating e o fan-out so para o genuinamente paralelo (7.1).
- Contexto curado eleva acuracia: AOrchestra (arXiv:2602.03786, 96% vs 84-86%). Qualidade de contexto preve reparo (r=0.950), grafo supera busca vetorial: SWE-Explore (arXiv:2606.07297) - sustenta o mapeador-dependencias.
- LIMITE (caveat 5 do doc): a COMBINACAO hooks + agentes especializados + orquestrador com contexto pre-carregado e lacuna no estado da arte - cada peca evidenciada, o todo nao.
