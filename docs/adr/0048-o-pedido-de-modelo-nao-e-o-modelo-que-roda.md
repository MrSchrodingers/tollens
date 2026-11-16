# ADR 0048 - O pedido de modelo nao e o modelo que roda

Data: 2026-11-16
Estado: aceito
Relaciona: ADR 0012 (guarda dura do fable), ADR 0014 (contrato de subagente e transcript do pai;
torna permanente a sonda de SubagentStart/SubagentStop), ADR 0015 (regra "hook novo so entra com
evento REAL capturado como fixture" e confirmacao da sonda como componente permanente)

## O defeito, medido

Subagentes que pedem um modelo (`opus`, por exemplo) podem rodar em outro
(`claude-sonnet-5-5`) sem erro e sem aviso. A hipotese de causa e a substituicao silenciosa pela
allowlist de modelos da politica managed; a causa NAO esta provada (ver Limites). Nada na cadeia
de hooks comparava o modelo pedido com o que rodou.

Medicao da divergencia, feita com o modo `--scan` deste hook sobre `~/.claude/projects` em
2026-11-16 por revisao e refutacao independentes e pelo coordenador da fatia, nao repetida pelo
autor ao escrever este ADR: `--scan` completo acusou 54 DIVERGE (48 `opus -> claude-sonnet-5-5`
e 6 `fable -> claude-sonnet-5-5`) em 1537 a 1538 metas; `--scan --since 2026-11-13T05:00:00Z`
acusou 48 `opus -> claude-sonnet-5-5` e 19 `opus -> claude-opus-5-5` honrados. A consequencia e
epistemica: o orquestrador delega uma revisao ou refutacao julgando que ela passou por um modelo
mais forte, e a evidencia que volta carrega um rotulo de capacidade que o runtime nao cumpriu.

## O que o payload entrega

Chaves de um evento real de SubagentStop: `agent_id`, `agent_transcript_path`, `agent_type`,
`background_tasks`, `cwd`, `effort`, `hook_event_name`, `last_assistant_message`,
`permission_mode`, `prompt_id`, `scratchpad_dir`, `session_crons`, `session_id`,
`stop_hook_active`, `transcript_path`. Fatos que governam o desenho:

1. Nao existe campo `model`. Medido em 2026-11-16 sobre `~/.claude/logs/subagent-probe.jsonl` e
   `.1`: 353 eventos SubagentStop, nenhum com `model`. A comparacao nao pode sair do payload.
2. `effort` e o objeto `{"level":"high"}` da sessao, nao do subagente; nao serve de pedido.
3. Nessa mesma amostra, 124 eventos tem `agent_type` vazio e esses 124 sao exatamente os 124 sem
   transcricao em disco (0 dos 229 com tipo preenchido). A classe desses 124 eventos e
   desconhecida.

## A decisao

Novo hook `evidence/hooks/model-honor.sh`, registrado em `SubagentStop`
(`install/hooks-spec.sh`), capability `hook_instrument` no registry.

- PEDIDO: `.model` e `.effort` de `${agent_transcript_path%.jsonl}.meta.json`, arquivo que o
  runtime grava ao lado do transcript do subagente. `.pickedEffortModel` do meta e registrado
  como `picked_effort_model`, so informativo, e NAO entra no julgamento.
- EFETIVO: `.message.model` da primeira linha `assistant` do transcript do subagente, ignorando
  `<synthetic>`, em leitura limitada (1 MiB e 400 linhas; o meta, 64 KiB). Nunca
  `transcript_path`, que e o do pai (ADR 0014).
- COMPARACAO: alias (`opus|sonnet|haiku|fable`) casa pela familia do ID efetivo, derivada por
  token (primeiro token de familia do ID normalizado, o que cobre tambem
  `claude-3-5-sonnet-20241022`). Trocar a versao dentro da familia nao diverge; o ID efetivo fica
  registrado. ID completo (`claude-*`) exige igualdade exata apos normalizar: minusculas, sem
  sufixo `[...]` (como `[1m]`), sem prefixo `anthropic.` ou `<regiao>.anthropic.`, sem sufixo
  `@<data>`. `inherit`, vazio, null ou ausente: `sem_pedido`. Tipo errado (numero, array,
  objeto, booleano) ou valor fora do vocabulario: `pedido_desconhecido`. Transcript ou meta
  ausente ou ilegivel, sem linha assistant, ou caminho fora da raiz: `indeterminado`.
  Divergencia: `DIVERGE`.
- SAIDA: uma linha JSONL por evento em `${MODEL_HONOR_LOG:-~/.claude/logs/model-honor.jsonl}`,
  modo 0600, ASCII puro (U+2028 e U+2029 escapados), somente identificadores, nomes de modelo e
  motivo curto, com `pedido_origem` (`meta` ou `ausente`). Todo campo textual do payload e
  truncado a 256 caracteres antes de montar o JSON; sem isso um campo acima de ~128 KiB
  derrubava o `jq --arg` e o DIVERGE sumia sem registro. Rotacao a 2 MB e append sob `flock`
  num arquivo de trava ao lado do log; sem `flock`, ou sem a trava em 5 s, grava sem rotacionar
  (nunca perde historico). A rotacao anterior, sem trava, perdia de 1 a 4 de 150 eventos
  concorrentes e podia sobrescrever o historico.
- STDOUT: um unico `systemMessage` de no maximo 300 caracteres em tres casos: DIVERGE; falha ao
  gravar o log (`model-honor: nao consegui gravar o log (<motivo>)`); `jq` ausente (texto fixo,
  escrito sem `jq`, para o desligamento do detector deixar rastro). Nos demais casos, nada.
- FALHA ABERTA: o modo hook sai sempre com 0 e nunca bloqueia. A decisao de bloquear um
  subagente por modelo divergente nao e desta fatia; o hook so torna a divergencia observavel.
- CAMINHO HOSTIL: o caminho do payload e resolvido com `realpath`, precisa casar
  `*/subagents/agent-*.jsonl` e estar sob `~/.claude/projects/` ou
  `~/.local/share/ai-central/accounts/*/projects/`; o meta resolvido passa pela mesma raiz. Fora
  disso nada e lido e o evento fica `indeterminado` com motivo `caminho_fora_da_raiz`.
- PRIVACIDADE (I5): o hook nunca le nem grava `last_assistant_message`, prompt ou texto de
  mensagem. A suite prova com um segredo sintetico presente no transcript e no payload.
- MODO `--scan <projects_dir> [--since <ISO8601>]`: aplica a mesma funcao de julgamento a
  `*/*/subagents/agent-*.meta.json` e imprime resumo TSV (contagem por status e por par
  pedido->efetivo; TAB e quebra de linha em caminhos viram espaco). Exit 0 sem `DIVERGE`, 1
  com, 2 em erro de uso ou de instrumento: `jq` que nao funciona, diretorio inexistente ou
  nenhum meta encontrado. Um `--since` que exclui tudo nao e erro. Permite medir o passivo
  historico sem depender de o hook ter estado ativo.

## Limites declarados

a. 56% dos metas reais nao trazem pedido: 858 de 1538 foram `sem_pedido` na varredura da
   refutacao independente (inclui `inherit`). O hook nao julga o que nao foi pedido por
   parametro e nao le o frontmatter do agente. A refutacao viu `investigador`, cujo frontmatter
   atual declara `model: haiku`, rodar em `claude-opus-5-5` em 12 execucoes sem pedido no meta.
   O frontmatter vigente na epoca dessas execucoes pode ter sido outro: NAO VERIFICADO.
b. Os 124 eventos com `agent_type` vazio e sem transcricao nao sao julgaveis (resultam
   `indeterminado`), e a classe deles e desconhecida; pode incluir agentes de workflow: NAO
   VERIFICADO. O verificador nao recupera retroativamente o que o runtime apagou.
c. Teto de leitura: transcript cuja primeira linha assistant fica alem de 1 MiB ou da linha 400
   vira `indeterminado`, nunca falso `honrado`. Meta acima de 64 KiB vira `indeterminado`.
d. TOCTOU entre o `realpath` e a leitura: explora-la exige escrita do mesmo usuario em
   `~/.claude/projects`; risco residual baixo, aceito.
e. A entrega do `systemMessage` do SubagentStop ao operador nao foi medida. O log e a fonte
   primaria; o `systemMessage` e aviso adicional.
f. O hook so tem efeito sob instalacao managed: o arquivo managed lido em 2026-11-16 tem
   `allowManagedHooksOnly=true` (leitura nao repetida na escrita deste ADR). Hook declarado so
   no escopo de usuario nao roda nessa configuracao.
g. `pickedEffortModel` do meta tem semantica NAO verificada. Hipotese: modelo da sessao pai.
   O cruzamento da revisao independente (`meta.model | pickedEffortModel | efetivo`) mostrou
   `opus|claude-fable-5-2|claude-opus-5-5` x46 e `opus|claude-sonnet-5-5|claude-sonnet-5-5` x48:
   o campo diverge do efetivo em parte dos casos, e por isso a hipotese de substituicao pela
   allowlist (secao "O defeito") tambem nao esta provada por esses dados. O campo e so
   registrado, para correlacao futura.
h. Julga so a primeira mensagem assistant; troca de modelo no meio da execucao nao e vista.
i. Um ID completo com sufixo de versao diferente (por exemplo `-20261101` a mais) diverge por
   desenho: so `[...]`, `anthropic.`, `<regiao>.anthropic.` e `@<data>` sao normalizados.
j. Regra 1 do ADR 0015 (hook novo so entra com evento REAL capturado como fixture): o `--scan`
   foi exercido sobre os arquivos reais em disco (os mesmos metas e transcripts que o runtime
   gravou), mas o modo hook nao foi exercido contra um evento SubagentStop ao vivo; as fixtures
   da suite sao sinteticas. NAO VERIFICADO no runtime.

## Verificacao

`tests/unit/model-honor.sh`: 24 casos, cada um protegendo um invariante nomeado no cabecalho da
suite (deteccao, falha aberta, ausencia de silencio, historico sob concorrencia, caminho hostil e
transcript do pai, regra de comparacao, tetos, privacidade). O controle positivo (caso 1, `opus`
contra `claude-sonnet-5-5`) foi registrado como vermelho pelo autor na sessao de 2026-11-16,
antes de o hook existir; essa observacao nao e reproduzivel a partir do diff.

Mutantes do hook (remocao de rotacao e de trava, tetos de leitura, familia, caixa,
sanitizacao, escopo do scan, fronteira de `--since`, fallback ao transcript do pai, entre
outros) foram aplicados para conferir a suite: 29 de 31 morreram. Os 2 sobreviventes sao
equivalentes: a guarda de raiz do transcript e coberta pela guarda de raiz do meta, derivado do
mesmo caminho, e o teto de 300 caracteres do `systemMessage` nunca e atingido porque cada campo
ja e truncado a 40 caracteres e o motivo de falha de log a 80.

## Referencias

- `evidence/hooks/model-honor.sh`, `tests/unit/model-honor.sh`.
- `install/hooks-spec.sh` (bloco `SubagentStop`), `orchestration/registry.json` (entrada
  `model-honor.sh`), `install/manifest.lock`, `scripts/status.sh` (enumera a suite).
- ADR 0014 (transcript do pai nunca e fonte; sonda permanente), ADR 0015 (regra do evento real).
