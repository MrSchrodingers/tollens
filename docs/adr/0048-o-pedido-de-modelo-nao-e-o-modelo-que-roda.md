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

A divergencia foi medida com o modo `--scan` deste hook sobre `~/.claude/projects` (comando 1 da
secao Reproducao). Em 2026-11-16, em varreduras independentes (revisao, refutacao e coordenacao;
hora nao registrada), o scan acusou 54 DIVERGE sobre cerca de 1540 a 1570 metas: 48
`opus -> claude-sonnet-5-5` e 6 `fable -> claude-sonnet-5-5`. O corpus e vivo: os totais crescem;
o que se espera de uma reexecucao e a mesma ordem de grandeza e os mesmos pares. A consequencia e
epistemica: o orquestrador delega uma revisao ou refutacao julgando que ela passou por um modelo
mais forte, e a evidencia que volta carrega um rotulo de capacidade que o runtime nao cumpriu.

## O que o payload entrega

Chaves de um evento real de SubagentStop: `agent_id`, `agent_transcript_path`, `agent_type`,
`background_tasks`, `cwd`, `effort`, `hook_event_name`, `last_assistant_message`,
`permission_mode`, `prompt_id`, `scratchpad_dir`, `session_crons`, `session_id`,
`stop_hook_active`, `transcript_path`. Fatos que governam o desenho (comando na secao Reproducao):

1. Nao existe campo `model`: em 2026-11-16 as 18:37, com o comando 2 da secao Reproducao, 470
   eventos SubagentStop em `~/.claude/logs/subagent-probe.jsonl` e `.1`, nenhum com `model`. A
   comparacao nao pode sair do payload.
2. `effort` e o objeto `{"level":"high"}` da sessao, nao do subagente; nao serve de pedido.
3. Na mesma medicao (2026-11-16 as 18:37): 158 eventos com `agent_type` vazio, todos sem
   transcricao em disco, e 312 com tipo preenchido e transcricao existente; nenhum evento com tipo
   vazio e transcricao, nem com tipo e sem transcricao. O log e vivo: os totais crescem, a
   estrutura se mantem. A classe dos eventos com tipo vazio e desconhecida.

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
  sem sufixo `@AAAAMMDD`, `-vN`, `-vN:M` (Bedrock), `-latest` ou `-AAAAMMDD`. Alias (`opus|sonnet|haiku|fable`,
  ja normalizado: `opus[1m]` vale `opus`) casa pela familia do ID efetivo, derivada por token (o
  que cobre `claude-3-5-sonnet-20241022`). ID completo (`claude-*`) exige igualdade exata dos IDs
  normalizados, comparados por inteiro: o truncamento a 128 caracteres vale so para o log, e ID
  acima de 256 caracteres vira `indeterminado/id_longo`. DECISAO sobre snapshots: datas
  diferentes da mesma versao e familia NAO sao divergencia, porque a substituicao procurada troca
  familia ou versao, e nao a data de snapshot de uma mesma versao; versao diferente
  (`claude-opus-4` contra `claude-opus-4-6`) diverge. O sufixo `-latest` e normalizado por
  analogia com os demais; nenhuma fonte primaria dele foi lida, e entre os cerca de 1570 metas
  reais so aparecem os pedidos `sonnet`, `opus`, `fable`, `haiku`, `inherit` e ausente. `inherit`, vazio, null ou ausente:
  `sem_pedido`. Tipo errado (numero, array, objeto, booleano) ou valor fora do vocabulario:
  `pedido_desconhecido`. Transcript ou meta ausente ou ilegivel, sem linha assistant, caminho fora
  da raiz, ID longo ou payload ilegivel: `indeterminado`. Efetivo sem prefixo `claude-` apos a
  normalizacao: a normalizacao toma o ultimo segmento depois de `/` (`anthropic/claude-...`, ARN de
  inference-profile ou foundation-model, `vertex/...`) e troca `.` por `-` (`claude-opus-4.5` vale
  `claude-opus-4-5`); persistindo sem prefixo, a FAMILIA ainda e derivada quando o ID tem um token
  `claude` e um token de familia. Se difere da pedida, `DIVERGE/familia_diferente` (o efetivo nao
  fica oculto); se coincide, ou se nao ha familia derivavel (ARN opaco, `opus-4-6`,
  `gpt-sonnet-9`), `indeterminado/efetivo_nao_reconhecido`. Divergencia: `DIVERGE`.
- SAIDA: uma linha JSONL por evento em `${MODEL_HONOR_LOG:-~/.claude/logs/model-honor.jsonl}`,
  modo 0600, ASCII puro (U+2028 e U+2029 escapados), somente identificadores, nomes de modelo e
  motivo curto, com `pedido_origem` (`meta` ou `ausente`) e `rotacao` (`flock` ou `sem_flock`).
  Todo campo textual do payload e truncado a 256 caracteres (caminho: 4096) antes de montar o
  JSON; sem isso um campo acima de ~128 KiB derrubava o `jq --arg` e o DIVERGE sumia sem
  registro. Payload que o `jq` rejeita (por exemplo surrogate solitario) passa por saneamento com
  `perl`, quando existe, e, se ainda falhar, vira linha `indeterminado/payload_ilegivel` com so
  `payload_bytes` e `payload_sha12` (12 primeiros hex do sha256 do bruto), mais `systemMessage`.
  `jq` que passa a sonda e o `type` mas falha nos filtros de extracao (o mesmo controle do
  `--scan`) vira `indeterminado/jq_filtro_falhou` mais `systemMessage`. `jq` que falha so no
  programa de extracao do payload (menos de 4 campos devolvidos) vira
  `indeterminado/jq_extracao_falhou`, mais `systemMessage`. Stdin com mais de um valor JSON: julga
  o primeiro OBJETO com `agent_transcript_path` (pula `{}`, numeros, arrays e strings) e registra
  `payload_multiplo: true`, mais aviso; sem nenhum objeto com caminho, `indeterminado/payload_sem_caminho`.
- ROTACAO: a 2 MB, sob `flock` num arquivo de trava ao lado do log, com tres geracoes (`.1`,
  `.2`, `.3`); a quarta rotacao descarta a mais antiga. Sem `flock`, ou sem a trava em 5 s, grava
  sem rotacionar: nao descarta nada, mas o log cresce sem teto enquanto a rotacao nao ocorre.
- STDOUT: um unico `systemMessage` de no maximo 300 caracteres nestes casos: DIVERGE; falha ao
  gravar o log; payload ilegivel; payload com varios valores (`payload_multiplo`); payload sem
  objeto com caminho (`payload_sem_caminho`); `jq` que falha nos filtros (`jq_filtro_falhou`) ou
  na extracao (`jq_extracao_falhou`); caminho fora da raiz (`caminho_fora_da_raiz`, tentativa de
  escape); `jq` ausente ou quebrado (texto fixo, escrito sem `jq`, para o desligamento do detector
  deixar rastro). Nos demais casos, nada: os outros `indeterminado` (meta ou transcript ausente
  ou ilegivel, sem linha assistant, ID longo, efetivo nao reconhecido) so vao ao log.
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
  Exit 0 quando nada divergiu e nada ficou nao julgado; 1 com `DIVERGE`; 3 quando nada divergiu
  mas ha `indeterminado` ou `pedido_desconhecido` (o resumo `NAO JULGADOS n de total` e a contagem
  por motivo vao ao stderr, e linhas `motivo` ao stdout), ou quando NENHUM evento foi julgado
  (`honrado` + `DIVERGE` == 0 com total > 0, so `sem_pedido`: mensagem `NENHUM JULGADO`);
  `sem_pedido` com pelo menos um julgado nao conta como incompletude (limite a), mas aparece no
  resumo; 2 em erro de uso ou de instrumento, com precedencia
  2 > 1 > 3 > 0: `jq` que nao funciona,
  `jq` que falha nos filtros (contado como `jq_erro`), diretorio inexistente, nenhum meta
  encontrado, ou arquivo, diretorio ou symlink ilegivel (contado como `ilegivel`). O argumento e
  os symlinks de projeto e de sessao sao resolvidos (`find -L`, alvo vira raiz permitida); symlink
  quebrado ou em laco conta como `ilegivel`. Symlink em `subagents` ou no `.meta.json` e resolvido
  por `realpath`: dentro das raizes permitidas, segue; fora delas (ou quando o nome resolvido nao
  casa `*/subagents/agent-*.jsonl`), conta como `ilegivel` e o exit e 2. `--since` vazio e erro de uso (exit 2); um `--since`
  que exclui tudo nao e erro (total 0, exit 0). O bloco termina com `exit` explicito e nunca le
  stdin. Permite medir o passivo historico sem depender de o hook ter estado ativo.

## Limites declarados

a. 56% dos metas reais nao trazem pedido (`sem_pedido`, inclui `inherit`; cerca de 56% dos metas
   na varredura de 2026-11-16, comando 1 da secao Reproducao). O hook nao julga o que nao foi pedido
   por parametro e nao le o frontmatter do agente. A refutacao viu `investigador`, cujo
   frontmatter atual declara `model: haiku`, rodar em `claude-opus-5-5` em 12 execucoes sem
   pedido no meta. O frontmatter vigente na epoca dessas execucoes pode ter sido outro: NAO
   VERIFICADO.
b. Os eventos com `agent_type` vazio e sem transcricao (158 em 2026-11-16 as 18:37) nao sao julgaveis (resultam
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
   `session_id` e `agent_id` trocados por identificadores sinteticos de mesma forma e tamanho;
   chaves reais e `effort` como objeto; o transcript e o meta sao fabricados so com o modelo).
   Isso cobre a FORMA do evento. O hook nao foi exercido contra um evento SubagentStop AO VIVO,
   porque nao esta instalado em nenhum settings: NAO VERIFICADO no runtime. Regra 3 do mesmo ADR:
   cada numero tem comando na secao Reproducao e os mutantes tem script em
   `tests/mutation/model-honor/`. As fixtures de commits anteriores desta mudanca continham os
   identificadores reais no historico do git; este commit os remove da arvore, nao do historico.
o. Caminho relativo em `agent_transcript_path` e resolvido contra o cwd do processo do hook, que
   o runtime define; o caminho resultante ainda passa pela guarda de raiz, entao um relativo que
   cai fora das raizes vira `caminho_fora_da_raiz`, mas o que um relativo valido significa depende
   do cwd (nao medido).
p. O mutante `G4_trap` (remover o `trap 'exit 0' EXIT`) sobrevive. A razao e por construcao (todo
   caminho do modo hook termina com `exit 0` explicito e nao ha `set -e`), mas nenhuma entrada que
   provoque erro interno foi encontrada para provar a equivalencia: NAO VERIFICADO.
q. Os achados m3 e m4 da quinta revisao independente foram entregues a esta mudanca so como
   "limites a registrar", sem o texto do achado; nao ha o que descrever aqui sem inventar: NAO
   VERIFICADO.
r. Publicacao: as fixtures de `tests/fixtures/model-honor/` nos commits `c773ae4`, `1d33f83` e
   `77cba2b` guardam identificadores reais de sessao e de agente; a arvore final ja os trocou por
   sinteticos. Publicar exige squash para uma branch nova a partir da base com a arvore final;
   o historico desta branch nao deve ser publicado como esta. A decisao de quando e como fazer o
   squash e do momento do push.
k. Trava de log presa por outro processo: cada hook espera ate 5 s, grava sem rotacionar, e o log
   cresce enquanto a trava estiver presa. O timeout de 10 s do hook em `install/hooks-spec.sh`
   cobre a espera, mas um disco travado faz cada SubagentStop sequencial pagar 5 s.
l. `-latest` e normalizado por analogia, sem fonte primaria lida. Efeito colateral conhecido, nao
   alterado: pedido `claude-opus-latest` contra efetivo `claude-opus-4-6` DIVERGE (o alias nao
   tem versao), e a existencia desse alias nao foi verificada. Nenhum meta real usa `-latest`: so
   aparecem `sonnet`, `opus`, `fable`, `haiku`, `inherit` e ausente (medicao do coordenador em
   2026-11-16, hora nao registrada; cerca de 1570 metas).
m. Cerca de 56% dos metas reais nao trazem pedido (limite a). A solucao de fundo nao e este hook:
   e um registro do roteador de modelos (o ledger do PRD do roteador) que grave o modelo pedido e
   o efetivo no momento do disparo, em vez de inferi-los depois dos arquivos de transcript.
n. Symlink dentro da arvore varrida pelo `--scan` que resolve para fora das raizes permitidas nao e
   seguido: conta como `ilegivel` e o resultado e rejeitado (exit 2). Quem varre uma arvore com
   symlinks para fora precisa passar cada raiz como argumento.

## Reproducao

Comandos que reproduzem cada numero citado. O corpus e os logs sao vivos: os totais absolutos
crescem; cada valor abaixo traz a data e a hora em que foi obtido.

1. Divergencia (`--scan`: exit 1 quando ha `DIVERGE`, 3 quando nada divergiu mas ha nao julgados,
   0 quando tudo foi julgado e nada divergiu):
   `bash evidence/hooks/model-honor.sh --scan ~/.claude/projects`
   Esperado: linhas `status` com `DIVERGE` (54 em 2026-11-16, hora nao registrada), `honrado`,
   `sem_pedido` (cerca de 56% do total), `indeterminado` (3), e linhas `par` com
   `opus->claude-sonnet-5-5` (48) e `fable->claude-sonnet-5-5` (6). Com
   `--since 2026-11-13T05:00:00Z`: 48 DIVERGE `opus->claude-sonnet-5-5` e 19
   `opus->claude-opus-5-5` honrados (coordenacao, 2026-11-16, hora nao registrada).
   Medido com este hook em 2026-11-17 as 14:19, `--since 2026-11-13T05:00:00Z`: exit 1, `total` 239,
   `DIVERGE` 48, `honrado` 77, `sem_pedido` 114 (O corpus e vivo; o valor de DIVERGE e o que se
   compara).
2. Eventos da sonda, com delimitador NAO branco (`IFS` de tab ou espaco colapsa campo vazio e ja
   produziu uma contagem errada, tratando o `agent_type` vazio como ausente):
   `cat ~/.claude/logs/subagent-probe.jsonl.1 ~/.claude/logs/subagent-probe.jsonl | jq -r 'select(.hook_event_name=="SubagentStop") | "\(.agent_type // "")|\(.agent_transcript_path // "")"' | while IFS='|' read -r t p; do [ -n "$t" ] && k=tipo || k=tipo_vazio; [ -e "$p" ] && e=com_transcript || e=sem_transcript; echo "$k $e"; done | sort | uniq -c`
   Obtido em 2026-11-16 as 18:37: `tipo com_transcript` 312 e `tipo_vazio sem_transcript` 158.
   Nenhum com `model`: o mesmo `jq` com `select(has("model"))` conta 0 (idem, 18:37).
3. `allowManagedHooksOnly`: `jq '.allowManagedHooksOnly' /etc/claude-code/managed-settings.json`
   (arquivo, nao valor efetivo do runtime). Obtido em 2026-11-16 as 18:37: `true`.
4. Hook ausente de settings: `grep -c model-honor /etc/claude-code/managed-settings.json
   ~/.claude/settings.json`. Obtido em 2026-11-16 as 18:37: 0 nos dois.
5. Mutantes: `bash tests/mutation/model-honor/run-all.sh` (ver o README do diretorio; imprime uma
   linha por mutante e o resumo). Sobre o hook de 86d3190, obtido em 2026-11-16 as 18:50:
   `MORTOS=68 DE=71`, vivos so os 3 equivalentes declarados, exit 0. Sobre o hook atual, ver a
   secao Verificacao.

## Verificacao

`tests/unit/model-honor.sh`: 49 casos, cada um protegendo um invariante nomeado no cabecalho da
suite. O controle positivo (caso 1, `opus` contra `claude-sonnet-5-5`) foi registrado como
vermelho pelo autor na sessao de 2026-11-16, antes de o hook existir; essa observacao nao e
reproduzivel a partir do diff.

Mutantes do hook (remocao de rotacao, trava e geracoes, tetos de leitura, familia, caixa,
normalizacao, sanitizacao, escopo e saida do scan, fronteira de `--since`, fallback ao transcript
do pai, raiz irma, tipo do meta, saneamento de surrogate, entre outros) foram aplicados para
conferir a suite. Sobre o hook de 2026-11-16 (commit 86d3190), `run-all.sh` deu `MORTOS=68 DE=71`
(exit 0, 2026-11-16 as 18:50). Naquela data tres mutantes sobreviventes foram declarados
equivalentes; a declaracao de `W_roottranscript` (remover a guarda de raiz do transcript) estava
ERRADA: com o transcript fora das raizes e o `.meta.json` como symlink para um meta dentro delas,
o hook correto da `indeterminado/caminho_fora_da_raiz` e o mutante le o transcript de fora e da
`DIVERGE`. O caso 46 da suite o mata, e o mutante deixou de ser equivalente. Restam dois
sobreviventes declarados: o `trap 'exit 0' EXIT` (`G4_trap`; todo caminho do modo hook termina
com `exit 0` explicito e nao ha `set -e`, mas a equivalencia segue NAO VERIFICADA, limite p) e o
teto de 300 caracteres do `systemMessage` (`U_msgcap`), que os tetos por campo (40 e 80) nao
deixam atingir na pratica.
Sobre o hook de a98eb3f, os 5 mutantes acrescentados (`mx1_controle_efet`, `D1b_extracao`,
`D2d_naoobjeto`, `D2e_semcaminho`, `R3_foraraiz`) morreram nos casos 41, 39, 40, 40 e 38
(2026-11-17 as 11:08). O gerador passou a produzir 81 mutantes (acrescentados `M5_id`,
`M1_exit3`, `M1_pd`, `M1_resumo`, `M2_escape`) e o executor passou a classificar `morto` so com
caso FAIL nomeado (`inconclusivo` para rc != 0 sem caso: timeout 124, contagem inesperada,
dependencia ausente), gravando cada linha ao terminar. A execucao completa sobre o hook atual NAO
foi concluida (carga da maquina): NAO VERIFICADO; nao se reemite "N de 81".
Nesta rodada o gerador passou a 88 mutantes e o executor roda `bash -n` em cada um antes (sintaxe
quebrada e `inconclusivo`, nunca morto; controle `SYN_sintaxe`) e um baseline com o hook intacto
(se falhar, o executor aborta com exit 2). A execucao completa dos 88 mutantes sobre o hook atual NAO foi feita nesta rodada: o load average ficou entre 21 e 52 (a regra era rodar so abaixo de 25) e o prazo nao cabia; NAO VERIFICADO, e nao se reemite "N de M".
Rotacao sob 150 hooks concorrentes com tres geracoes pre-existentes (2026-11-17 as 11:09):
150 de 150 eventos distintos preservados e marcas A, B e C em `.1`, `.2` e `.3`.

## Referencias

- `evidence/hooks/model-honor.sh`, `tests/unit/model-honor.sh`, `tests/fixtures/model-honor/`.
- `install/hooks-spec.sh` (bloco `SubagentStop`), `orchestration/registry.json` (entrada
  `model-honor.sh`), `install/manifest.lock`, `scripts/status.sh` (enumera a suite).
- ADR 0014 (transcript do pai nunca e fonte; sonda permanente), ADR 0015 (regras 1 e 3).
