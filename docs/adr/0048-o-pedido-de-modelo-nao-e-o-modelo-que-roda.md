# ADR 0048 - O pedido de modelo nao e o modelo que roda

Data: 2026-11-16
Estado: aceito. O hook esta INERTE ate a instalacao managed: em 2026-11-16 ele nao constava de
nenhum settings (nem o managed, nem o de usuario). O campo `installed: true` do registry significa
"presente no manifesto de instalacao" (o teste CC5 de `tests/unit/capability-conformance.py`
exige manifesto == registry por fonte; `installed: false` reprova), e nao "ativo no runtime".
Relaciona: ADR 0012 (guarda dura do fable), ADR 0014 (contrato de subagente e transcript do pai;
torna permanente a sonda de SubagentStart/SubagentStop), ADR 0015 (regra 1 "hook novo so entra
com evento REAL capturado como fixture", regra 3 "todo numero publicado vira script", e
confirmacao da sonda como componente permanente)

## O defeito, medido

Subagentes que pedem um modelo (`opus`, por exemplo) podem rodar em outro
(`claude-sonnet-5-5`) sem erro e sem aviso. A hipotese de causa e a substituicao silenciosa pela
allowlist de modelos da politica managed; a causa NAO esta provada (ver Limites). Nada na cadeia
de hooks comparava o modelo pedido com o que rodou.

A divergencia foi medida com o modo `--scan` deste hook sobre `~/.claude/projects` (comando na
secao Reproducao). Em 2026-11-16: 54 DIVERGE (48 `opus -> claude-sonnet-5-5` e 6
`fable -> claude-sonnet-5-5`) em cerca de 1540 metas. As contagens absolutas crescem com o corpus;
o que se espera de uma reexecucao e a mesma ordem de grandeza e os mesmos pares. A consequencia e
epistemica: o orquestrador delega uma revisao ou refutacao julgando que ela passou por um modelo
mais forte, e a evidencia que volta carrega um rotulo de capacidade que o runtime nao cumpriu.

## O que o payload entrega

Chaves de um evento real de SubagentStop: `agent_id`, `agent_transcript_path`, `agent_type`,
`background_tasks`, `cwd`, `effort`, `hook_event_name`, `last_assistant_message`,
`permission_mode`, `prompt_id`, `scratchpad_dir`, `session_crons`, `session_id`,
`stop_hook_active`, `transcript_path`. Fatos que governam o desenho (comando na secao Reproducao):

1. Nao existe campo `model`: 353 eventos SubagentStop, nenhum com `model` (2026-11-16, sonda
   `~/.claude/logs/subagent-probe.jsonl` e `.1`). A comparacao nao pode sair do payload.
2. `effort` e o objeto `{"level":"high"}` da sessao, nao do subagente; nao serve de pedido.
3. Nessa amostra, 124 eventos tem `agent_type` vazio e esses 124 sao exatamente os 124 sem
   transcricao em disco (0 dos 229 com tipo preenchido). A classe desses 124 e desconhecida.

## A decisao

Novo hook `evidence/hooks/model-honor.sh`, registrado em `SubagentStop`
(`install/hooks-spec.sh`), capability `hook_instrument` no registry.

- PEDIDO: `.model` e `.effort` de `${agent_transcript_path%.jsonl}.meta.json`, arquivo que o
  runtime grava ao lado do transcript do subagente. `.pickedEffortModel` do meta e registrado
  como `picked_effort_model`, so informativo, e NAO entra no julgamento.
- EFETIVO: `.message.model` da primeira linha `assistant` do transcript do subagente, ignorando
  `<synthetic>`, em leitura limitada (1 MiB e 400 linhas; o meta, 64 KiB). Nunca
  `transcript_path`, que e o do pai (ADR 0014).
- COMPARACAO: pedido e efetivo passam pela mesma normalizacao: minusculas; sem sufixo `[...]`
  (como `[1m]`); sem prefixo `anthropic.` ou `<regiao>.anthropic.` (`us`, `eu`, `apac`, `global`);
  sem sufixo `@AAAAMMDD`, `-vN`, `-vN:M` (Bedrock) ou `-AAAAMMDD`. Alias (`opus|sonnet|haiku|fable`,
  ja normalizado: `opus[1m]` vale `opus`) casa pela familia do ID efetivo, derivada por token (o
  que cobre `claude-3-5-sonnet-20241022`). ID completo (`claude-*`) exige igualdade exata dos IDs
  normalizados, comparados por inteiro: o truncamento a 128 caracteres vale so para o log, e ID
  acima de 256 caracteres vira `indeterminado/id_longo`. DECISAO sobre snapshots: datas
  diferentes da mesma versao e familia NAO sao divergencia, porque a substituicao procurada troca
  familia ou versao, e nao a data de snapshot de uma mesma versao; versao diferente
  (`claude-opus-4` contra `claude-opus-4-6`) diverge. `inherit`, vazio, null ou ausente:
  `sem_pedido`. Tipo errado (numero, array, objeto, booleano) ou valor fora do vocabulario:
  `pedido_desconhecido`. Transcript ou meta ausente ou ilegivel, sem linha assistant, caminho fora
  da raiz, ID longo ou payload ilegivel: `indeterminado`. Divergencia: `DIVERGE`.
- SAIDA: uma linha JSONL por evento em `${MODEL_HONOR_LOG:-~/.claude/logs/model-honor.jsonl}`,
  modo 0600, ASCII puro (U+2028 e U+2029 escapados), somente identificadores, nomes de modelo e
  motivo curto, com `pedido_origem` (`meta` ou `ausente`) e `rotacao` (`flock` ou `sem_flock`).
  Todo campo textual do payload e truncado a 256 caracteres (caminho: 4096) antes de montar o
  JSON; sem isso um campo acima de ~128 KiB derrubava o `jq --arg` e o DIVERGE sumia sem
  registro. Payload que o `jq` rejeita (por exemplo surrogate solitario) passa por saneamento com
  `perl`, quando existe, e, se ainda falhar, vira linha `indeterminado/payload_ilegivel` com so
  `payload_bytes` e `payload_sha12` (12 primeiros hex do sha256 do bruto), mais `systemMessage`.
- ROTACAO: a 2 MB, sob `flock` num arquivo de trava ao lado do log, com tres geracoes (`.1`,
  `.2`, `.3`); a quarta rotacao descarta a mais antiga. Sem `flock`, ou sem a trava em 5 s, grava
  sem rotacionar: nao descarta nada, mas o log cresce sem teto enquanto a rotacao nao ocorre.
- STDOUT: um unico `systemMessage` de no maximo 300 caracteres em quatro casos: DIVERGE; falha
  ao gravar o log (`model-honor: nao consegui gravar o log (<motivo>)`); payload ilegivel; `jq`
  ausente ou quebrado (texto fixo, escrito sem `jq`, para o desligamento do detector deixar
  rastro). Nos demais casos, nada.
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
  pedido->efetivo; controles, TAB, quebra de linha e U+2028/U+2029 em caminhos viram espaco).
  Exit 0 sem `DIVERGE`, 1 com, 2 em erro de uso ou de instrumento: `jq` que nao funciona,
  `jq` que falha nos filtros (contado como `jq_erro`), diretorio inexistente, nenhum meta
  encontrado, ou arquivo ou diretorio ilegivel (contado como `ilegivel`). Um `--since` que
  exclui tudo nao e erro (total 0, exit 0). O bloco termina com `exit` explicito e nunca le
  stdin. Permite medir o passivo historico sem depender de o hook ter estado ativo.

## Limites declarados

a. 56% dos metas reais nao trazem pedido (`sem_pedido`, inclui `inherit`; 858 de 1538 na
   varredura de 2026-11-16, comando na secao Reproducao). O hook nao julga o que nao foi pedido
   por parametro e nao le o frontmatter do agente. A refutacao viu `investigador`, cujo
   frontmatter atual declara `model: haiku`, rodar em `claude-opus-5-5` em 12 execucoes sem
   pedido no meta. O frontmatter vigente na epoca dessas execucoes pode ter sido outro: NAO
   VERIFICADO.
b. Os 124 eventos com `agent_type` vazio e sem transcricao nao sao julgaveis (resultam
   `indeterminado`), e a classe deles e desconhecida; pode incluir agentes de workflow: NAO
   VERIFICADO. O verificador nao recupera retroativamente o que o runtime apagou.
c. Teto de leitura: transcript cuja primeira linha assistant fica alem de 1 MiB ou da linha 400
   vira `indeterminado`, nunca falso `honrado`. Meta acima de 64 KiB vira `indeterminado`.
d. TOCTOU entre o `realpath` e a leitura: explora-la exige escrita do mesmo usuario em
   `~/.claude/projects`; risco residual baixo, aceito.
e. A entrega do `systemMessage` do SubagentStop ao operador nao foi medida. O log e a fonte
   primaria; o `systemMessage` e aviso adicional.
f. O hook so tem efeito sob instalacao managed. O ARQUIVO managed lido em 2026-11-16 declara
   `allowManagedHooksOnly=true`; o valor EFETIVO no runtime nao foi verificado (uma nota anterior
   registrava `false`). Hook declarado so no escopo de usuario nao roda se o valor efetivo for
   `true`. Em 2026-11-16 o hook nao estava em nenhum settings.
g. `pickedEffortModel` do meta tem semantica NAO verificada. Hipotese: modelo da sessao pai. A
   revisao independente reportou o cruzamento `meta.model | pickedEffortModel | efetivo` com
   `opus|claude-fable-5-2|claude-opus-5-5` x46 e `opus|claude-sonnet-5-5|claude-sonnet-5-5` x48
   [nao reproduzido por comando commitado]: o campo diverge do efetivo em parte dos casos, e por
   isso a hipotese de substituicao pela allowlist (secao "O defeito") tambem nao esta provada. O
   campo e so registrado, para correlacao futura.
h. Julga so a primeira mensagem assistant; troca de modelo no meio da execucao nao e vista.
i. A familia e o PRIMEIRO token de familia do ID (`claude-sonnet-opus-x` honra `sonnet`); IDs
   reais nao tem esse formato. Pedido com espaco (` opus`) e `pedido_desconhecido`, sem trim.
j. Regra 1 do ADR 0015 (hook novo so entra com evento REAL capturado como fixture): a suite
   alimenta o hook com tres formas reais de evento SubagentStop (tipo preenchido com transcript,
   outra conta, tipo vazio sem transcript), sanitizadas de `subagent-probe.jsonl`, em
   `tests/fixtures/model-honor/` (sem `last_assistant_message`, `cwd`, `prompt_id` nem texto;
   chaves reais e `effort` como objeto; o transcript e o meta sao fabricados so com o modelo).
   Isso cobre a FORMA do evento. O hook nao foi exercido contra um evento SubagentStop AO VIVO,
   porque nao esta instalado em nenhum settings: NAO VERIFICADO no runtime. Regra 3 do mesmo ADR:
   ver a secao Reproducao.
k. Trava de log presa por outro processo: cada hook espera ate 5 s, grava sem rotacionar, e o log
   cresce enquanto a trava estiver presa. O timeout de 10 s do hook em `install/hooks-spec.sh`
   cobre a espera, mas um disco travado faz cada SubagentStop sequencial pagar 5 s.

## Reproducao

Comandos que reproduzem cada numero citado. Os totais absolutos crescem com o corpus; os valores
esperados abaixo sao os de 2026-11-16.

1. Divergencia (`--scan`, exit 1 quando ha `DIVERGE`):
   `bash evidence/hooks/model-honor.sh --scan ~/.claude/projects`
   Esperado: linhas `status` com `DIVERGE` 54, `honrado` cerca de 620, `sem_pedido` cerca de
   860, `indeterminado` 3, e linhas `par` com `opus->claude-sonnet-5-5` 48 e
   `fable->claude-sonnet-5-5` 6. Com `--since 2026-11-13T05:00:00Z`: 48 DIVERGE
   `opus->claude-sonnet-5-5` e 19 `opus->claude-opus-5-5` honrados.
2. Eventos da sonda, com delimitador NAO branco (`IFS` de tab ou espaco colapsa campo vazio e ja
   produziu uma contagem errada, tratando o `agent_type` vazio como ausente):
   `cat ~/.claude/logs/subagent-probe.jsonl.1 ~/.claude/logs/subagent-probe.jsonl | jq -r 'select(.hook_event_name=="SubagentStop") | "\(.agent_type // "")|\(.agent_transcript_path // "")"' | while IFS='|' read -r t p; do [ -n "$t" ] && k=tipo || k=tipo_vazio; [ -e "$p" ] && e=com_transcript || e=sem_transcript; echo "$k $e"; done | sort | uniq -c`
   Esperado em 2026-11-16 (353 eventos): `tipo_vazio sem_transcript` 124 e `tipo com_transcript`
   229. Nenhum com `model`: o mesmo `jq` com `select(has("model"))` conta 0.
3. `allowManagedHooksOnly`: `jq '.allowManagedHooksOnly' /etc/claude-code/managed-settings.json`
   (arquivo, nao valor efetivo do runtime). Esperado em 2026-11-16: `true`.
4. Hook ausente de settings: `grep -c model-honor /etc/claude-code/managed-settings.json
   ~/.claude/settings.json`. Esperado em 2026-11-16: 0 nos dois.

## Verificacao

`tests/unit/model-honor.sh`: 33 casos, cada um protegendo um invariante nomeado no cabecalho da
suite. O controle positivo (caso 1, `opus` contra `claude-sonnet-5-5`) foi registrado como
vermelho pelo autor na sessao de 2026-11-16, antes de o hook existir; essa observacao nao e
reproduzivel a partir do diff.

Mutantes do hook (remocao de rotacao, trava e geracoes, tetos de leitura, familia, caixa,
normalizacao, sanitizacao, escopo e saida do scan, fronteira de `--since`, fallback ao transcript
do pai, raiz irma, tipo do meta, saneamento de surrogate, entre outros) foram aplicados para
conferir a suite: 59 de 62 morreram. Os 3 sobreviventes sao equivalentes: o `trap 'exit 0' EXIT` (todo
caminho do modo hook termina com `exit 0` explicito e nao ha `set -e`); a guarda de raiz do
transcript, coberta pela guarda de raiz do meta, derivado do mesmo caminho; e o teto de 300
caracteres do `systemMessage`, que os tetos por campo (40 e 80) nao deixam atingir na pratica.

## Referencias

- `evidence/hooks/model-honor.sh`, `tests/unit/model-honor.sh`, `tests/fixtures/model-honor/`.
- `install/hooks-spec.sh` (bloco `SubagentStop`), `orchestration/registry.json` (entrada
  `model-honor.sh`), `install/manifest.lock`, `scripts/status.sh` (enumera a suite).
- ADR 0014 (transcript do pai nunca e fonte; sonda permanente), ADR 0015 (regras 1 e 3).
