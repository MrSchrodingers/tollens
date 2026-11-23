# ADR 0002 - Reforma da persona global e do pipeline de agentes: o Colegio Analitico

- Data: 2026-06-17
- Status: Aceito (validacao adversarial executada em 2026-06-17; achados incorporados - ver secao Validacao)
- Supersede: 0001-persona-triade-e-disciplina-epistemica.md (a persona Triade foi substituida)
- Escopo: configuracao global de usuario (~/.claude/)
- Decisor: mrschrodingers@gmail.com, via sessao de design assistida

## Contexto

A configuracao global anterior definia:

- Persona "A Triade": oscilacao Markov (sticky, uma voz por turno) entre tres
  intelectuais brasileiros (Karnal, Cortella, Clovis), declarada como camada de estilo.
- Pipeline de 10 subagentes (investigador, mapeador-dependencias, implementador, tdd,
  revisor-codigo, revisor-consistencia, cetico, insight, continuidade, revisor-critico).
- Hook `artifact-discipline.sh`: guarda lexical (anti-emoji + anti-hype/bajulacao),
  fail-closed, com isencao de Regra 2 para arquivos sob `.claude/`.

O usuario solicitou: (a) registro tecnico, formal e erudito; (b) postura critica,
cetica, anti-bajulacao, com o rigor de raciocinio de um filosofo analitico; (c)
integracao de competencias de seguranca (CVE/vulnerabilidade/depreciacao), ciencia da
computacao de otimalidade (algoritmos, arquitetura, topologia), engenharia de
producao / pesquisa operacional (fluxos) e analise matematica; (d) autorizacao para
reorganizar, refatorar e remover o que for incoerente.

A decisao foi fundamentada em pesquisa, nao em preferencia. Cinco frentes paralelas
coletaram evidencia citada (resumida em "Base de evidencia").

## Decisao

1. Substituir "A Triade" por "O Colegio Analitico": coloquio de vozes-arquetipo
   tecnico-cientificas que debatem na prosa do chat (PT-BR), cada voz mapeando uma
   FUNCAO EPISTEMICA, nao um ornamento. Vozes: Logico-Epistemologo, Arquiteto (CS),
   Auditor de Seguranca, Engenheiro de Producao / Pesquisador Operacional, Analista de
   Dados / Matematico. Aposentar Cortella e Clovis. Preservar o temperamento cetico de
   Karnal como inflexao do Logico-Epistemologo (o ceticismo dele e falibilismo
   popperiano aplicado).

2. Substituir a oscilacao Markov (uma voz por turno) pela CONVOCACAO POR RELEVANCIA: as
   vozes pertinentes ao tema sao chamadas. Default: UMA voz ou prosa neutra, sem rotulo -
   inclusive na maioria das questoes nao triviais. O debate multi-voz rotulado (tese ->
   objecao -> replica -> sintese) e reservado a questao com TENSAO real entre lentes ou alto
   custo de reversao; "nao trivial" sozinho nao o justifica (discriminador estreito, alinhado
   ao CLAUDE.md I.2.3 - ver achado 9 na Validacao).

3. Reforcar a disciplina anti-bajulacao (Diretriz 3) com intervencoes de prompt de
   lastro empirico: "Ask, Don't Tell" (reescrever a afirmacao do usuario como pergunta
   neutra antes de avaliar); nao abandonar posicao correta sob pressao; distinguir
   concordancia genuina de bajulacao (trava contra a sobre-correcao / ceticismo
   performatico); vigilancia multi-turn.

4. Adicionar a Diretriz 3.1 (Anti-falso-rigor): modelo, citacao ou abstracao so se
   justificam se mudam uma decisao. Ornamento que aparenta rigor e pior que a ausencia
   de rigor, porque transfere falsa confianca.

5. Adicionar 3 subagentes (opus, read-only), com gatilho por caracteristica da tarefa:
   - `analista-otimalidade`: complexidade (O/Theta vs limite inferior do problema) +
     arquitetura (modulos profundos/rasos, sintomas de Ousterhout, essencial vs
     acidental). Antes da implementacao, em paralelo ao mapeador-dependencias.
   - `auditor-seguranca` (PROFUNDA, gated): SCA (CVE + depreciado/EOL + integridade) +
     triagem CVSS x KEV x EPSS + taint exaustivo + threat model (STRIDE se fronteira), em
     superficie de ataque nova ou mudanca de dependencia. Os padroes de vuln de CODIGO
     (IDOR, mass-assignment, injecao via filtro) ficam no revisor-codigo, que roda em todo
     diff (ver achado 10). Apos revisor-codigo.
   - `analista-fluxos`: fluxo como rede de filas (Little, Kingman, Goldratt, Erlang);
     conclusao so sobre dado medido. Em analise/desenho de fluxo ou desempenho.

6. Reforcar 5 agentes existentes: investigador (criterio popperiano), cetico (perguntas
   criticas de Walton + catalogo de falacias + limite inferior), insight (falseabilidade
   do teste), revisor-codigo (regressao de complexidade + contrato pre/pos/invariante e
   LSP), revisor-critico (auditoria de complexidade acidental + anti-falso-rigor +
   steelman obrigatorio antes do veredito).

7. Manter o hook `artifact-discipline.sh` como guarda lexical estreita. A bajulacao
   SUBSTANTIVA (concordar com premissa falsa, abandonar resposta correta) e
   estruturalmente indetectavel por regex; nao tentar captura-la no hook. Atualizar
   comentarios e o lexico de bordao (atado a triade que sai).

8. Consolidar o documento `CLAUDE.md` em PT-BR (antes misturava ingles e PT-BR).

## Base de evidencia (resumo citado)

Frente 1 - Filosofia analitica e metodo:
- Toulmin, S. (1958) *The Uses of Argument* (claim/grounds/warrant/qualifier/rebuttal).
- Popper, K. (1934/1959) *The Logic of Scientific Discovery* (falseabilidade).
- Walton, D. (1996) *Argumentation Schemes for Presumptive Reasoning* (perguntas
  criticas; raciocinio derrotavel).
- Hume, D. (1748) *An Enquiry Concerning Human Understanding* ("a wise man proportions
  his belief to the evidence").
- Principio da caridade / steelman (regras de Rapoport, popularizadas por Dennett, 2013).
- Correcoes de atribuicao confirmadas: tese-antitese-sintese NAO e de Hegel (Mueller,
  1958); a obra de Hume e *Enquiry*, nao *Essay* (esse e de Locke).

Frente 2 - Sycophancy em LLMs (confianca anotada; o onus da fonte e do texto):
- [verificado] Sharma et al. (Anthropic, 2023) *Towards Understanding Sycophancy in
  Language Models* (arXiv:2310.13548): a bajulacao e produto previsivel do RLHF.
- [verificado] Perez et al. (2022) model-written evaluations (arXiv:2212.09251): inverse
  scaling.
- [verificado: arXiv:2602.23971] UK AI Security Institute (2026) *Ask, Don't Tell* (Dubois,
  Ududec, Summerfield, Luettgau): converter nao-perguntas em perguntas antes de responder
  reduz bajulacao, efeito mais forte que o baseline "nao seja bajulador". Correcao de
  atribuicao: e 2026 (nao 2025) e "AI Security Institute" (renomeado de "Safety" em
  fev/2025). NAO usar o superlativo no texto operativo (Diretriz 3.1).
- [verificado: arXiv:2502.08177] SycEval (Stanford, 2025): distingue sycophancy progressiva
  (~43,5%) de regressiva (~14,7% - abandonar resposta correta sob pressao/rebuttal), que e a
  forma perigosa para engenharia.
- [verificado: arXiv:2605.21778] taxonomia de sycophancy: o avaliador INDIVIDUAL e pouco
  confiavel (single-rater ICC2 = .184), enquanto o agregado de 106 especialistas e alto
  (ICC2k = .960). O ponto: o especialista isolado discorda do que conta como sycophancy -
  por isso um "avaliador" fixo como regex nao detecta a forma substantiva. A conclusao
  operativa nao depende do numero; ele fica restrito a este registro (Diretriz 3.1).

Frente 3 - Seguranca:
- OWASP Top 10:2025 (final jan/2026), com A03 "Software Supply Chain Failures".
- OWASP ASVS 5.0 (verificacao por requisito); CVSS v4.0 (FIRST); CISA KEV; EPSS (FIRST).
- CWE/MITRE; SLSA v1.0 (OpenSSF); NIST SSDF SP 800-218; OSV.dev; GHSA; endoflife.date.
- Regra dura: nunca recitar CVE/score de memoria; consultar a fonte ou declarar ausencia.

Frente 4 - CS / engenharia de software:
- Parnas (1972) information hiding; Ousterhout (2018) *A Philosophy of Software Design*
  (modulos profundos; sintomas: change amplification, cognitive load, unknown unknowns).
- Hoare (1969) logica de Hoare; Liskov & Wing (1994) LSP comportamental.
- Knuth (1974) otimizacao prematura (~97% das micro-eficiencias devem ser ignoradas).
- Brooks (1986) complexidade essencial vs acidental. CLRS: limite inferior Omega(n log n)
  para ordenacao por comparacao.
- SOLID tratado como heuristica contestada (critica de North/CUPID), nao dogma.

Frente 5 - Pesquisa operacional e matematica de fluxos:
- Little (1961) L = lambda*W. Kingman (1961) aproximacao G/G/1 (espera diverge com
  rho -> 1). Goldratt (1984) *The Goal* (Theory of Constraints, gargalo).
- Erlang B/C (dimensionamento). USL (Gunther). Cadeias de Markov (Whitt).
- Regra de ouro convergente com a Frente 1: o modelo so se justifica se muda uma decisao.

## Alternativas consideradas e rejeitadas

- Voz analitica unica (dialetica internalizada num so timbre): rejeitada; o usuario
  escolheu o coloquio de vozes na prosa.
- Reforma enxuta (otimalidade e fluxos como lentes, nao agentes): rejeitada; o usuario
  escolheu a reforma completa com agentes first-class. Ressalva tecnica honesta: a opcao
  enxuta tinha menor custo opus e menor risco de redundancia (a lente de complexidade hoje
  aparece em 4 agentes - analista-otimalidade, revisor-codigo, cetico, revisor-critico, em
  estagios distintos). A escolha foi acatada COM esses custos registrados, nao sem objecao.
- Maximo aparato academico (Toulmin obrigatorio por afirmacao, nivel de confianca
  numerico, ADR por decisao): rejeitada; a propria pesquisa (Frentes 1 e 5) aponta esse
  caminho como falso rigor (precisao espuria, verbosidade, citacao-padding).

## Consequencias

Positivas:
- Rigor distribuido por competencia (seguranca, otimalidade, fluxos first-class).
- Anti-bajulacao deixa de ser principio generico e ganha intervencoes de lastro empirico.
- A persona vira substancia (funcao epistemica), reduzindo o risco de "retorica inflada".

Custos e riscos (com mitigacao):
- Pipeline cresce de 10 para 13 agentes. O GATING (gatilho por caracteristica da tarefa)
  BUSCA conter o custo opus, mas e disciplina de julgamento da sessao principal, nao
  mecanismo enforcado como o hook: a contencao e hipotese a MEDIR (quantos agentes por
  tarefa, na pratica), nao garantia. A omissao de um agente que deveria ter rodado e
  auditada pelo revisor-critico (portao final) - Diretrizes 7 e 13.
- Risco de sobre-correcao (ceticismo performatico, discordancia gratuita): mitigado pela
  regra "concordancia genuina != bajulacao" (Diretriz 3).
- Risco de falso rigor: mitigado pela Diretriz 3.1 e pela auditoria do revisor-critico.

## Validacao

Revisao adversarial executada em 2026-06-17 por continuidade + cetico + revisor-critico
(sobre os arquivos, sem repo git). Veredito do portao final: "segue, com ressalvas" -
nenhum BLOQUEANTE nem ALTO; achados MEDIO e abaixo. A eficacia dinamica (a config de fato
reduzir bajulacao e o gating de fato conter custo) NAO e verificavel estaticamente; so se
observa em sessoes ao vivo - declarado explicitamente para nao cometer "sucesso declarado
sem prova".

Achados incorporados nesta revisao:
1. Colisao de ADR 0001 (duplicado): este ADR renumerado para 0002; o anterior marcado
   Superseded. Referencias genericas a "ADR 0001" no texto operativo atualizadas.
2. Auto-violacao de citacao (precisao espuria/selo de autoridade): "ICC ~ 0,18" e o
   superlativo "melhor intervencao" removidos do texto operativo (CLAUDE.md e hook);
   mantidos so neste registro de evidencia, com confianca anotada.
3. "Enforcado por hook" sobre-afirmado: o hook so cobre conteudo de arquivo
   (Write/Edit/MultiEdit/NotebookEdit); chat, commit/PR (Bash) e prompt de delegacao
   (Task) sao disciplina, nao garantia. Texto do CLAUDE.md corrigido.
4. Canibalizacao de voz: guardrail adicionado (a voz de persona nao substitui o subagente
   especialista homonimo).
5. Lacuna de autoridade sobre requisito: Diretriz 3 passou a distinguir pressao sobre
   fato tecnico (resistir) de correcao de requisito/escopo (acatar).
6. Temperamento de Karnal: removido o afeto ("melancolica"); reduzido a funcao falibilista
   pura, com caveat anti-incerteza-fabricada e anti-citacao-verbatim-sem-fonte.
7. Auditoria de omissao do gating adicionada ao revisor-critico; gatilho do
   auditor-seguranca estreitado; fronteira revisor-codigo (rasa) vs auditor-seguranca
   (profunda) explicitada.
8. cetico e insight ganharam memory: user (acumulam padroes de falacia/edge do repo).

Achados incorporados nas revalidacoes (Rodadas 1 e 2):
9. Discriminador do coloquio estreitado (I.2.3) e ADR Decisao #2 alinhada: default uma voz;
   o debate exige SEMPRE >=2 lentes em tensao genuina; "alto custo de reversao" deixou de ser
   gatilho-OU auto-concedivel (razao para BUSCAR a tensao, nao para encena-la).
10. Furo de seguranca P4 (achado na Rodada 1, reaberto e fechado na Rodada 2 - mover a
    seguranca de codigo apenas RELOCAVA o gate de "CRUD vs A01" para "trivial vs
    nao-trivial"). Correcao em DOIS LEITORES INDEPENDENTES (o 2o gated na invocacao, nao 3
    camadas - (b) e (c) abaixo vivem ambas no revisor-critico): (1) a REGRA DE TRIVIALIDADE
    define qualquer diff de acesso a dados/autorizacao/entrada nao-confiavel como nao trivial
    - pela superficie tocada, nao pelo tamanho - forcando o revisor-codigo (1o leitor) a rodar
    ate num diff de 1 linha; (2) o revisor-critico, lendo o diff cru como 2o leitor
    independente da percepcao da sessao, faz a auditoria de omissao do revisor-codigo (b) E a
    checagem A01 como rede final (c). O auditor-seguranca ficou para a PROFUNDIDADE (SCA/CVE/supply chain/threat model)
    em superficie nova ou dependencia. LIMITE INERENTE declarado: nenhum mecanismo (so o hook
    seria, e A01 nao e regex-avel) forca a sessao a seguir a regra - resta disciplina, nao
    garantia, mesmo teto da eficacia comportamental.
11. Escotilha de fuga e calibracao na Diretriz 3 (afirmacao mista): proibido reclassificar
    um fato falseavel como "requisito" para ceder; em afirmacao mista, acatar a escolha sem
    silenciar o fato; e o peso da objecao deve ser proporcional a gravidade - fato grave
    (perda de dado, seguranca, irreversibilidade) nao e nota de rodape, e bloqueio com
    destaque, nunca registro perfunctorio.
12. Hook: fail-closed tambem para input JSON malformado (antes fail-open com jq presente);
    nota de que o range de emoji barra dingbats tecnicos (check/warning) por design.
13. Seccao 1 do CLAUDE.md passou a mencionar a isencao .claude/ da regra de lexico (remete
    ao cabecalho, fonte autoritativa).

Verificacao de fontes (2026-06-17, contra arXiv/OWASP oficial): as tres pendentes foram
CONFIRMADAS, com correcao. UK "Ask, Don't Tell" = arXiv:2602.23971, **2026**, "AI Security
Institute". SycEval = arXiv:2502.08177 (Stanford). Taxonomia ICC = arXiv:2605.21778
(single-rater .184 vs agregado .960). OWASP Top 10:2025 com A03 Software Supply Chain
Failures confirmada como versao corrente na fonte oficial. Nenhuma citacao caiu como
fabricada. Fragilidades conhecidas (nao corrigidas por decisao): hook fail-closed por jq se
jq sair do PATH; range de emoji bloqueia dingbats tecnicos (usar ASCII em doc).

## Corroboracao empirica (2026-06-23, ref: docs/research/referencias-pesquisa-agentes-llm.md)

- Bajulacao como produto previsivel do RLHF: Sharma et al. (arXiv:2310.13548); Perez et al. (arXiv:2212.09251).
- Enquadramento NEGATIVO ativa o conceito proibido (semantic gravity well): Jang et al. (arXiv:2209.12711, peer-reviewed) + recomendacao oficial Anthropic de converter negacao em afirmacao. Motivou o refino de enquadramento positivo na Secao 3 e nos agentes cetico/revisor-critico (v1.4.0).
