# ADR 0022 - Tres planos, e a fronteira que o ator nao controla

- Data: 2026-08-03
- Status: aceito
- Corrige: 0010, 0015, 0016, 0020 (todos tratavam `Stop` como portao de conclusao)
- Renomeia o projeto: `claude-mecanismo` -> `tollens`

## O achado que subordinou todos os outros

O repositorio nao era o sistema. Medido em 2026-08-03, claude-code 2.1.220:

| Componente | Ativo | Versionado | Cobertura |
|---|---|---|---|
| Hooks | 13 | 9 (1 divergente) | 62% |
| Skills | 9 | 2 | 22% |
| Agentes | 10 | 1 | 10% |
| **Total** | **32** | **12** | **37,5%** |

Quatro hooks rodavam em toda sessao sem versionamento, teste ou ADR. E o `verify-gate.sh`
instalado era uma versao **anterior** a do repositorio - sem a camada de adaptadores que o
`plugin.json` declarava implementada e que o ADR 0011 registrava como corrigida:

```
grep -c "ADAPTERS" ~/.claude/hooks/verify-gate.sh  ->  0
```

Este projeto passou 21 ADRs combatendo prosa-como-garantia e produziu um repositorio que era,
ele mesmo, prosa sobre um sistema divergente. Nao era um bug: era um estado que nao deveria ser
alcancavel. Nao existia operacao de instalar nem de conferir, so `cp` - e copia diverge calada.

## O erro de categoria

`Stop` foi tratado como portao de conclusao desde o ADR 0010. Ele nao pode ser, por quatro
razoes independentes:

1. `stop_hook_active=true` na parada seguinte a um bloqueio - semantica anti-loop oficial;
2. o runtime **sobrepoe** o hook apos N bloqueios consecutivos (default 8);
3. esse N vive em `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`, dentro do `settings.json` que o proprio
   ator governado escreve;
4. `Stop` nao dispara em interrupcao do usuario nem em falha de API.

A razao 3 e a estrutural e generaliza: **parametro de politica dentro do espaco de escrita do
ator governado nao e politica.** Vale igualmente para `disableAllHooks`, `enabledPlugins`,
`permissions`, `env` e `hooks`.

E `pre-commit` tambem nao e fronteira. Medido:

```
git commit             -> exit=1, 0 commits   (hook barrou)
git commit --no-verify -> exit=0, 1 commit    (codigo reprovado entrou na historia)
```

A propriedade correta nunca e absoluta. E sempre relativa: `¬bypass(ator, politica P)`.

## Decisao

### Tres planos, com autoridades distintas

```
control/    politica, autoridade, integridade de configuracao
execution/  hooks de execucao, adaptadores, agentes, skills
evidence/   verificador, ledger, telemetria, CI
```

### A cadeia de estados perde `READY`

```
DRAFT -> LOCALLY_CHECKED -> CANDIDATE -> CI_VERIFIED -> MERGEABLE
falhas: LOCAL_CHECK_FAILED | NOT_VERIFIED | CI_FAILED | STALE_EVIDENCE
```

A sessao produz no maximo `CANDIDATE`. Quem certifica e a CI sobre o SHA exato.

### Cinco garantias do verificador, cada uma com repro e mutante

| # | Garantia | Defeito que pagou |
|---|---|---|
| G1 | cache guarda VEREDITO; `fail` nunca vira verde | carimbo gravado antes de executar: 2a parada saia 0 com codigo quebrado |
| G2 | `stop_hook_active` avisa por `additionalContext` | stderr com exit 0 e canal inerte (ADR 0021) |
| G3 | identidade sobre BYTES | hash de nomes nao ve conteudo de untracked |
| G4 | conjuncao sobre TODOS os adaptadores | monorepo: JS valido mascarava Python quebrado |
| G5 | `command` + `args`, sem `sh -c` | string em shell permite composicao arbitraria |

### Manifesto, instalador, verificador

Nao existe instalar manualmente. `install/manifest.sh` declara o estado desejado com digest;
`install/apply.sh` aplica; `install/verify.sh` compara; `control/hooks/session-integrity.sh`
denuncia divergencia no primeiro turno da sessao.

## O que este ADR NAO resolve

**A politica continua gravavel pelo ator.** Esta fase e escopo de usuario. A raiz de confianca
real exige managed settings + `allowManagedHooksOnly` + launcher nao gravavel, e nao foi feita
porque `allowManagedHooksOnly` desliga de uma vez todo hook de escopo de usuario - ativa-lo
antes de migrar os 14 hooks derrubaria o mecanismo inteiro. Fase 2, com sudo, apos validacao.

**Nao ha medicao de desfecho.** As suites verificam mecanismo sob fixture. Que o harness
melhore resultado de engenharia continua nao demonstrado, agora com um agravante conhecido:
`SWE-Skills-Bench` (arXiv:2603.15401) tem ~11 tarefas por skill, e 24 das 49 skills saturaram
em 100% nas duas condicoes - o benchmark nao tinha margem para detectar ganho nessas. Alem
disso, `ΔP=0` significa `n01=n10`, nao `n01=n10=0`: os 39 deltas nulos nao demonstram que as
condicoes acertaram as mesmas tarefas. Dimensionar corpus exige `q=p01+p10` e `d=p01-p10`,
que o artigo nao publica.

**`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP=0` nao foi verificado.** O default 8 esta documentado; a
semantica de zero veio de fonte secundaria. Plano de teste: cap=2, hook que sempre bloqueia,
contador persistente, timeout externo.

## O que refutaria este ADR

Se `~/.claude` nao fosse o escopo efetivo - por exemplo, se plugins instalados sobrescrevessem
os hooks em tempo de execucao. A precedencia entre `~/.claude/hooks` e `~/.claude/plugins/` nao
foi verificada com `/hooks` nem `--debug`.

## Adendo 2026-08-03 - achados de revisao independente

Revisao externa do estado publicado encontrou oito defeitos. Todos verificados; sete corrigidos.

### Regressao de seguranca minha, confirmada na fonte primaria

O adaptador .NET declarava `executes_repository_code: false` sobre `dotnet format
--verify-no-changes --no-restore`. A documentacao da Microsoft adverte o contrario:

> `dotnet format` **may restore, compile, and run analyzers** from the specified project or
> solution. **Only invoke the tool against trusted code.**

`--no-restore` suprime apenas o restore implicito - nao a compilacao nem os analisadores, que
sao codigo do repositorio. Escrevi a justificativa sem conferir a fonte: e o terceiro erro
desta classe no projeto, sob vigilancia nominal da regra que existe para impede-lo.

Corrigido como REGRA GERAL, nao caso especial (G10): adaptador que declara
`executes_repository_code: true` nunca roda em auto-deteccao - vira lacuna declarada.

### Demais correcoes

| # | Defeito | Correcao |
|---|---|---|
| G9 | `jq`/`git` ausentes saiam 0 em silencio - a mesma inercia que G7 combate, no caminho mais critico | dependencia estrutural ausente e NOT_VERIFIED; fora de repo git, inerte segue legitimo |
| G11 | `environment_digest` hasheava so o CAMINHO do binario; troca do executavel no mesmo path preservava o `pass` em cache | inclui realpath, sha256 do binario e string de versao |
| - | `apply.sh` nao removia componente que saiu do manifesto: `apply` nao convergia para `desired` | `managed-files.lock`; remove apenas o que ele mesmo gerenciou, nunca arquivo desconhecido |
| - | skills eram conferidas contra a working tree, deixando o manifesto fora do circuito | digest com caminho normalizado; `REPO-DRIFT` distinguido de `installation drift` |
| - | contagem de casos era descritiva: apagar cinco testes mantinha a suite verde | `EXPECTED` como invariante |
| - | mutante era considerado morto por qualquer reprovacao, e `sed` que nao casava virava "sobreviveu" | baseline obrigatorio; kill precisa ser atribuivel ao caso-alvo; mutante nao aplicado e FALHA |
| - | CI usava `actions/checkout@v4`, `ubuntu-latest` e ruff sem versao - tags mutaveis numa fronteira de evidencia | action pinada por SHA completo, `ubuntu-24.04`, `ruff==0.15.5` |

O mutante M7 sobreviveu a primeira tentativa e revelou que o caso G7 nao distinguia "lacuna por
ser executor" de "lacuna por binario ausente" - assercao especifica adicionada. Segunda vez
nesta sessao que a mutacao encontra teste fraco que a suite verde nao mostrava.

### Nao corrigido, e por que

- **`.claude/verify.json` aprovado ainda SUBSTITUI os analisadores genericos** em vez de somar.
  A formula real e `Pass(v_repo,x)` quando aprovado, nao a conjuncao. E override semantico
  deliberado (o projeto sabe o que verificar), mas estava descrito como conjuncao irrestrita.
- **A aprovacao cobre o digest de `verify.json`, nao o conteudo transitivo.** Aprovar
  `{"command":"bash","args":["scripts/verify.sh"]}` autoriza um script que pode mudar depois.
  A aprovacao significa "confio que este repositorio execute sua suite", nao "confirmei os
  bytes que rodarao". Solucao real e sandbox, nao aprovacao.
- **Commit local sem upstream nao e verificado**: `git diff HEAD` e untracked ficam vazios apos
  commit, e sem `@{u}` nao ha base. Exige definir a base (merge-base, commit inicial da sessao
  ou ledger anterior).
- **Adaptadores de documento sao especificacao versionada, nao mecanismo executado.** Nenhum
  executor os consome: `read-budget.sh` mantem logica propria por extensao.

## Adendo 2 - a garantia nova que quebrou o modo seguro

Segunda revisao independente, sobre o commit `9ddb1fa`. Cinco achados; todos procedentes.

### Critico: `--dry-run` passou a apagar arquivo

Ao adicionar a convergencia (`managed-files.lock`), o bloco de remocao ficou ANTES da checagem
`[ "$DRY" -eq 1 ] && exit 0`. O modo anunciado como inspecao segura executava `rm -rf`.

Medido antes da correcao, em HOME descartavel:

```
digest apos adicionar orfao ... a87423aa7c659c48
DEPOIS do --dry-run .......... a32a09c13da42d79   <- estado alterado
arquivo orfao FOI APAGADO pelo dry-run
```

Este defeito e a tese do projeto aplicada a si mesmo: **adicionar uma garantia de convergencia
nao prova que os demais modos da operacao, em especial o modo declaradamente nao destrutivo,
preservam a garantia.** Corrigido com portao antes de qualquer escrita, e coberto por G10, que
compara o digest do diretorio byte a byte, mais o mutante MI1 em `tests/mutation/install.sh`.

### Demais

| # | Defeito | Correcao |
|---|---|---|
| G9b | `command -v git \|\| exit 0` seguia fail-open; so `jq` fora corrigido | sobe a arvore atras de `.git` sem usar git; havendo `.git` e faltando git, NOT_VERIFIED |
| - | contagem publicava "9 mortos" para 8 mutantes: o baseline incrementava o mesmo contador | `BASELINE` separado; `EXPECTED_MUTANTS` como invariante |
| - | `environment_digest` truncava o sha256 do binario em 16 hex (64 bits), descrito como "sha256 do binario" | hash completo; numa identidade de evidencia nao ha ganho em truncar |
| - | "heartbeat em toda sessao" era mais forte que o codigo | limite escrito no hook: ha heartbeat em toda execucao que ultrapassa as precondicoes; ausencia nao implica drift |

### Limite que permanece em G10 (executor nao roda sozinho)

A regra confia no valor DECLARADO em `declared_effects.executes_repository_code`. O defeito
anterior foi exatamente uma declaracao falsa. Logo G10 impede execucao de adaptador
CORRETAMENTE classificado; nao detecta classificacao errada. Contra isso valem revisao de
fonte, mutacao e corpus hostil - nao a regra.

## Adendo 3 - Fase D1: os adaptadores de documento viram mecanismo

O ADR declarava, como limite conhecido: "adaptadores de documento sao especificacao versionada,
nao mecanismo executado; `read-budget.sh` mantem logica propria por extensao". Verificado antes
de agir: `grep -c adapters execution/hooks/read-budget.sh` = 0, e nenhum executor consumia o
diretorio. Especificacao apresentada como mecanismo e o defeito que este repositorio combate.

### O que passou a existir

`execution/document-tools/doctool.sh`, com tres verbos - `probe`, `plans`, `run` - dirigidos
pelo registry `execution/adapters/documents/*.json`. Adicionar um formato e adicionar um JSON.

| Invariante | Motivo |
|---|---|
| D1 sem `sh -c`; placeholders substituidos por VALOR | documento e entrada nao-confiavel; nome de arquivo com `$( )` nao pode virar comando |
| D2 evidence pack ancorado (arquivo, digest, adaptador, plano, linha) | excerto sem ancora nao e evidencia, e alegacao sobre um arquivo |
| D3 todo excerto marcado `untrusted` | conteudo de documento e DADO, jamais POLITICA |
| D4 lacuna declarada | PDF sem OCR devolve `gap`, nunca texto vazio que se leria como "documento sem conteudo" |
| D5 timeout, teto de bytes, diretorio descartavel | o executor nao escreve no diretorio do usuario |

`read-budget.sh` passou a consultar o registry ANTES do `case` embutido: havendo adaptador, a
receita e o executor.

### Medido

- 21 assercoes em 7 cenarios (`tests/unit/document-tools.sh`), com fixtures geradas no proprio
  teste: CSV de 800 linhas, PDF e DOCX via pandoc, PDF sem camada de texto via PyMuPDF.
- Reducao real: `profile` de um CSV de 17.619 bytes emite excerto < 4.000 bytes com shape,
  dtypes, nulos e describe.
- Injecao: PDF contendo "IGNORE AS INSTRUCOES ANTERIORES" sai como excerto marcado
  `untrusted: true`, nunca como instrucao.
- Nome de arquivo `$(touch PWNED_DOCTOOL).csv`: o marcador NAO e criado.

### O que NAO foi feito

- **Cache content-addressed de extracoes.** Cada `run` reprocessa. O digest ja existe no pack;
  falta a camada de cache e sua invalidacao.
- **Sandbox.** Os limites sao timeout, teto de bytes e tmpdir. Nao ha isolamento de filesystem
  nem de rede - `pandoc` e `libreoffice` rodam com a autoridade do usuario.
- **Benchmark pareado.** Os testes provam que o mecanismo funciona e reduz bytes; nao provam
  que a resposta final melhora. Comparar "leitura direta" com "pipeline" exige corpus.
- **OCR e transcricao** seguem como lacunas declaradas.

## Adendo 4 - a regra que eu mesmo reintroduzi

Revisao automatica de commit acusou `unpinned-dep-in-security-gate` em
`.github/workflows/verify.yml`. Confirmado: `pymupdf` sem versao.

E reincidencia. Numa rodada pinei `actions/checkout` por SHA, `ubuntu-24.04`, `ruff`, `pandas` e
`openpyxl`; na rodada seguinte acrescentei `pymupdf` sem versao. Terceira ocorrencia da mesma
classe nesta sessao:

| # | Defeito | Classe |
|---|---|---|
| 1 | adaptador .NET declarava `executes_repository_code: false` | afirmacao sem conferir a fonte |
| 2 | `spreadsheet.json` perdeu a declaracao de dependencias | capacidade afirmada sem declarar o que exige |
| 3 | `pymupdf` sem versao no gate externo | regra propria nao aplicada ao proprio acrescimo |

O padrao e o mesmo: a regra existia, estava escrita, e nao foi executada no acrescimo seguinte.
Enunciar nao executa. Por isso a correcao NAO foi pinar o `pymupdf` - foi transformar a regra
em teste.

`tests/unit/supply-chain.sh`, 5 assercoes:

- S1 toda action pinada por SHA de 40 caracteres, nunca por tag (tag e mutavel);
- S2 todo pacote pip com `==`;
- S3 `runs-on` e imagem nomeada, nunca `-latest`;
- S4 dependencia de sistema nao pinada precisa de `EXCECAO DECLARADA` por escrito - `apt` no
  runner nao tem pinagem estavel, e fixar versao desligaria o gate por ruido a cada atualizacao
  da imagem; a garantia vem da imagem nomeada mais o registro das versoes observadas no log;
- S5 todo pacote que um adaptador declara em `.requires` e instalado pela CI.

### O teste tambem nasceu quebrado

Na primeira versao, S2 PASSOU sobre o workflow com `pymupdf` sem versao: a classe de caracteres
do regex continha `\[\]`, o que a invalidava, e nenhum pacote era extraido. Teste que nao ve o
defeito presente e pior que teste nenhum - foi exatamente assim que o `pymupdf` entrou.
Corrigido e verificado por mutacao: com a dependencia sem pin, a suite sai 1; restaurada, sai 0.

## Adendo 5 - a distincao que faltava: oraculo x ambiente

Revisao independente encontrou, em S5, a mesma estrutura vacua pela quinta vez nesta sessao:

```
packaging ausente -> SKIP -> EXPECTED reduzido -> suite verde (4/4), exit 0
```

Reproduzido antes de corrigir, com um `packaging.py` que lanca ImportError no PYTHONPATH.

A correcao exigiu uma distincao que estava implicita e agora e regra:

| Tipo de pre-requisito | Ausente significa | Tratamento |
|---|---|---|
| **Dependencia do ORACULO** (ex.: `packaging` para comparar specifier) | o teste NAO FOI REALIZADO | reprova a suite: `exit 2`, NAO VERIFICADO |
| **Variacao de AMBIENTE** (ex.: quais locales existem) | uma variante nao pode ser exercitada | `SKIP` explicito, com assercao-guarda exigindo que ao menos uma tenha sido exercitada |

Sem a segunda metade, o SKIP de ambiente recria a mesma estrutura vacua - foi por isso que R1
ganhou "ao menos um locale de ordenacao distinta foi exercitado".

Correcoes: S5 exige `packaging` (exit 2 se faltar), S6 exige que ele esteja pinado no workflow
- do contrario a garantia valeria localmente e seria indefinida no ambiente remoto - e
`EXPECTED=6` fixo, sem reducao dinamica.

Verificado por mutacao: `packaging` ausente -> exit 2; despinado na CI -> exit 1; restaurado -> 0.

### A generalizacao das cinco ocorrencias

```
precondicao falha -> operacao nao executa -> pos-condicao vacuamente verdadeira -> verde
```

| # | Onde | O que nao executou |
|---|---|---|
| 1 | `--dry-run` | o `cd` falhou; a operacao nao rodou e "estado identico" era trivial |
| 2 | locale | `LC_ALL=pt_BR` sem o locale instalado; comparava C consigo mesmo |
| 3 | locale, 2a tentativa | `locale` ECOA o nome pedido mesmo para locale inexistente |
| 4 | matcher do apt | `apt-get -o ... install` nao casava com `"apt-get install"`; o caso sumiu |
| 5 | S5 | `packaging` ausente virava SKIP e o esperado encolhia junto |

O contrato completo de um teste nao e `Q(estado_final)`. E:

```
precondicoes satisfeitas
  E tratamento efetivamente aplicado
  E oraculo capaz de discriminar
  E operacao comprovadamente executada
  E Q(estado_final)
```

As defesas construidas, uma por instancia: exit code como assercao (1), discriminador
comportamental (2, 3), contagem invariante (4), e pre-requisito de oraculo obrigatorio (5).

## Adendo 6 - o drift documental e o defeito que ele revelou

O README afirmava "28 assercoes" com a suite em 29. Pequeno operacionalmente, e a MESMA classe
que originou o projeto: narrativa em copia separada do mecanismo, afastando-se sem sinal.

A correcao nao foi corrigir o numero - foi parar de duplica-lo. `scripts/status.sh` gera
`docs/status.generated.md` a partir de execucao real; o README referencia. `--check` reprova se
o arquivo committado estiver desatualizado, e a CI roda esse check.

### O que o status gerado encontrou no primeiro uso

O script exporta `LC_ALL=C` (identidade nao pode depender de locale, ADR/adendo 3). Sob essa
variavel, `tests/unit/run.sh` reprovou 2 casos que passavam sem ela:

```
PASS  aceita EVIDENCIA acentuada (PT-BR reprovava 25%)     <- sem LC_ALL
FAIL  aceita EVIDENCIA acentuada (PT-BR reprovava 25%)     <- LC_ALL=C
```

Causa: `subagent-contract.sh` normalizava acentos com `sed 'y/.../.../'`, que opera sobre
CARACTERES. Sob `LC_ALL=C` o sed processa BYTES, a transliteracao multi-byte nao acontece, e o
hook voltava a barrar retorno legitimo em PT-BR.

E o defeito do ADR 0018 reaparecendo por outra via: la o padrao era ASCII e o texto acentuado;
aqui a normalizacao existe mas depende do ambiente. **Em produção isso e falso bloqueio**: uma
sessao com locale C rejeitaria todo retorno de subagente com acento.

Corrigido com substituicao LITERAL por byte (`s/Ê/E/g` casa uma sequencia fixa, insensivel a
locale). Regressao R4 exercita o contrato sob `LC_ALL=C` e `en_US.UTF-8`; mutante removendo a
normalizacao de um unico caractere reprova a suite.

Registro do metodo: este defeito nao foi encontrado por leitura nem por revisao. Apareceu
porque um script novo rodou a suite existente sob uma variavel diferente. Terceira vez na
sessao em que **mudar o ambiente** revelou o que o ambiente unico escondia.
