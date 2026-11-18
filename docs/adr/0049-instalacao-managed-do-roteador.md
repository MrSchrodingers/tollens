# ADR 0049 - Instalacao managed do roteador de modelos

Data: 2026-11-18
Estado: aceito como DESENHO. Nada foi instalado no sistema por esta onda: a aplicacao e do operador,
como root, conforme `docs/runbooks/roteador-instalacao.md`. O carregamento real do mod NUNCA foi
verificado (ver Limites).
Relaciona: ADR 0012 (guarda do Fable), ADR 0022 e 0026 (raiz de confianca e fronteira root),
ADR 0048 (model-honor), ADR 0050 (pending-ask). Fontes primarias do runtime copiadas para a sessao:
"Install your organization's mods" (mods-admin) e "Split a file-based policy across teams"
(managed-settings).

## Contexto

O roteador (`claude-plugins/plugins/tollens-router`, motor R1 e mod R2) so conta como mod da
organizacao se o Claude Code puder provar a origem: `enabledPlugins` com o plugin ligado,
marketplace declarado por caminho absoluto de diretorio em `extraKnownMarketplaces`, plugin listado
no marketplace por caminho relativo, e o diretorio gravavel so por administrador. Sem isso o mod
conta como de usuario e `allowManagedHooksOnly` o impede de carregar.

O `managed-settings.json` vivo (2026-11-18) NAO e o que o instalador gera: tem `availableModels`,
`deniedModels`, hooks de outro repositorio (`quality-gate`, `budget-guard`, `budget-count` em
`/opt/tollens/hooks` e `secret-guard` em `/opt/claude-harness`) e `allowManagedHooksOnly=true`. O
gerador anterior reescrevia o arquivo inteiro e trocava `/opt/tollens` por inteiro: aplicar o
instalador sobre o sistema vivo apagaria essas guardas e os modelos negados. Esta decisao trata isso
antes de acrescentar qualquer coisa.

## Decisao

### O que se instala (ordem)

1. Arvore de origem root:root em `/opt/.tollens-src` (ADR 0026; passo A0 do roteiro).
2. `apply-managed.sh` (deploy) monta tudo em staging e so entao troca:
   - `/opt/tollens/claude-plugins/` (tipo `plugin` do manifesto, diretorio inteiro): marketplace
     `tollens-tools` em `.claude-plugin/marketplace.json`, plugin `tollens-router` em
     `plugins/tollens-router` (fonte relativa). Modos exatos do ADR 0026 (0644/0755), root:root.
   - `/opt/tollens/hooks/*`: `model-honor.sh` (SubagentStop, ADR 0048) e `pending-ask.sh` (Stop,
     ADR 0050, nasce em `aviso`) ja constam de `install/hooks-spec.sh` e do manifesto.
   - `/etc/claude-code/managed-settings.json`: acrescenta `enabledPlugins`, `extraKnownMarketplaces`
     (`directory`, `/opt/tollens/claude-plugins`) e `prependPlugins=[tollens-router@tollens-tools,
     sec-default@builtin]`. O repositorio nao usa `managed-settings.d`; as chaves vao no arquivo que o
     instalador ja gera. O host tem `/etc/claude-code/managed-settings.d/60-ai-harness.json` (informado
     pelo operador em 2026-11-18; leitura direta nao feita por esta onda); o instalador nao o toca e ele
     e preservado. Um fragmento tambem nao serviria a liberacao do Opus: `deniedModels` e lista que
     COMBINA entre fontes (um fragmento nao remove entrada do arquivo base) [nao verificado: a afirmacao
     vem da leitura da documentacao do runtime, nao de teste com o runtime].
   - `/etc/claude-code/router-policy.json` (root:root 0644): politica embarcada, validada com
     `validatePolicy(politica, {now})` do motor instalado ANTES de qualquer escrita; reprovou, nada
     muda. Modo inicial `shadow`. Reaplicar preserva o `mode` ja instalado (o operador o muda no passo
     D) e renova o resto do conteudo.
3. Sentinela de desligamento `/etc/claude-code/router-off`: NAO e criada. Presente = `off`, lida a
   cada decisao (CONTRATO.md). Criar e remover exige root.

### Preservacao no settings vivo

Sobre arquivo ja marcado `_managed_by: tollens`, o gerador preserva toda chave que nao e dele
(`availableModels`, `deniedModels`, `env` alem das tres variaveis do instalador, etc.), preserva hooks
que a especificacao nao declara (e copia para a nova arvore os arquivos deles quando estao em
`/opt/tollens/hooks`) e nao rebaixa `allowManagedHooksOnly` de `true` para `false`. Sobre arquivo de
terceiro o comportamento antigo vale (backup `.pre-tollens`). Hook externo preservado nao e verificado
por `--verify` (nao esta no manifesto): a reconciliacao deles com o repositorio e pendencia aberta.
Backup datado `managed-settings.json.pre-roteador.<UTC>` so quando o conteudo muda.

O motor que valida a politica roda como root em raiz real: o instalador recusa um `node` que nao seja de
root ou esteja em diretorio gravavel por outros (`node_raiz`), e a recusa vale tambem para `sudo -E` e
`sudo env PATH=$PATH`. O operador instala um `node` root-owned em caminho de sistema (passo A0 do roteiro);
em 2026-11-18 o host so tem `node` em `~/.nvm`. A fonte da politica embarcada so aceita override
(`MANAGED_ROUTER_POLICY_SRC`) sob prefixo de ensaio, nunca em raiz real.

### Liberacao do Opus: passo separado

Decisao do operador (2026-11-16): Opus 5.5 permanente em `availableModels`; Fable so por sessao com
sentinela. `apply-managed.sh --liberar-opus` (com `--dry-run` para ensaio) altera SOMENTE
`availableModels` (acrescenta `claude-opus-5-5`, prefixo de versao do runtime) e `deniedModels`
(remove toda entrada que tem o TOKEN `opus`, onde token e cada sequencia `[a-z]+`: `opus`, `claude-opus-5`,
`opus[1m]`, `claude-opus-4-1`; `opusplan` fica). Entrada que tambem tem o token `fable` nunca sai
(ex.: `claude-fable-opus`). Fable permanece em `deniedModels` e fora de `availableModels`; o hook `fable-guard.sh` e a sentinela (ADR 0012) nao sao tocados. Backup
`managed-settings.json.pre-liberar-opus.<UTC>`. `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL=haiku` nao e
alterado: o d.ts diz que o modelo forcado pela sessao vence o do hook, entao agentes de workflow podem
seguir em haiku mesmo apos a liberacao (decisao do operador pendente, NAO VERIFICADO).

### Conflito de politica

A politica emite `opus` em T3 e T4; o managed nega `opus` ate a liberacao. Enquanto isso, toda decisao
de piso T3/T4 cai em `managed_nega_piso` e nada e aplicado (CONTRATO.md). Em `shadow` isso so aparece
no ledger. Por isso A (instalar) e B (liberar) sao separaveis e o enforce (D) so vem depois de B.

### Vencimento

`valid_until` da politica embarcada: 2026-11-30T00:00:00Z. Depois dessa data o motor aceita a politica
mas a degrada para `shadow` (o teste fixa `now=2026-12-01` e espera `shadow`). Renovar = editar
`valid_until` em `claude-plugins/plugins/tollens-router/router-policy.json`, regenerar o manifesto,
ressincronizar a arvore de origem e reaplicar (o `mode` instalado e mantido).

### Verificacao pos-instalacao

- `apply-managed.sh --verify`: conformidade do manifesto, incluindo o plugin (divergencia e ausencia
  acusadas; dono e gravabilidade medidos na raiz real).
- `model-honor.sh --scan ~/.claude/projects --since <instante da instalacao>`: exit 0 = nenhum
  divergente nem nao julgado; 1 = ha DIVERGE (pedido x efetivo); 3 = nada divergiu mas ha nao
  julgado; 2 = erro de uso ou de instrumento (ADR 0048). Antes da liberacao do Opus, exit 1 com
  `opus -> sonnet` e o estado conhecido (48 pares medidos em 2026-11-16); depois, o esperado e 0 ou 3.
- TESTE DE ACEITACAO do carregamento: em sessao nova, `claude plugin list` mostra `tollens-router`
  habilitado e, apos uma delegacao por Agent, existe `~/.claude/logs/router-ledger-*.jsonl` com
  linhas. Ledger vazio apos delegacoes = o mod nao carregou ou nao decide; nao avancar para enforce.

### Rollback

- Imediato: criar `/etc/claude-code/router-off` (mod passa a `off`).
- Roteador: `apply-managed.sh --revert-router` remove o plugin, a politica e as tres chaves de
  plugin; hooks e modelos ficam intactos.
- Opus: restaurar `managed-settings.json.pre-liberar-opus.<UTC>` (root, `cp -p`).
- Instalacao inteira: `managed-settings.json.pre-roteador.<UTC>` e `/opt/.tollens-src.prev`.
- `--revert` recusa por padrao (exit 1, nada removido) quando `.pre-tollens` nao tem
  `_managed_by == "tollens"`: o vivo e de 2026-08-12 (`_managed_by` `evidence-gate`, hooks em
  `/opt/evidence-gate`, inexistente) e restaura-lo substituiria a politica atual por uma antiga e
  removeria `/opt/tollens` (inclui hooks fora do repositorio). `--revert-forcar` restaura mesmo assim.
  A mensagem final do deploy deixou de sugerir `--revert`.
- Restauracao de backup do settings por copia para temporario no mesmo diretorio e `mv -f` (atomico).
- `--revert-router` deixa `--verify` vermelho (plugin ausente do manifesto); reaplicar o deploy corrige.
- Backup `cp -a /opt/tollens` e obrigatorio antes do passo A2 (roteiro, A0).

## Limites

- NAO VERIFICADO: o carregamento real do mod sob `allowManagedHooksOnly=true`. O contrato e a leitura
  da documentacao; nenhum `claude plugin list`, `--debug` nem ledger foi observado. O primeiro ledger
  nao vazio e o teste de aceitacao.
- NAO VERIFICADO: posse root:root e nao-gravabilidade pelo ator. A suite roda sobre prefixo temporario
  sem root; a garantia vem do `chown -R root:root` do staging e do `--verify` na raiz real (mecanismo
  ja existente, ADR 0026), e deve ser conferida por `--verify` apos a aplicacao.
- NAO VERIFICADO: que `claude-opus-5-5` em `availableModels` permita o alias `opus` na selecao do
  runtime (a documentacao descreve prefixo de versao; o alias nao foi exercitado).
- A arvore de origem protege o instalador, nao o autentica (ADR 0026, Limites).
- PENDENTE: `/opt/tollens/claude-plugins` leva tambem `tests/` e os mutantes do plugin, que nao sao
  politica. Excluir exigiria filtrar o digest em quatro pontos (`install/manifest.sh`, `dry_diff` e
  `conformidade_managed` do worker, e o teste I7) e a copia do staging; nao feito nesta onda para nao
  quebrar o digest que o `--verify` confere.
- NAO VERIFICADO: o aceite de um `node` root-owned em raiz real (o host nao tem um; a suite cobre a
  recusa e o predicado `node_raiz` sobre `/usr/bin/bash`, nao uma instalacao com `sudo`).

## Evidencia executavel

`tests/unit/managed-router.sh` (raiz temporaria; I1 a I8) e `tests/unit/managed.sh` (oraculo de
contagem atualizado para o tipo `plugin`).
