# ADR 0050 - Pendencia do operador exige pergunta estruturada

Data: 2026-11-17
Estado: aceito. O hook esta INERTE ate a instalacao managed (apply-managed.sh, a cargo do
operador); em 2026-11-17 ele nao consta de nenhum settings. `installed: true` no registry
significa "presente no manifesto", nao "ativo no runtime" (mesma ressalva do ADR 0048).
Numeracao: 0050. O numero 0049 esta reservado ao R3 do roteador (router-modelos-spec.md); este ADR
foi emitido como 0049 no primeiro commit e renumerado na rodada 2.
Relaciona: ADR 0021 (canais que entregam: exit 2 bloqueia), ADR 0022 (Stop nao e fronteira de
confianca), ADR 0014 (contrato de subagente, transcript do pai x do subagente), ADR 0048
(modelo de log JSONL sem conteudo)

## O defeito, medido

Sessoes e agentes encerram o turno com texto como "suas pendencias", "decisao sua", "aguardo sua
confirmacao" sem chamar AskUserQuestion. O operador fica sem pergunta estruturada (opcoes,
recomendacao marcada) e a pendencia fica em prosa. O proprio coordenador fez isso por horas. A
medicao original e do operador (decisao de 2026-11-17, "regra + hook Stop"); este repositorio nao
tem, ainda, a contagem de ocorrencias: o modo `aviso` existe para produzi-la.

## A decisao

1. Regra textual curta para o CLAUDE.md global do operador, redigida em
   `docs/proposals/pending-ask-regra.md`. NAO aplicada por esta mudanca: o arquivo global e do
   operador.
2. Hook `evidence/hooks/pending-ask.sh`, registrado em `Stop` (`install/hooks-spec.sh`),
   capability `hook_gate` no registry (E_M e E_S pagas por `tests/unit/pending-ask.sh`: o
   instrumento pode bloquear, e a falha aberta e o anti-laco sao invariantes de seguranca).
3. Contrato de subagente: o retorno traz, em linha propria,
   `DECISAO_PENDENTE: <pergunta>|<opcao recomendada>|<alternativas>`. SubagentStop nao bloqueia
   (e o hook nao esta la). O hook de Stop da sessao principal trata a linha, recebida em retorno
   de chamada Agent/Task do turno, como "precisa perguntar" (padrao `decisao_pendente_subagente`).
   Quem pergunta ao operador e a sessao principal, com AskUserQuestion.

## Como o hook decide

- Texto: `last_assistant_message` do payload se presente; senao o ultimo bloco de texto assistant
  do turno no transcript. Turno = tudo depois da ultima mensagem REAL do usuario (`type=user` com
  `tool_result`, `isMeta` e `isSidechain` nao contam).
- Disparo = (padrao de uma lista FECHADA e VERSIONADA casa no texto normalizado, ou ha
  DECISAO_PENDENTE de subagente) E (nenhum `tool_use` AskUserQuestion no turno). Padroes sao
  locucoes, nunca palavra solta; `PADROES_V` sobe a cada mudanca da lista.
- Modo, por arquivo `~/.claude/pending-ask.mode` (`off|aviso|bloqueio`), padrao `aviso`:
  `aviso` so registra; `bloqueio` registra e bloqueia UMA vez (exit 2 + stderr, o canal que
  entrega, ADR 0021). Ausente: `aviso`. Invalido: `aviso` com linha de erro.
- Anti-laco: `stop_hook_active=true` sai 0 sem bloquear. Evento ilegivel nao bloqueia.
- Falha aberta: toda saida e 0 exceto o bloqueio deliberado (`trap EXIT`). Falha deixa linha
  `evento=erro` com motivo.
- Log `~/.claude/logs/pending-ask.jsonl`, 0600, campos: ts, session_id, evento
  (disparo|suprimido|erro), modo, padrao_casado, bloqueou, padroes_v, motivo (so em erro).
  Nunca conteudo de mensagem, transcript ou retorno de subagente. Resposta sem padrao nao deixa
  rastro; `suprimido` registra o caso em que o padrao casou e havia AskUserQuestion.

## Rodada 2 (PADROES_V=2): citacao, borda e minimos

Revisao independente apontou falso positivo por citacao e falsos negativos de borda. Mudancas:
- Antes de casar, o texto perde bloco de codigo (``` e ~~~), codigo inline, linhas iniciadas por `>`
  e trechos entre aspas duplas, curvas ou angulares (ate 160 caracteres, uma linha). Aspas simples
  nao sao tratadas (apostrofo). Efeito colateral aceito: duas aspas soltas na mesma linha escondem o
  que ha entre elas.
- Normalizacao: NFKC aproximado em jq, sem dependencia nova: zero-width e controles de direcao
  somem, marcas combinantes somem (cobre NFD), espacos Unicode viram espaco, ASCII de largura total
  volta a ASCII. Nao e NFKC completo.
- `confirma_pergunta` so casa no inicio de frase (`Confirma?`), nao no meio (`O teste confirma?`).
- Padroes novos: `fico_no_aguardo`, `pendencias_para_voce`, `posso_prosseguir` (exige `?`).
  `se_preferir_posso` segue cobrindo `Se quiser, posso ...`: e o que a regra proibe quando o passo e
  do agente.
- Decisao sobre AskUserQuestion: ele suprime em QUALQUER ponto do turno (depois da ultima fala real
  do usuario). A alternativa, exigi-lo posterior a ultima fala com padrao, nunca suprimiria nada,
  porque o turno termina na fala final. Custo aceito: pendencia nova depois de um AskUserQuestion ja
  respondido no mesmo turno nao e pega. E o erro barato para um hook que, em `bloqueio`, forca turno.
- Ultima linha do transcript partida (gravacao em curso) e sem `last_assistant_message`: sem
  veredito, `erro/ultima_linha_truncada`, em vez de julgar texto antigo do turno.
- Arquivo de modo: branco e linhas vazias na frente sao ignorados; caixa e irrelevante.
- Rotacao do log (2 MiB, uma geracao) sob `flock`; sem `flock` ou sem a trava em 5 s grava sem
  rotacionar. Nao ha teste de corrida (nao e deterministico); so o de rotacao simples.
- Sessao headless: AskUserQuestion nao pode ser respondido, e bloquear forcaria turno impossivel. O
  hook nunca bloqueia quando o transcript traz `entrypoint: "sdk-cli"` (log com
  `auq_disponivel: false`). Medido em 2026-11-17 sobre os 40 transcripts mais recentes: 23 `sdk-cli` e
  17 `cli`, nenhum com os dois. A disponibilidade do AskUserQuestion NAO e observavel no transcript
  (o registro de ferramentas diferidas nao o lista; a palavra aparece em arquivos de instrucao, ate
  em sessoes `sdk-cli`). O entrypoint e proxy: nao verificado que `claude -p` implica `sdk-cli` em
  todas as versoes, nem que todo `sdk-cli` e sem AskUserQuestion (programas do Agent SDK podem tê-lo).

## Plano de medicao (1 semana em `aviso`)

Antes de ligar `bloqueio`: contar `disparo` por `padrao_casado` e revisar uma amostra por padrao
contra a conversa de origem (o log nao guarda texto; a revisao e pelo `session_id` e `ts`).
Padrao com falso positivo recorrente sai da lista (subindo `PADROES_V`). `quer_que_eu` e
`posso_prosseguir` sao os candidatos mais fracos. Linhas do log de versoes diferentes nao se somam. Criterio de virada para `bloqueio`: decisao do
operador sobre a taxa observada; este ADR nao fixa limiar, porque nao ha medida que o sustente.

## Limites declarados

- NAO e fronteira de confianca: o arquivo de modo e o log vivem em ~/.claude, escrita do ator
  governado; o runtime sobrepoe hooks de Stop apos N bloqueios (ADR 0022).
- Detecao lexical: nao distingue pergunta ao operador de citacao da mesma locucao (resumo de
  conversa, texto de documento). Falso negativo: pendencia redigida fora da lista.
- Retorno de subagente em background chega como mensagem de usuario e nao e inspecionado.
- Formato de transcript (um bloco por linha, `tool_result` em linha `user`) e `tool_use` com nome
  `AskUserQuestion`/`Agent`/`Task` foram lidos de um transcript real de 2026-11-17 apenas por
  estrutura (chaves); a forma do payload de Stop (campos `transcript_path`, `stop_hook_active`,
  `last_assistant_message`) vem do uso pelo verify-gate e do ADR 0048, nao de captura de Stop.
  NAO VERIFICADO: carregamento real no Claude Code, que depende da instalacao managed.
- Os arquivos de agente (`execution/agents/*.md`) NAO foram alterados para emitir a linha
  `DECISAO_PENDENTE`; ate isso ocorrer ela depende do prompt de delegacao.

## Reproducao

    bash tests/unit/pending-ask.sh          # 26 casos, exit 0
    PENDING_ASK_HOOK=<hook que sai 0> bash tests/unit/pending-ask.sh   # vermelho
