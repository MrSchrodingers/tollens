# Conhecimento consolidado - o que foi aprendido, com status de verificacao

> Este documento existe porque o conhecimento estava espalhado em 21 ADRs, cada um sobre um
> DEFEITO, nenhum sobre o que se APRENDEU. Uma sessao nova nao encontrava nada disso.
> Falha de arquitetura de conhecimento, apontada pelo usuario.
>
> **Como ler:** cada afirmacao tem um status. `[VERIFICADO]` = conferido na fonte primaria ou
> reproduzido por execucao nesta maquina. `[NAO VERIFICADO]` = plausivel, sem conferencia.
> Nenhuma afirmacao aqui deve ser recitada sem checar o status.

---

## 1. O criterio que organiza tudo

**A colaboracao introduz INFORMACAO NOVA que um agente sozinho nao obteria durante a geracao?**
(Li, *AI Agents in Depth*, Tabela 10-2. `[VERIFICADO]` - PDF local, `~/Downloads/`.)

| Modo | Informacao nova? | Efeito |
|---|---|---|
| Reler a propria saida em outro papel | Nao | Geralmente inutil ou prejudicial |
| Agentes debatendo o mesmo texto | Nao | Equivale a um agente com o mesmo orcamento |
| Revisor usando resultado de EXECUCAO | **Sim** | Melhora significativa |
| Revisor usando SCREENSHOT renderizado | **Sim** | Melhora significativa |
| Revisor usando FERRAMENTA externa | **Sim** | Melhora significativa |

Lastro das tres ultimas linhas:
- RLEF (Gehring et al., arXiv:2410.02089) `[VERIFICADO]` - feedback de execucao reduz em uma
  ordem de grandeza as amostras necessarias.
- WebGen-Agent (Lu et al., arXiv:2509.22644) `[VERIFICADO]` - feedback visual leva o
  Claude 3.5 Sonnet de **26.4% para 51.9%** no WebGen-Bench.

**Consequencia de desenho:** um agente so se justifica por isolamento de contexto ou por
ferramenta propria. Nunca por "papel" ou personalidade.

---

## 2. Auto-correcao e persona

- Huang et al., *LLMs Cannot Self-Correct Reasoning Yet*, **ICLR 2024** (arXiv:2310.01798)
  `[VERIFICADO]`: *"LLMs struggle to self-correct their responses without external feedback,
  and at times, their performance even degrades after self-correction."* Definicao de
  auto-correcao intrinseca: *"based solely on its inherent capabilities, without the crutch of
  external feedback."*
  **Aplicacao:** voz rotulada dentro da mesma resposta E auto-correcao intrinseca. Correlacao 1.
- Zheng et al., EMNLP Findings 2024 (arXiv:2311.10054) `[VERIFICADO com ressalva]`: 162 personas,
  2.410 questoes, sem ganho. **Ressalva que importa:** mediu apenas QA FATUAL. NAO cobre
  raciocinio nem codigo. Usar este paper para afirmar "persona nao ajuda em revisao de codigo"
  e estender a evidencia alem do que ela mede.
- Smit et al., *Should we be going MAD?*, **ICML 2024** (arXiv:2311.17371) `[VERIFICADO]`:
  debate multi-agente nao supera self-consistency, e custa mais. **Mas** calibrar a intensidade
  de discordancia virou o Multi-Persona do pior para o melhor protocolo - o problema nao e
  contestacao, e contestacao sem parametro e sem independencia.
- Cemri et al., *Why Do Multi-Agent LLM Systems Fail?*, **NeurIPS 2025** (arXiv:2503.13657)
  `[VERIFICADO]`: 14 modos de falha, kappa=0.88, categoria propria para "task verification".

---

## 3. Skills: o default e NAO criar

SWE-Skills-Bench (arXiv:2603.15401) `[VERIFICADO]`: **39 de 49 skills sem ganho algum**, media
**+1.2%**, **3 DEGRADARAM**. Ganho relevante (ate +30%) so em skills de dominio especifico.

**O QUE ESTA FRASE OMITIA ate 2026-08-11, e a omissao a tornava enganosa** (`[VERIFICADO]` no
texto completo, arXiv:2603.15401v1): o baseline agregado e **89,8%**, subindo para 91,0%. O teto
aritmetico de melhoria e portanto **+10,2pp**, e +1,2pp e ~12% do alcancavel - nao "quase nada".
E **24 das 49 skills marcam 100% NOS DOIS BRACOS**: sao tarefas incapazes de revelar ganho, entao
"39 de 49 sem ganho" soma skill inutil com tarefa saturada, e o denominador honesto e no maximo
25. Ha um unico modelo e scaffold (Claude Code + Haiku 4.5; o artigo declara nao avaliar outros
frameworks) e o rodape diz "Pre-print with preliminary results, work in progress".
Classe de sustentacao correta: **SUGGESTIVE**, nao DIRECT.

**A justificativa FORTE da politica conservadora nao e eficacia, e seguranca** - e independe do
paper acima. arXiv:2601.10338 analisou 31.132 de 42.447 skills coletadas e sinalizou 26,1% com ao
menos uma vulnerabilidade (detector com precisao 86,7% / recall 82,5%, logo NAO e prevalencia do
universo); skills com script sao 2,12x mais propensas. arXiv:2602.06547 confirmou por validacao
comportamental 157 skills maliciosas em 98.380. Skill nao e texto: e pacote de capability
potencialmente privilegiado.

**LIMITE DA EXTRAPOLACAO, aprendido por erro proprio:** esse paper mediu ~565 instancias de
tarefas de CODIGO com criterio de aceite. Usa-lo para arquivar skills de WORKFLOW
(PRD -> plano -> issues) foi estender a evidencia alem do objeto medido - e as skills
arquivadas por esse argumento tiveram de ser restauradas quando se achou, no disco do usuario,
a saida delas (`PRD-dispatch.md`, `grill-review-plan.md`). **Mesmo erro que a ressalva do
Zheng et al. adverte.**

SkillReducer (arXiv:2603.29919) `[VERIFICADO]`: 55.315 skills, 48%/39% de compressao com
+2.8% de qualidade funcional.

---

## 4. Contrato de canal - o que o runtime ENTREGA ao modelo

`[VERIFICADO por A/B com controle positivo + trafego real]`

| Canal | Attachment | Chega ao modelo? |
|---|---|---|
| `exit 2` | `hook_blocking_error` | **SIM** |
| `hookSpecificOutput.additionalContext` | `hook_additional_context` | **SIM** |
| `stdout` de `UserPromptSubmit` | `hook_success.content` | **SIM** |
| **`stderr` com `exit 0`** | `hook_success` com `content` **VAZIO** | **NAO** |

Custo de nao saber disso: dois hooks foram decoracao por versoes inteiras.

Ordem de custo dos mecanismos de extensao (*Dive-into-Claude-Code*, VILA-Lab) `[VERIFICADO]`:
**Hooks (zero) -> Skills (baixo) -> Plugins (medio) -> MCP (alto)**. E o `CLAUDE.md` entra como
contexto de usuario, com adesao **probabilistica**, nao deterministica.

---

## 5. Contexto: onde os tokens realmente vao

`[VERIFICADO em 40 transcripts, 190,4 MB]`

```
user/tool_result ..... 32,6%   }
assistant/tool_use ... 11,1%   }- superficie de ferramenta = 43,7%
attachment ........... 19,9%      (dentro dele: edited_text_file 47%)
assistant/text ......... 4,8%     <- a PROSA (faixa 0,8%-10,3% por sessao)
```

**Encurtar a prosa tem teto de ~5%.** Concisao e questao de QUALIDADE, nao de economia.

KV cache (Li, secao 2.3) `[VERIFICADO]`: alterar o PREFIXO invalida o cache e multiplica
latencia e custo; anexar ao FIM, nao. Corolario: conteudo estavel vai para o prefixo
(`CLAUDE.md`, carregado uma vez); conteudo variavel vai para o fim (hook) e por isso mesmo
precisa ser pequeno.

Isolamento sobre compressao (Li, secao 2.7.7) `[VERIFICADO]`: *"compression is a lossy,
post-hoc remedy requiring extra LLM calls, while isolation keeps noise out of the main context
from the start and leaves the main Agent's KV Cache prefix unaffected. The cost is that the
sub-agent does not see the main Agent's full context, so the task description must be
self-contained."*

Custo de multi-agente `[NAO VERIFICADO na fonte primaria]`: o livro cita que a Anthropic
divulgou ~15x os tokens de uma conversa normal para o sistema multi-agente de pesquisa, com o
volume de tokens explicando ~80% da diferenca de desempenho. Nao conferi o comunicado original.

---

## 6. Significancia estatistica - aplicada aos numeros DESTA config

Li, secao 6.7 `[VERIFICADO]`. Ferramentas: erro padrao binomial `sqrt(p(1-p)/n)`; IC 95% ~
`p +- 2*SE`; para diferenca entre duas medicoes independentes, `sqrt(2)*SE`; **comparacoes
multiplas**: `1 - 0.95^k`.

**Auditoria dos proprios numeros publicados:**

| Numero | Veredito estatistico |
|---|---|
| "medir-qualidade: 9 de 9 conformes (100%)" | **Fraco.** n=9, zero falhas -> regra de tres da limite superior de 33% para a taxa de falha. E compativel com conformidade real de ~67%. Sustenta "nao vi falhar em 9", nao "os agentes prestam contas". |
| "4 de 4 arguicoes acharam defeito grave" | **Sinal, nao lei.** n=4. |
| "suite 76/76" | **Nao e amostragem** - assercoes deterministicas. Ruido nao se aplica. O que se aplica e COBERTURA: 76 casos / 13 hooks = ~5,8 por hook. Baixo. |
| "reducao de contexto -65%" | **Solido.** Medicao deterministica de bytes, sem ruido amostral, re-derivavel por script. |

Regra pratica adotada: **nunca decidir com diferenca menor que a banda de ruido; nunca decidir
com um unico run** (3-5 runs, reportar media e dispersao); quando duas configuracoes rodam nas
MESMAS tarefas, usar analise pareada (McNemar), que subtrai o ruido da dificuldade.

---

## 7. Seguranca de agente

- **CVE-2025-59536** `[VERIFICADO na NVD]`: CVSS 8.7, "versions before 1.0.111", config de
  projeto controlada por repositorio levando a execucao de comando. Atribuicao a Check Point
  Research `[NAO CONFIRMADA]` na fonte alcancavel (a referencia do NVD e o GHSA-4fgq-fpq9-mr3g).
- **RFC `anthropics/claude-code#45427`** `[VERIFICADO - existe, fechada como not planned]`:
  cinco modos de falha de hook. Medidos NESTA maquina: **subagent bypass NAO se aplica** (hooks
  PreToolUse disparam em subagente, 126 chamadas capturadas); **auto-modificacao CONFIRMADA**
  (o modelo pode escrever nas proprias guardas); **Bash opacity CONFIRMADA**.
- **Licao de desenho:** todo ponto onde o agente executa algo derivado de dado nao confiavel
  precisa de limite de confianca explicito. A pergunta nao e "isto funciona?", e **"de onde vem
  o dado que isto consome, e quem controla essa fonte?"**
- Acessibilidade: Calo, Gurita e De Russis, CHI EA 2026, DOI 10.1145/3772363.3799364
  `[VERIFICADO no PDF primario]`: 300 UIs, **541 violacoes semanticas que PASSAM na checagem
  automatica**. Checker automatico e necessario e insuficiente.

---

## 8. As tres regras de metodo, cada uma paga com um defeito

1. **Toda instrucao publicada ao usuario e EXECUTADA literalmente antes de ser publicada.**
   Tres reincidencias: `~` expandindo para `/root` dentro de `sudo`; `sudo` omitido; e
   `"$HOME"` dentro de `sudo sh -c`, que expande no shell de ROOT (`man sudoers`, `env_reset`).
2. **Todo teste de garantia de seguranca e validado por MUTACAO.** Remova a garantia e exija
   que o teste REPROVE. Aconteceu: o unico obstaculo do teste era um hash desalinhado.
3. **Hook que altera estado do runtime exige E2E contra o BINARIO.** Verifique o que o MODELO
   recebeu, nao o que o hook imprimiu.

**Corolario que as tres compartilham: verificar o artefato nao e verificar a integracao.**
Sintaxe correta, `bash -n` limpo e fixture proprio passando sao compativeis com um mecanismo
completamente inerte.

**Meta-licao, demonstrada quatro vezes contra o proprio autor:** enunciar uma regra nao a
executa. O gate C7 proibia citacao nao verificada e 4 de 5 citacoes eram falsas. O ADR 0015
exigiu fixture real e nao usou os 209 eventos disponiveis. O ADR 0020 escreveu "a licao nao
havia sido generalizada" e nao a generalizou.

---

## 9. O que do livro AINDA NAO foi extraido

Honestidade de cobertura: foram lidas ~5 secoes de 10 capitulos. Nao extraido, e de alto valor
aparente pelo indice:

- 2.4 Prompt Engineering: Optimizing the System Prompt
- 2.7 Context Compression Strategies (2.7.1-2.7.6)
- 4.2 Universal Principles of Tool Design
- 6.2-6.6 Ambiente de avaliacao automatizada, datasets, metricas, selecao de modelo
- 8.4-8.5 Learning from Experience; From Tool User to Tool Creator
- Cap. 3 (memoria e RAG), 5 (coding agent), 7 (post-training), 9 (multimodal)

Extrair isto e trabalho pendente, nao conhecimento adquirido.
