# Roteiro do operador - instalacao managed do roteador de modelos

Base: ADR 0049. Branch: `onda34-roteador-instalacao` do repositorio `/home/ti/evidence-gate`
(worktree `/home/ti/wt/evidence-gate-r3`). Nada daqui foi executado no sistema por quem escreveu o
roteiro. Onde o roteiro diz "root", rode no seu terminal. Cada passo diz o que esperar; se a saida
diferir, pare e nao avance.

Estado de partida conhecido (2026-11-18): `/etc/claude-code/managed-settings.json` marcado
`_managed_by: tollens`, `allowManagedHooksOnly=true`, `availableModels=[sonnet,haiku]`,
`deniedModels=[opus,fable,claude-opus-5,claude-fable-5]`; `/opt/tollens/hooks` contem
`quality-gate.sh`, `budget-guard.sh` e `budget-count.sh`, que NAO estao no repositorio; o instalador
novo os preserva (ADR 0049), mas confira no ensaio.

## Passo A - instalar em shadow (sem mudar modelos)

### A0. Pre-requisitos

**Node de root.** O instalador valida a politica do roteador com o motor (`node`) e, como root, RECUSA um
`node` que nao seja de root ou que esteja em diretorio gravavel por outros (ADR 0049). O `node` do seu
usuario (nvm, `/home/ti/.nvm/...`) nao serve, e nunca use `sudo -E` nem `sudo env PATH=$PATH` para
contornar: isso poria codigo do ator para rodar como root. Em 2026-11-18 o host NAO tem `node` em
caminho de sistema (`/usr/bin/node` e `/usr/local/bin/node` ausentes); instale-o pelo gerenciador de
pacotes da distribuicao (por exemplo `sudo dnf install nodejs`) ANTES do passo A2.

```
sudo sh -c 'command -v node'                                      # esperado: um caminho de sistema, ex. /usr/bin/node
sudo stat -L -c '%U:%G %a %n' "$(sudo sh -c 'command -v node')"   # esperado: root:root, modo sem escrita de grupo/outros
```

Saida vazia, ou dono diferente de `root`: PARE. Caso de teste do pre-requisito: sem `node` de root, o
passo A2 deve terminar com exit 1 ANTES de `committed`, com mensagem sobre `node` (ausente ou nao
root-owned) e nada alterado (`--verify` igual ao de antes). Se voce instalou e mesmo assim for
recusado, o `node` achado pelo `sudo` e outro: confira o `command -v` acima.

**Backup da arvore ativa (OBRIGATORIO).** A troca de `/opt/tollens` descarta o que nao esta no manifesto
nem e referenciado por hook registrado. Sem esta copia nao ha ponto de volta da arvore:

```
sudo cp -a /opt/tollens /opt/tollens.bak-$(date -u +%Y%m%d)
sudo ls -ld /opt/tollens.bak-*                                    # esperado: o diretorio recem criado
```

Nao avance sem o `ls` mostrar o backup.

### A0b. Sincronizar a arvore de origem root:root (ADR 0026), POR HASH

O instalador, quando roda como root, recusa uma fonte que nao seja inteira root:root, sem symlink e
sem escrita de grupo/outros (exit 78). A fonte e `/opt/.tollens-src`. Monte uma nova ao lado e troque.
O snapshot e arquivado e verificado pelo HASH do commit, nao pelo nome da branch: a branch pode andar
entre o ensaio e o `archive`. Confira o hash com o que a revisao informou antes de seguir.

```
# terminal do operador (sem root)
H="$(git -C /home/ti/evidence-gate rev-parse --verify 'onda34-roteador-instalacao^{commit}')"; echo "$H"
git -C /home/ti/evidence-gate log -1 --format='%H %s' "$H"     # esperado: o hash e o assunto revisados
git -C /home/ti/evidence-gate archive --format=tar -o "$HOME/tollens-src-$H.tar" "$H"
git get-tar-commit-id < "$HOME/tollens-src-$H.tar"             # esperado: igual a $H

ls -d /opt/.tollens-src.new /opt/.tollens-src.prev 2>&1        # esperado: "No such file" nos dois

sudo mkdir /opt/.tollens-src.new
sudo tar -x -C /opt/.tollens-src.new --no-same-owner < "$HOME/tollens-src-$H.tar"
printf '%s\n' "$H" | sudo tee /opt/.tollens-src.new/.commit-publicado >/dev/null
sudo chown -R root:root /opt/.tollens-src.new
sudo chmod -R go-w /opt/.tollens-src.new
sudo find /opt/.tollens-src.new \( -type l -o \! -user root -o \! -group root -o -perm /022 \) -print -quit
#   esperado: nenhuma linha

sudo mv /opt/.tollens-src /opt/.tollens-src.prev && sudo mv /opt/.tollens-src.new /opt/.tollens-src
cat /opt/.tollens-src/.commit-publicado                        # esperado: igual a $H
```

`git archive` leva so arquivos rastreados (sem `.git`, sem cache). O snapshot anterior fica em
`/opt/.tollens-src.prev` (contem `id_mines`, chave privada nao rastreada: decida o destino dela; nao e
escopo deste roteiro). O `.tar` em `$HOME` pode ser apagado depois.

### A1. Ensaio (sem root, nao escreve nada)

```
bash /opt/.tollens-src/install/apply-managed.sh --dry-run
```

Antes de aplicar, confira a validade da politica embarcada (B4): `valid_until` e 2026-11-30T00:00:00Z.

```
jq -r .valid_until /opt/.tollens-src/claude-plugins/plugins/tollens-router/router-policy.json
date -u +%Y-%m-%dT%H:%M:%SZ
```

Se a data de hoje for igual ou posterior a `valid_until`, o motor degrada a politica para `shadow`: renove
antes (ADR 0049, secao Vencimento) em vez de reaplicar.

Esperado: `PLANO (nada sera escrito)`, depois `=== DIFF do que mudaria`. Confira:

- secao `hooks externos preservados`: `quality-gate.sh`, `budget-guard.sh`, `budget-count.sh` (em
  `/opt/tollens/hooks`) e `/opt/claude-harness/hooks/secret-guard.sh`: 4 comandos. Se faltar algum, PARE.
- diff do `managed-settings.json`: acrescimos `enabledPlugins`, `extraKnownMarketplaces`,
  `prependPlugins`; hooks `model-honor.sh` (SubagentStop) e `pending-ask.sh` (Stop) novos; nenhuma
  linha de `availableModels` ou `deniedModels` mudando; `allowManagedHooksOnly` continua `true`.
  O diff TAMBEM mostra reordenacao de grupos de hook, nao so acrescimos: `quality-gate.sh` sai do
  grupo do Stop (o `pending-ask.sh` ocupa o lugar dele) e vira grupo proprio, `budget-count.sh` sai do grupo do SubagentStart, e
  `budget-guard.sh` muda de posicao no PreToolUse. Os comandos sao os mesmos; muda o agrupamento (o
  runtime executa todos). Comando que SUMA do diff (nao so mude de grupo): PARE.
- `INSTALA claude-plugins` e `router-policy.json` novo.

### A2. Aplicar

```
sudo bash /opt/.tollens-src/install/apply-managed.sh
```

Esperado: `hook externo preservado: ...` (3 linhas: os tres hooks em `/opt/tollens/hooks`; o
`secret-guard.sh` fica fora de `/opt/tollens`, nao e copiado e nao gera linha), `managed: N componentes | 0 divergentes | 0 com
dono errado | 0 gravaveis pelo ator` e `managed transaction committed`, exit 0. Falha antes de
`committed`: nada ativo foi alterado (staging descartado; politica e arvore anteriores restauradas).
Backup criado: `/etc/claude-code/managed-settings.json.pre-roteador.<UTC>`.

### A3. Conferir

```
bash /opt/.tollens-src/install/apply-managed.sh --verify; echo exit=$?
ls -l /etc/claude-code/router-policy.json /etc/claude-code/router-off
jq -r .mode /etc/claude-code/router-policy.json
```

Esperado: `ESTADO: politica fora do espaco de escrita do ator`, `exit=0`; `router-policy.json`
`root root -rw-r--r--`; `router-off` AUSENTE (`No such file`); modo `shadow`.

## Passo B - liberar o Opus (separado; so depois de A conferido)

```
bash /opt/.tollens-src/install/apply-managed.sh --liberar-opus --dry-run
sudo bash /opt/.tollens-src/install/apply-managed.sh --liberar-opus
jq -c '{availableModels, deniedModels}' /etc/claude-code/managed-settings.json
```

Esperado no ensaio: apenas `claude-opus-5-5` acrescentado a `availableModels` e `opus` e
`claude-opus-5` removidos de `deniedModels`. Depois de aplicar: `deniedModels` com `fable` e
`claude-fable-5`; backup `/etc/claude-code/managed-settings.json.pre-liberar-opus.<UTC>`. O Fable
segue por sentinela de sessao (ADR 0012), sem mudanca. Reaplicar e no-op (`Opus ja liberado`).
O `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL=haiku` nao muda (ver ADR 0049, decisao pendente).

## Passo C - verificacao pos-instalacao

Em sessao NOVA do Claude Code (managed so e lido na partida):

1. `claude plugin list` deve listar `tollens-router@tollens-tools` habilitado. Alternativa:
   `claude --debug` e procurar a linha `hooks module` do mod com `tier prepend`.
2. Delegue uma tarefa por Agent (qualquer) e confira o ledger:
   `ls -l ~/.claude/logs/router-ledger-*.jsonl*` e
   `cat ~/.claude/logs/router-ledger-*.jsonl | jq -r '[.evento,.modo_efetivo]|@tsv' | sort | uniq -c`.
   Ledger ausente ou vazio apos delegacoes: o mod NAO carregou (nunca foi verificado). Nao avance;
   rode `claude --debug`, guarde a saida e use o rollback se preciso.
3. Escopo do model-honor, a partir do instante da instalacao (ajuste a data):
   `bash /opt/tollens/hooks/model-honor.sh --scan ~/.claude/projects --since 2026-11-18T00:00:00Z; echo exit=$?`
   Exit 0 = ok; 1 = ha DIVERGE (pedido x efetivo); 3 = nada divergiu mas ha nao julgado; 2 = erro de
   uso ou instrumento. Antes do passo B, exit 1 com pares `opus -> sonnet` e esperado. Depois do B,
   subagentes novos que pedem `opus` devem honrar: espere 0 ou 3.
4. `bash /opt/.tollens-src/install/apply-managed.sh --verify` de novo (exit 0). Exceto depois de
   `--revert-router`: o manifesto continua exigindo o plugin, entao o `--verify` sai com exit 1, uma linha
   `AUSENTE /opt/tollens/claude-plugins` e `1 divergentes`. Esse e o estado esperado de um roteador
   removido, nao falha do restante; volta a exit 0 reaplicando o deploy (que reinstala o roteador).

## Passo D - ligar enforce: BLOQUEADO ate haver calibracao medida

**Nao execute este passo com a politica embarcada.** Em `enforce` o motor exige que todo nivel EMITIVEL
(hoje T2, T3 e T4; T0 e T1 tem `emitivel: false`) tenha `quality.por_nivel.<Tn>` medido: `n` maior ou
igual a `limites.n_minimo` (padrao 8) e `aprovacao_medida` maior ou igual ao piso do papel
(`piso_aprovacao.default` 0.8; 0.9 para refutador, revisor-codigo e auditor-seguranca), com a `fonte` da
medicao. A politica embarcada tem `aprovacao_medida: null` e `n: null` nos cinco niveis: com `mode=enforce`
o `validatePolicy` devolve `degradaPara: shadow` e o motor decide em `shadow` (razao `nivel_nao_medido`).
O instalador nao muda isso, e a trava abaixo existe para impedir um `enforce` que so parece ligado.

O que a calibracao exige, antes de qualquer comando:

1. Medir a aprovacao por nivel T2, T3 e T4 (taxa de aprovacao pelo revisor sobre resultados de cada nivel,
   com `n` e `fonte` registrados). Esse trabalho (calibracao R6) esta no BACKLOG e NAO foi feito: nao ha
   medicao nem limiar justificado nesta onda.
2. Gravar os valores medidos em `quality.por_nivel` de
   `claude-plugins/plugins/tollens-router/router-policy.json` no repositorio, regenerar
   `install/manifest.lock`, ressincronizar a fonte (A0b) e reaplicar o deploy (o `mode` instalado e mantido).
3. Conferir `valid_until`: a politica embarcada vence em 2026-11-30T00:00:00Z. Politica vencida degrada a
   `shadow` mesmo em `enforce`, sem alerta. Renove antes (ADR 0049, secao Vencimento).
4. Criterio proposto de observacao (limiares sao decisao do operador): pelo menos 7 dias corridos em
   `shadow` com o ledger crescendo (item C2) e pelo menos 50 linhas `tool.call`; passo B aplicado e, desde
   ele, nenhuma razao `managed_nega_piso`
   (`cat ~/.claude/logs/router-ledger-*.jsonl* | jq -r '.reasons[]?' | sort | uniq -c | sort -rn`);
   nenhuma razao `persistencia_falhou`; `model-honor --scan --since <data do B>` com exit 0 ou 3.

Comando (root; so depois dos itens 1 a 4; valida com o motor instalado, por `env -i` e PATH fixo, e troca de
forma atomica; o `node` e o de root do passo A0; o `trap` remove `.router-policy.novo` se qualquer etapa
falhar). A trava impede o `enforce` com politica vencida ou degradada: o `validatePolicy` reprova se
`degradaPara` vier preenchido, e nada e trocado. Com a politica embarcada atual ele SEMPRE reprova; isso e
o comportamento esperado enquanto o passo estiver bloqueado.

```
sudo bash -c '
set -euo pipefail
cd /etc/claude-code
trap "rm -f .router-policy.novo" EXIT
jq ".mode=\"enforce\"" router-policy.json > .router-policy.novo
/usr/bin/env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin node --input-type=module -e "
const [, pol, eng] = process.argv;
const fs = await import(\"node:fs\");
const { validatePolicy } = await import(eng);
const r = validatePolicy(JSON.parse(fs.readFileSync(pol, \"utf8\")), { now: Date.now() });
if (!r.ok || r.degradaPara) { console.error(JSON.stringify(r)); process.exit(1); }
" .router-policy.novo file:///opt/tollens/claude-plugins/plugins/tollens-router/engine.mjs
chmod 0644 .router-policy.novo; chown root:root .router-policy.novo
mv -f .router-policy.novo router-policy.json
jq -r .mode router-policy.json
'
```

Esperado (so desbloqueado): imprime `enforce`. Reaplicar o instalador depois preserva `enforce`. Para voltar:
mesmo comando com `\"shadow\"` (e sem a validacao de degradacao).

## Rollback

| Quero | Comando (root) |
|---|---|
| Desligar o mod agora | `sudo touch /etc/claude-code/router-off` (religar: `sudo rm /etc/claude-code/router-off`) |
| Voltar a shadow | passo D com `shadow` |
| Remover o roteador (plugin, politica, 3 chaves) | `sudo bash /opt/.tollens-src/install/apply-managed.sh --revert-router` |
| Voltar a restringir o Opus | procedimento R1 abaixo, com `<backup>` = `managed-settings.json.pre-liberar-opus.<UTC>` |
| Voltar ao settings anterior a instalacao | procedimento R1 abaixo, com `<backup>` = `managed-settings.json.pre-roteador.<UTC>` (a arvore nova em `/opt/tollens` preserva os hooks externos referenciados; restaure-a de `/opt/tollens.bak-<data>` so se faltar arquivo) |
| Voltar a arvore de origem | `sudo mv /opt/.tollens-src /opt/.tollens-src.novo && sudo mv /opt/.tollens-src.prev /opt/.tollens-src` |

**Procedimento R1 (restaurar um backup do settings, atomico).** Copia para arquivo temporario no mesmo
diretorio e troca por `mv -f` (`rename(2)`): o arquivo vivo nunca fica meio escrito, e o temporario e
removido se a copia falhar. Nao use `cp` direto sobre `managed-settings.json`.

```
sudo bash -c 'set -euo pipefail
d=/etc/claude-code/managed-settings.json
bk=/etc/claude-code/<backup>
tmp="$d.rb.$$"
trap "rm -f \"$tmp\"" EXIT
cp -p "$bk" "$tmp"
jq -e . "$tmp" >/dev/null
mv -f "$tmp" "$d"'
jq -c '{availableModels, deniedModels}' /etc/claude-code/managed-settings.json
```

`apply-managed.sh --revert` RECUSA por padrao (exit 1, nada removido) quando
`/etc/claude-code/managed-settings.json.pre-tollens` nao tem `_managed_by == "tollens"`. O `.pre-tollens`
vivo e de 2026-08-12, tem `_managed_by` `evidence-gate` e aponta hooks para `/opt/evidence-gate/hooks`,
que nao existe em `/opt`: restaura-lo substituiria a politica atual por uma antiga e removeria
`/opt/tollens` por inteiro (inclui `quality-gate.sh`, `budget-guard.sh` e `budget-count.sh`, que nao
estao no repositorio). Para desfazer so o roteador use `--revert-router`. `--revert-forcar` restaura
mesmo assim e so deve ser usado depois de ler o `.pre-tollens`; nao faz parte deste roteiro.
O `--revert-router` deixa o `--verify` vermelho (ver C4); reaplicar o deploy o reinstala.
O backup da arvore (`/opt/tollens.bak-<data>`, passo A0) e o unico ponto de volta de `/opt/tollens`.

## O que este roteiro NAO prova

Continuam NAO VERIFICADOS por execucao (nada disso foi observado em maquina real):

- a carga do mod `tollens-router` sob `allowManagedHooksOnly=true`;
- o comportamento do runtime quando a carga do plugin FALHA (se os hooks managed seguem ou nao);
- o `env_keep` e o `secure_path` do `sudoers` do host: o roteiro usa `sudo` simples e nao os inspeciona;
- o efeito do alias `opus` sobre `claude-opus-5-5` na selecao de modelo;
- a aceitacao de um `node` root-owned em raiz real (o host so tem `node` em `~/.nvm`);
- a posse root:root em raiz real (o `--verify` do passo A3 a mede).

O passo C e o aceite: ledger nao vazio apos delegacoes em sessao nova e `claude plugin list` com o plugin
habilitado. Sem isso, nada acima esta provado.
