# ADR 0023 - O que a execucao encontrou, e a leitura nao

- Data: 2026-08-04
- Status: aceito
- Sessao: fechamento da Fase 1 (M2 -> M3), a partir de `docs/HANDOFF.md`
- Complementa: 0022 (fecha a condicao de refutacao declarada la)

## O achado que organiza este ADR

O handoff previa cinco itens de P0/P1/P2 e nenhum defeito. A sessao fechou os itens e encontrou
**oito defeitos**, todos por EXECUCAO. Nenhum por leitura de codigo, nenhum por revisao.

| # | Defeito | Como apareceu |
|---|---|---|
| 1 | ancora de evidencia reprovava retorno real bem ancorado | rodar um subagente de verdade e ler o payload da sonda |
| 2 | `nao verificado` era inexequivel - o hook bloqueava o que ele mesmo instrui | testar a instrucao publicada |
| 3 | R4 era vacua: campos que o hook nao le | mutacao sobre a garantia que R4 dizia proteger |
| 4 | comentario obsoleto contradizendo codigo e matcher | conferir o matcher real |
| 5 | gate inerte em branch sem upstream | montar o cenario e rodar |
| 6 | suites nao reentrantes corrompem-se com FAIL plausivel | rodar duas ao mesmo tempo |
| 7 | S2 nao via pacote sem aspas simples; S1 quebrava com espaco duplo | gerar variantes de formatacao |
| 8 | `--enforce` gravava a politica antes de conferir; `--revert` nao revertia | exercitar o proprio instalador |

Os defeitos 1, 2, 7 e 8 sao de SEGURANCA ou de disponibilidade do mecanismo. Os defeitos 3 e 6
sao do aparato de teste - isto e, do que deveria detectar os demais.

## 1. A condicao de refutacao do ADR 0022 foi testada, e nao se realizou

O ADR 0022 declarava: "Se `~/.claude` nao fosse o escopo efetivo - por exemplo, se plugins
instalados sobrescrevessem os hooks em tempo de execucao". Enquanto nao observado, a tese
central tinha premissa aberta.

O handoff afirmava que so o usuario poderia observar, via `/hooks`. **Parcialmente falso.**
`/hooks` e `/status` sao da TUI; `--debug` e flag de CLI; e existe observavel mais forte que
qualquer um dos dois: `--include-hook-events` com `--output-format=stream-json` emite
`hook_started` e `hook_response` com `exit_code` e `outcome`. `/hooks` mostra o CONFIGURADO;
isto mostra o EXECUTADO.

Predicao registrada antes do tratamento e confirmada exatamente (2->3, 4->5, 3->4 por evento,
com o heartbeat do hook de usuario continuando a incrementar): **hooks de plugin SOMAM aos de
escopo de usuario.** O total por evento e a uniao dos escopos, filtrada por `matcher`.

A tese do 0022 permanece, agora com premissa medida.
Registro completo: `evidence/observations/2026-08-04-precedencia-de-hooks.md`.

## 2. A fronteira externa passou a impor - e isso foi medido, nao configurado

Ruleset ativo com `bypass_actors: []`. O que importa nao e te-lo criado:

```
$ git push origin fase1/contrato-ancora:main
remote: error: GH013: Repository rule violations found for refs/heads/main.
 ! [remote rejected]   exit=1   origin/main inalterado em 92908d1
```

O push partiu do token com `admin: true` - o ator governado na sua maior autoridade - e foi
recusado. `¬bypass(ator, politica)` deixa de ser aspiracao.

**Refinado por um segundo teste, no fim da sessao.** Um push direto foi ACEITO - e o controle
explicou: o SHA ja era o head de um PR com os checks verdes, e o GitHub o registrou como
`state: MERGED`. Com commit novo e sem PR, a recusa se repete. A propriedade nunca foi "o
comando falha"; e que artefato sem PR aprovado nao chega a `main`. Uma observacao sem controle
teria produzido refutacao FALSA de garantia verdadeira - o erro simetrico, e igualmente caro.

Limite que permanece, e que o README precisa dizer: quem tem admin pode DESATIVAR o ruleset. O
provado e que nao ha bypass DENTRO da regra. Desativar deixa rastro no audit log; contornar em
silencio nao deixaria. E a diferenca entre as duas coisas e todo o alcance possivel sem uma
autoridade organizacional acima do dono do repositorio.

## 3. O defeito mais consequente: o mecanismo pressionava na direcao de fabricar evidencia

`subagent-contract.sh` bloqueia retorno sem ancora de evidencia. Medido sobre payload REAL:

```
- Comando: `wc -l .../verify.sh` -> saida `71 .../verify.sh`, exit code `0`.
   -> BLOQUEADO: "Faltou: ANCORA-DE-EVIDENCIA"
```

Duas causas, ambas da mesma classe - o oraculo reconhecia evidencia por CONVENCAO LEXICAL e nao
por estrutura:

- `0x60` (crase de markdown) entre `code ` e `0` derrotava o padrao. Escrever ``exit code `0` ``
  e a forma normal de um agente formatar.
- a lista de comandos era FECHADA. `wc`, `xxd`, `stat`, `make` ficavam de fora. Enumerar
  comandos nao e conjunto decidivel: a allowlist so cresce por remendo.

E havia o terceiro, pior que os dois: a mensagem de bloqueio promete por escrito que
`nao verificado` e resposta valida, e o CLAUDE.md secao 4 tambem. **Medido: um retorno
declarando nao-verificacao recebia exit 2 identico ao de prosa vazia.**

A consequencia e estrutural, nao cosmetica. O unico caminho estavel para atravessar o portao
era APRESENTAR uma ancora. Um mecanismo criado para punir alegacao sem lastro estava
selecionando, entre os agentes, aqueles que produzem a APARENCIA de lastro. Isso e pior do que
nao ter o mecanismo: sem ele, "nao verifiquei" e apenas nao dito; com ele, e penalizado.

## 4. O aparato de teste tinha os mesmos defeitos que deveria detectar

**R4 era vacua.** Montava o payload com `transcript_path` e `subagent_type`; o hook le
`agent_type` e `last_assistant_message`. Com `agent_type` vazio, o hook saia no filtro de tipo
e nunca chegava a normalizacao que R4 dizia proteger. Provado por mutacao: removida TODA a
normalizacao, R4 antiga seguia verde nos dois locales; com os campos corretos, o mesmo mutante
morre. **Sexta instancia do padrao** `precondicao falha -> operacao nao executa -> pos-condicao
vacuamente verdadeira -> verde`.

**A ancora so tinha casos positivos.** O caso "barra retorno sem evidencia" reprovava ja no
`RESULTADO`, entao o poder discriminante da ancora nunca fora exercitado. Positivo sem negativo
correspondente mede PRESENCA, nao poder de decisao. Corrigido, e o mutante MC4 (oraculo que
aceita tudo) so pode ser morto por esse caso negativo.

**O contrato de subagente nunca fora validado por mutacao** - justamente o hook com o pior
historico do projeto (ADRs 0014, 0018, adendo 6 do 0022). `tests/mutation/contrato.sh`, 5
mutantes, cada um morto no caso-alvo.

## 5. Testes de propriedade acharam dois detectores de seguranca furados

`tests/unit/propriedades.sh` afirma propriedades sobre FAMILIAS de entrada. Na primeira
execucao:

- **S2 so enxergava tokens iniciados por aspa simples.** `pip install requests` e
  `pip install "requests"` PASSAVAM. Um pacote sem pinagem atravessava o gate inteiro por
  diferenca de formatacao - a propria classe que S2 existe para impedir.
- **S1 recortava por `${line#*uses: }`**, com um espaco literal. `uses:  a/b@v1` produzia
  string vazia e a action nao pinada passava batida.

Nenhum dos dois seria encontrado por mais um caso por exemplo escrito por quem escreveu o
detector: o exemplo herdaria a mesma suposicao de formatacao. Esta e a justificativa completa
para o metodo, e ela e especifica - nao vale "propriedades sao melhores".

## 6. Concorrencia: a corrida produzia vermelho PLAUSIVEL

Reproduzido: `tests/mutation/contrato.sh` (que muta o hook no lugar) concorrente com
`tests/unit/run.sh` fez este ultimo reportar `FAIL BARRA blocos completos SEM ancora
(got=0 want=2)`, exit 1. Isolada no instante seguinte: 45/45.

O perigo nao e a vermelhidao - e ela ser plausivel. O caso acusado parece defeito real, e o
operador depuraria algo que nao existe. A corrida simetrica tambem cabe: suite lendo o hook
MUTADO (mais permissivo) durante a janela mascara defeito real.

`tests/lib/lock.sh` FALHA RAPIDO em vez de serializar. Esperar faria as duas passarem, que e a
absorcao silenciosa que este repositorio existe para nao fazer. O lock mora em `.git/`, nao em
`$TMPDIR`: exclusao mutua ancorada em variavel de ambiente nao e exclusao mutua.

## 7. Claim ledger: o que o torna util nao e o formato

`evidence/claims/*.yaml`, 16 alegacoes. A regra que o distingue de prosa formatada: **toda
referencia a evidencia e resolvida contra a suite real, e citar regressao ou mutante inexistente
REPROVA.** O inventario e DERIVADO de `tests/` a cada execucao (a contagem corrente sai em `docs/status.generated.md`; digita-la aqui a faria divergir, que e exatamente o defeito que originou aquele arquivo) -
lista digitada seria segunda copia da verdade.

Ha autochecagem: extracao vazia sai 2 (NAO VERIFICADO), nunca 0. Sem ela, uma regex quebrada
reprovaria tudo (falso vermelho) ou, frouxa demais, aprovaria tudo (falso verde).

A maioria dos casos de `tests/unit/claims.sh` e NEGATIVA - e essa proporcao, e nao o total, e o que importa: um validador que aprovasse tudo passaria em qualquer numero de positivos. E um deles nasceu passando pelo motivo
errado - o fixture era YAML invalido e a reprovacao vinha do parser, nao da resolucao.

## 8. Raiz de confianca: duas correcoes ao plano do handoff

O handoff previa "migrar os 14 hooks para plugin force-enabled ANTES de ativar". Conferido na
fonte primaria:

> `allowManagedHooksOnly` | (Managed settings only) Only managed hooks, SDK hooks, and hooks
> from plugins force-enabled in managed settings `enabledPlugins` are loaded. User, project,
> and all other plugin hooks are blocked.

Correcao 1: o escape e `enabledPlugins` DENTRO do managed settings. E como conteudo de plugin
mora em `~/.claude/plugins`, gravavel pelo ator, plugin nao serve de raiz: politica root
apontando para script user-owned e raiz de confianca so no nome.

Correcao 2: **nao bastam os hooks.** `verify-gate.sh` le a tabela em `$CLAUDE_ADAPTERS_DIR`;
`doctool.sh` le `$DOC_ADAPTERS_DIR`; `read-budget.sh` executa os doctools. Com a tabela
gravavel, o ator desliga o gate sem tocar em hook nenhum. O deploy managed cobre 30 componentes.
Agentes e skills seguem em `~/.claude` por decisao declarada: sao capacidade, nao politica.

E o instalador tinha dois defeitos proprios, achados antes de qualquer entrega: `--enforce`
gravava a politica ANTES de conferir o deploy (deploy incompleto derrubaria o mecanismo
inteiro - a armadilha exata do handoff), e `--revert` nao revertia (restaurava um "backup" que
o proprio instalador havia criado).

## O que NAO foi feito, e por que

- **`allowManagedHooksOnly` nao foi ativado.** Exige `sudo`, que exige senha nesta maquina. O
  instalador foi exercitado integralmente contra prefixo de ensaio, mas a
  afirmacao "o runtime honra a flag" so pode vir de medicao com root. Ate la o estado e
  NAO VERIFICADO, e o `status.generated.md` continua dizendo `governed=user`.
- **Sem corpus de eficacia (P4).** Nenhuma afirmacao sobre melhoria de engenharia e dizivel.
- **Sem auditoria autoralmente independente (P5).** A CI executa testes escritos pelo mesmo
  processo, contra os mesmos oraculos. Continua sendo observador ambiental.
- **Sem sandbox.** `pandoc`, `libreoffice` e `pdftotext` seguem processando entrada nao
  confiavel com a autoridade do usuario. Esta e a lacuna aberta mais relevante, e ela DEVE
  travar a expansao para OCR e novos formatos ate haver isolamento.
- **`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=0` continua nao verificado.**

## O que refutaria este ADR

- Se, sob outra versao do runtime ou outra plataforma, hooks de plugin SOBRESCREVESSEM os de
  usuario, a secao 1 cai e com ela a premissa do 0022. A medicao e de uma versao e uma
  plataforma.
- Se `allowManagedHooksOnly`, ativado, NAO bloqueasse hooks de usuario, a secao 8 estaria
  descrevendo uma garantia que nao existe. Nao foi medido.
- Se o oraculo da ancora, corrigido, passasse a aceitar retorno sem lastro em uso real, a
  correcao da secao 3 teria trocado falso bloqueio por falso verde. **ISTO SE REALIZOU DUAS
  VEZES** - ver o adendo. Esta linha citava um "corpus de 15 casos" que nunca existiu em
  `tests/`; a cobertura real e a que `docs/status.generated.md` publica por execucao. Manter
  aqui a alegacao que o proprio adendo desmente seria o defeito descrito duas secoes abaixo,
  dentro do paragrafo que existe para dizer o que refutaria este documento.

## O padrao, com oito instancias novas

O ADR 0022 fechava dizendo que o avanco nao veio de parar de errar, mas de tornar erros
observaveis. Esta sessao acrescenta uma distincao mais estreita: **os oito defeitos foram
encontrados por MUDAR O QUE EXECUTA, nao por olhar mais.**

Rodar o binario de verdade; rodar sob outro locale; rodar duas vezes ao mesmo tempo; rodar com
um plugin a mais; gerar variantes de formatacao; mutar a garantia. Leitura atenta do mesmo
codigo, pela mesma pessoa que o escreveu, encontrou zero deles - inclusive nas passagens onde a
regra violada estava escrita no comentario logo acima.

---

## Adendo - a revisao independente sobre o proprio diff desta sessao

Antes de fechar, o diff foi submetido a `revisor-codigo` e `auditor-seguranca` em contexto
separado, com scanner executado. **Onze achados procedentes**, cinco deles criticos - todos
sobre codigo escrito NESTA sessao, boa parte dele sobre as proprias correcoes acima.

O dado que organiza este adendo: a suite estava **verde com todos os onze abertos**. Isso nao
e contradicao, e o ponto - nenhum dos onze tinha caso de teste, porque quem escreveu o codigo
escreveu tambem os testes, e ambos herdaram a mesma suposicao.

### Critico: a raiz de confianca era instalada a partir de entrada nao confiavel

`install/manifest.lock` e um arquivo do REPOSITORIO, isto e, esta dentro do espaco de escrita
do ator governado. Suas colunas `origem` e `destino` eram usadas VERBATIM como caminho de
`mkdir -p`, `cp -f` e `rm -rf`, e o instalador roda como ROOT. Medido:

```
destino = ../../../ZONA/vitima.conf   -> arquivo FORA do prefixo sobrescrito
destino = ../../../ZONA  (origem=dir) -> `rm -rf` destruiu o diretorio FORA do prefixo
origem  = /etc/hostname               -> copiaria arquivo de fora do repo, com modo alargado
```

Sob `sudo`: escrita e remocao arbitrarias como root a partir de dado que o ator controla. A
inversao exata da tese do projeto. E o digest do manifesto nao protegia - ele e calculado sobre
o MESMO working tree que deveria proteger, e a conformidade comparava o arquivo copiado com o
valor que o proprio atacante escreveu. Detector de drift contra `~/.claude`, jamais controle de
integridade sobre o repositorio; a distincao passou despercebida ate a auditoria.

Corrigido com portao de confinamento antes da primeira escrita, nos DOIS instaladores - o furo
gemeo em `install/apply.sh` roda como usuario, mas seu alvo sao os proprios hooks da politica.

### Critico: o portao contava divergencia e nunca populacao

Com o conjunto de politica VAZIO, o laco de copia nao copia nada, a conformidade nao itera
nada, e `0 divergentes` era lido como aprovacao. `--enforce` gravava `allowManagedHooksOnly:
true` apontando para 14 caminhos inexistentes: o mecanismo inteiro de hooks desligado com
aparencia de ligado - a armadilha que o proprio arquivo dizia tratar. Gatilho realista: qualquer
normalizacao de whitespace no manifesto.

`MG6` nao pegava, e a razao importa: ele sabota UMA entrada (`div=1`); nao esvazia o conjunto.
**Ausencia de divergencia num conjunto vazio e vacuamente verdadeira** - a mesma forma logica
perseguida desde o ADR 0022, agora dentro do portao construido para impedi-la.

### Critico: `--revert` apagava politica de terceiro

O comentario prometia "Remove SOMENTE o que este script cria". O codigo apagava QUALQUER
`managed-settings.json` - inclusive politica corporativa de outra ferramenta, que pode conter
`permissions.deny` - sem backup, sem aviso, sob `sudo`. A marca `_managed_by` ja existia e era
consultada no ramo de backup, nao no de remocao.

### Critico: o gerador da politica aceitava injecao de JSON

`sed "s|@BASE@|$BASE|g"` sobre o texto do JSON: um valor com aspas FECHA a string e ABRE objeto
novo, e o resultado continua sendo JSON valido - de modo que o `jq -e .` do consumidor nao
barra. Esse documento vira politica em `/etc/claude-code/`. Trocado por `jq --arg`, que nunca
reparseia o valor.

### Critico: o oraculo da ancora trocou falso bloqueio por falso verde

**A condicao de refutacao escrita neste proprio ADR foi satisfeita.** A correcao da secao 3
abriu passagens vacuas, medidas:

| Contraexemplo | Alternativa que casava | Estado |
|---|---|---|
| `o custo foi de R$ 500 mil` | `\$ ` em qualquer posicao | corrigido (ancorado no inicio da linha) |
| `nada ficou nao verificado` | escape sem polaridade nem caixa | corrigido (token `NAO VERIFICADO` em caixa alta) |
| eco da mensagem de bloqueio do hook | idem | corrigido - o portao publicava a propria chave |
| `a doc em exemplo.com:8080 descreve` | `arquivo.ext:linha` | **ABERTO, declarado** |
| `pela leitura, o hook faz exit 2` | `exit <digito>` | **ABERTO, declarado** |

Os dois ultimos nao sao patchaveis por regex, e insistir seria trocar este falso aceite por
outro falso bloqueio - foi assim que o defeito de producao nasceu. `host.tld:porta` e
`arquivo.ext:linha` sao lexicalmente identicos; citar um exit code tem a mesma forma de
reportar um. **O limite passa a ser escrito no hook e em `evidence/claims/C-009.yaml`:** o
oraculo distingue texto COM FORMA de evidencia de texto sem forma; nao distingue REPORTAR de
MENCIONAR.

E havia um agravante de outra ordem: o comentario do hook e a claim C-009 afirmavam validacao
contra "corpus de 15 casos - 9 positivos, 6 negativos". **Esse corpus viveu no rascunho de quem
escreveu a correcao e nunca entrou em `tests/`.** Afirmacao de cobertura inexistente, dentro do
ledger de evidencia. Corrigida em ambos, e o mecanismo que a pegou foi o proprio validador,
quando as claims passaram a citar mutantes que ainda nao existiam.

### Setima instancia do padrao vacuo, no verificador da fase 2

`--verify` imprimia `0 gravaveis pelo ator` sob prefixo de ensaio, onde essa checagem NAO
EXECUTA - ela e guardada por `REAL=1`. A suite lia esse veredito como aprovacao da garantia
central da fase 2. Agora o modo de ensaio declara `NAO VERIFICADO` e nao afirma "fora do espaco
de escrita do ator".

### O que permanece ABERTO, e nao foi corrigido nesta sessao

- **Base de comparacao com remoto de outro nome.** `verify-gate.sh` procura
  `origin/{HEAD,main,master}`; num fork cujo remoto se chama `upstream`, ou com default
  `develop`, a base cai para arvore vazia e o gate passa a acusar codigo JA PUBLICADO. Medido:
  dois repositorios identicos, diferindo so no nome do remoto, dao `exit=2` e `exit=0`. E
  falso positivo, e falso positivo e o que faz o operador desligar o gate. `C-008` declara o
  limite como "verifica mais do que o necessario, nunca menos" - formalmente verdadeiro,
  severidade subdimensionada.
- **`tests/unit/claims.sh` L5b sobrevive a remocao da guarda que diz testar.** Removida
  `RE_SHA` de `commit_existe`, a suite segue verde: `git cat-file -e` recusa a opcao sozinho.
  O teste mede o parser do git, nao a guarda. `RE_SHA` fica como defesa em profundidade sem
  bypass demonstrado, e o TESTE e que esta errado.
- **A politica managed executa `install/verify.sh` do espaco do ator.** `session-integrity.sh`
  roda `cd $TOLLENS_REPO && bash install/verify.sh`, e esse env e gravado pelo proprio
  `managed-settings.json` root-owned apontando para o clone no home. `verify.sh` nao e
  componente do manifesto, logo nao vai para `/opt`. O ator faz o proprio auditor sair 0.
  Corrigir exige promover `verify.sh` e o manifesto a componentes managed.
- **Copia antes da conformidade.** O portao de confinamento precede a primeira escrita, mas a
  copia para `$OPT` ainda precede a checagem de digest: um repositorio com drift sobrescreve a
  politica VIVA antes de reprovar. Correcao: estagiar em `$OPT.new` e trocar por `mv` atomico.
- **`--verify` nao mede posse em nenhum caminho executavel**: exige `REAL=1`, que exige root.

### O que este adendo demonstra sobre o metodo

Onze achados procedentes sobre codigo escrito horas antes, por quem tambem escreveu os testes
que o cobriam - e a suite verde o tempo inteiro. As correcoes desta sessao criaram tres dos
cinco criticos.

A conclusao operacional nao e "revisar mais". E que **revisao com CONTEXTO SEPARADO e ferramenta
que executa acha o que o autor nao pode achar**, porque o ponto cego do autor esta nos testes
tanto quanto no codigo. O `refutador` como portao final nao substitui isso: chega tarde demais
para reescrever o corpus.

---

## Adendo 2 - o portao final, e o que ele refutou

O `refutador` recebeu o diff cru e o veredito foi **revisar-e-ressubmeter**, com tres refutacoes
estruturais em artefatos independentes. Todas reproduzidas por execucao propria antes de aceitas.

### O portao de populacao comparava o manifesto CONSIGO MESMO

`--enforce` conferia `n` (itens conformes) contra `tipos_politica | wc -l` - e `n` vinha do laco
que itera a MESMA fonte. Tautologia: so podia falhar com o conjunto vazio, que era justamente o
caso que o adendo anterior havia acabado de cobrir. Medido:

```
$ grep -v 'evidence/hooks/verify-gate.sh' install/manifest.lock > sem-gate.lock
$ MANAGED_MANIFEST=sem-gate.lock ... --enforce     -> EXIT=0
  allowManagedHooksOnly=true
  politica declara: bash .../hooks/verify-gate.sh   -> arquivo NAO EXISTE
```

O gatilho e o procedimento normal do repositorio: `manifest.sh` gera por glob, entao renomear ou
mover um hook e regenerar produz esse estado sem edicao manual. A politica vem de OUTRA fonte -
`hooks-spec.sh` - e o produto nunca a confrontava com o disco. **A propriedade existia apenas no
oraculo do teste (MG4), exercitada sobre o manifesto real, onde era vacuamente verdadeira.**
Garantia morando no TESTE e nao no ARTEFATO - a inversao que este ADR persegue, encontrada
dentro do portao construido para impedi-la, uma correcao depois.

Este e o **quinto** defeito no mesmo `apply-managed.sh` nesta sessao.

### A correcao do falso aceite anterior introduziu outro

Ao ancorar o prompt de shell no inicio da linha para barrar `R$ 500 mil`, entrou `[$>]` - e `>`
no inicio da linha e BLOCKQUOTE de markdown, a forma corrente de um agente citar prompt, doc ou
mensagem de erro. Medido: 8 de 15 retornos de prosa plausivel atravessavam, 3 so por isso. O `>`
entrou sem mencao no comentario que justificava o cifrao.

**Terceira rodada de regex neste oraculo, terceiro par falso-bloqueio/falso-aceite.** O `>` foi
removido; o padrao de recorrencia fica registrado, porque ele - e nao a alternativa N+1 - e o
achado. Um oraculo lexical sobre texto livre tem um teto, e cada rodada o encontra por outro
lado.

### `scope.commit` era decorativo

O validador conferia apenas que o objeto git existia, e resolvia a evidencia contra o WORKTREE.
Medido: as 16 claims declaravam `1319931`, e nesse snapshot os mutantes MC6/MC7 e as duas
observacoes de C-015/C-016 nao existiam. A frase impressa era verdadeira sobre a arvore de
trabalho e falsa sobre o escopo que cada claim declara.

Corrigido na estrutura: `inventario_no_commit()` deriva a evidencia do snapshot declarado por
cada claim, via `git ls-tree` e `git show`, e a observacao e conferida com `git cat-file -e
<commit>:<path>`. L12 exercita a discriminacao - a MESMA claim, mudando so o snapshot, passa de
0 para 1.

### E o ADR mantinha publicada a alegacao que ele mesmo desmentia

A secao "O que refutaria este ADR" repetia o "corpus de 15 casos" que o adendo 1 declara
inexistente. Corrigido, junto de tres numeros digitados em prosa que ja haviam se afastado do
repositorio. A correcao **nao foi atualiza-los**: foi remove-los e apontar para
`docs/status.generated.md`. Numero digitado em prosa e a classe que originou este projeto, e
atualizar um numero so adia a proxima divergencia.

`tests/unit/run.sh` era a unica suite sem invariante de contagem - e e a que hospeda os casos do
oraculo da ancora. Agora tem.

### O que o portao final demonstra

O `refutador` sustentou P1 conferindo o ruleset na API em vez de acreditar no relato, e nao
conseguiu refutar P0.2, P0.3, P0.4, o lock nem as contagens invariantes - dizendo, em cada caso,
o que testou. Refutou tres coisas, e as tres eram do mesmo tipo: **artefatos que afirmavam mais
do que verificavam**, incluindo o proprio ADR.

O padrao acumulado nesta sessao, agora com dezenove defeitos: os achados vieram de mudar o que
executa e de contexto separado. Nenhum veio de reler. E as correcoes produziram uma fracao
relevante dos defeitos seguintes - o que significa que "corrigido" e um estado tao sujeito a
verificacao quanto "escrito".

---

## Adendo 3 - a CI reprovou o ultimo commit, e o achado era do teste

`55014c4` saiu vermelho. O defeito estava em `L12`, escrito uma hora antes para provar que
`scope.commit` decide: ele ancorava o snapshot antigo em `HEAD~6`. Isso nao e uma propriedade -
e uma DISTANCIA no historico, e o resultado muda sozinho a cada commit.

Localmente `HEAD~6` caia antes de a suite de concorrencia existir, e o caso media o que dizia
medir. Com um commit a mais, passou a cair depois: a claim resolveu, o caso passou a medir nada,
e a contagem invariante reprovou. **A invariante de contagem foi quem denunciou** - sem ela, o
caso teria virado verde vacuo em silencio.

### O dado que nenhuma execucao isolada daria

No MESMO SHA, o run de `pull_request` PASSOU e o de `push` REPROVOU. Em `pull_request` o checkout
e de um merge commit, cuja ancestralidade e outra - dois valores de `HEAD~6` para o mesmo codigo.
Foram precisos dois eventos com topologias distintas para expor a dependencia.

Corrigido com ancora estavel por construcao (a raiz do repositorio) e uma PRECONDICAO EXPLICITA
que afirma que a evidencia citada de fato nao existe naquele snapshot - sem ela o caso volta a
poder medir nada, que foi exatamente como quebrou.

### CORRECAO DE UMA AFIRMACAO MINHA, no commit que corrigiu o teste

A mensagem de `716f9a2` afirma: "um merge pode proceder com o run de PR verde enquanto o de push
esta vermelho". **Isso foi afirmado com mais forca do que a medicao sustenta.**

O que foi MEDIDO: para `55014c4` existem dois check-runs chamados `verify` no mesmo SHA, um
`success` e um `failure`, iniciados com 4 segundos de diferenca.

O que NAO foi verificado: qual dos dois o `required_status_checks` avalia - o mais recente, o
primeiro, ou a conjuncao. A documentacao nao foi localizada em fonte primaria (a URL consultada
devolveu 404), e nao construi a medicao direta porque ela exigiria empurrar deliberadamente um
commit vermelho para o branch protegido.

Portanto o estado correto e: **ha dois check-runs homonimos por SHA, e a regra de desempate do
portao e NAO VERIFICADA.** Se for "o mais recente", a ordem entre os dois runs decide - e eles
comecam com segundos de diferenca, o que faz do desempate uma corrida. Isso e o suficiente para
tratar como pendencia real, e nao o suficiente para afirmar que ha bypass.

Registro o episodio porque ele e a regra de verificacao de fonte aplicada contra o proprio autor,
duas horas depois de o ADR declarar que essa e a regra: enunciar nao executa.
