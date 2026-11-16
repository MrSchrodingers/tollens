# ADR 0048 - O pedido de modelo nao e o modelo que roda

Data: 2026-11-16
Estado: aceito
Relaciona: ADR 0012 (guarda dura do fable), ADR 0014 (contrato de subagente e transcript do pai),
ADR 0015 (instrumentacao permanente de eventos de subagente)

## O defeito, medido

Subagentes que pedem um modelo (`opus`, por exemplo) rodam em outro (`claude-sonnet-5-5`) sem
erro e sem aviso: a allowlist de modelos da politica managed substitui o pedido em silencio.
Na investigacao que originou a fatia S0 do PRD do roteador de modelos (secoes 1, R5, I1, I5, I6)
foram contados 48 subagentes que pediram `opus` e rodaram em Sonnet. Esse numero vem da
investigacao a montante e nao foi remedido nesta fatia. O que esta fatia verifica por execucao
e o detector, nao a contagem.

A consequencia e epistemica: o orquestrador delega uma revisao ou refutacao julgando que ela
passou por um modelo mais forte, e a evidencia que volta carrega um rotulo de capacidade que o
runtime nao cumpriu. Nada na cadeia de hooks comparava o pedido com o que rodou.

## O que o payload entrega (medido em eventos reais de SubagentStop)

Chaves: `agent_id`, `agent_transcript_path`, `agent_type`, `background_tasks`, `cwd`, `effort`,
`hook_event_name`, `last_assistant_message`, `permission_mode`, `prompt_id`, `scratchpad_dir`,
`session_crons`, `session_id`, `stop_hook_active`, `transcript_path`. Quatro fatos governam o
desenho:

1. Nao existe campo `model`. A comparacao nao pode sair do payload.
2. `effort` e o objeto `{"level":"high"}` da sessao, nao do subagente; nao serve de pedido.
3. 29 de 63 eventos tem `agent_type` vazio.
4. 32 de 63 apontam para transcript que nao existe mais no disco.

## A decisao

Novo hook `evidence/hooks/model-honor.sh`, registrado em `SubagentStop`
(`install/hooks-spec.sh`), capability `hook_instrument` no registry.

- PEDIDO: `.model` e `.effort` de `${agent_transcript_path%.jsonl}.meta.json`, arquivo que o
  runtime grava ao lado do transcript do subagente.
- EFETIVO: `.message.model` da primeira linha `assistant` do transcript do subagente, ignorando
  `<synthetic>`, em leitura limitada (1 MiB, 400 linhas). Nunca `transcript_path`, que e o do
  pai (ADR 0014).
- COMPARACAO: alias (`opus|sonnet|haiku|fable`) casa por familia (`claude-<alias>-*`); trocar a
  versao dentro da familia nao diverge, e o ID efetivo fica registrado. ID completo exige
  igualdade exata. `inherit`, vazio ou ausente: `sem_pedido`. Valor fora do vocabulario:
  `pedido_desconhecido`. Transcript ou meta ausente ou ilegivel, sem linha assistant, ou
  caminho fora da raiz: `indeterminado`. Divergencia: `DIVERGE`.
- SAIDA: uma linha JSONL por evento em `${MODEL_HONOR_LOG:-~/.claude/logs/model-honor.jsonl}`,
  rotacao a 2 MB, modo 0600, somente identificadores, nomes de modelo e motivo curto. Em
  `DIVERGE`, um `systemMessage` em stdout.
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
  pedido->efetivo). Exit 0 sem `DIVERGE`, 1 com, 2 em erro de uso ou de instrumento. Permite
  medir o passivo historico sem depender de o hook ter estado ativo.

## Limites declarados

- Julga so a primeira mensagem assistant. Troca de modelo no meio da execucao nao e vista.
- Transcript cuja primeira linha assistant fica alem do teto de leitura vira `indeterminado`,
  nao falso `honrado`.
- Um valor de pedido com sufixo de variante (por exemplo contexto estendido) que nao esteja no
  vocabulario cai em `pedido_desconhecido` ou em `DIVERGE` se for ID completo; a forma exata dos
  valores reais de `.model` do meta nao foi enumerada nesta fatia.
- A entrega do `systemMessage` de `SubagentStop` ao operador depende do runtime e nao foi
  medida aqui. O log e a fonte primaria; o `systemMessage` e aviso adicional.
- Em eventos cujo transcript ja nao existe no disco (32 de 63 na amostra), o resultado e
  `indeterminado`: o verificador nao recupera retroativamente o que o runtime apagou.
- Nao corrige a substituicao: apenas a torna visivel. A politica da allowlist continua sendo
  decisao do operador.

## Verificacao

`tests/unit/model-honor.sh`: 14 casos, um por invariante ou por corpus parametrizado
(controle positivo `opus` -> `claude-sonnet-5-5`, familia, ID exato, pedido ausente, transcript
ausente, caminho hostil, entrada nao JSON, `<synthetic>`, ausencia de `jq`, I5, `--scan`, modo
do log). O controle positivo foi observado vermelho antes de o hook existir.

## Referencias

- `evidence/hooks/model-honor.sh`, `tests/unit/model-honor.sh`.
- `install/hooks-spec.sh` (bloco `SubagentStop`), `orchestration/registry.json` (entrada
  `model-honor.sh`), `install/manifest.lock`.
- ADR 0014 (transcript do pai nunca e fonte), ADR 0015 (instrumentacao permanente).
