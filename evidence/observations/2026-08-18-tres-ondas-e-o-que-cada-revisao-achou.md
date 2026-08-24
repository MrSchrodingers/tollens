# Observacao - tres ondas em uma sessao, e o que cada camada de revisao encontrou

- Data: 2026-08-18
- Ambiente: Linux, `claude-code 2.1.234`, repositorio `MrSchrodingers/tollens`
- Cobre: ondas 11 (arena), 12 (referencia que nao resolve) e 13 (estado nao e diretorio)
- Fecha: o registro de metodo que os ADR 0031, 0032 e 0033 referenciam sem duplicar

---

## 1. Por que esta observacao existe

Os ADR registram DECISAO. Esta observacao registra o PROCESSO que as produziu, porque o dado
mais util da sessao nao esta em nenhum dos tres: e a distribuicao dos defeitos por camada de
revisao, e ela e contra-intuitiva.

Nenhum numero aqui e estimado. Cada um vem de execucao colada no transcript da sessao.

---

## 2. O que foi feito, por onda

### Onda 11 - arena de mutacao

Os treze arneses de `tests/mutation/` mutavam arquivos de PRODUCAO na arvore de trabalho e
restauravam no `trap`. Restauracao e uma propriedade; isolamento e outra:

```
EventuallyRestored  NAO IMPLICA  NeverObservableAsMutant
```

Seis incidentes medidos em dois dias decorreram da janela entre mutar e restaurar, incluindo
`install/manifest.sh` gravando o digest de um MUTANTE como estado desejado do sistema.

`tests/lib/arena.sh` passa a copiar a arvore para `$TMPDIR` e fazer `cd`. `git worktree` foi
rejeitado por tres razoes medidas nesta estacao.

### Onda 12 - referencia publicada que nao resolve

Quatro classes fechadas:

| classe | evidencia |
|---|---|
| portao lia 1 arquivo por skill | `TOTAL=50 FAIL=0` com 4 referencias mortas em `references/` da skill que ele governa |
| comando publicado inexistente | `bash scripts/medir-skills.sh` -> `No such file or directory` |
| `Diretriz N` a secao movida | 8 citacoes: 3 para secao inexistente, 5 resolvendo para secao que diz OUTRA COISA |
| projecao sem chave de roteamento | 10 de 10 com `description: "Projecao do agente canonico <nome>"` |

A varredura ampla rendeu 28 achados para 2 defeitos. Os 26 restantes eram registro datado
(`docs/adr/**`), exemplo ilustrativo ou caminho de outro projeto - classes que NAO se corrige.
Um "atualize tudo" literal teria falsificado 12 ADR e quebrado 14 exemplos corretos.

O `CLAUDE.md` global entrou no manifesto como tipo `config` (49 componentes), semeado
byte-exato para o primeiro `apply` ser no-op comprovado.

### Onda 13 - estado nao e nome de diretorio

`state` vira metadado em `orchestration/registry.json:capabilities`; o instalador le o registry
em vez do glob; nasce `tests/unit/capability-conformance.py`, que afere ARTEFATO contra POLICY;
as oito skills sao reclassificadas para `candidate` SEM desinstalar; `defesa-de-tese` sai da
arvore ativa e vira tombstone.

---

## 3. O achado estrutural que organiza as tres ondas

Uma unica forma se repete, subindo um nivel por onda:

```
onda 11   o experimento observava a arvore errada
onda 12   o portao lia o arquivo errado
onda 13   o portao aferia a POLICY, nao o ARTEFATO
```

Na onda 13 a forma fica nitida:

```
PolicyDeclared  NAO IMPLICA  PolicyApplied
```

`orchestration/skill-policy.json` declarava cinco estados e sete `promotion_requires`. Oito
skills viviam em `execution/skills/promoted/`, ZERO declarando estado, ZERO com dossie, e
`python3 tests/unit/methodology.py` -> `TOTAL=53 FAIL=0`. `promoted` era **inferido de um nome
de diretorio**.

---

## 4. A distribuicao dos defeitos por camada, que e o dado principal

Tres camadas de revisao independentes acharam conjuntos **disjuntos**. Contagem por onda,
apenas de achados que exigiram correcao:

| camada | o que ela faz | achados |
|---|---|---|
| `revisor-codigo` | le o diff, cruza texto com codigo | contradicao ata-commit, backup ausente, regressao de contrato de argumento, heredoc silencioso, wiring de interpretador |
| `auditor-seguranca` | EXECUTA o codigo contra alvo hostil | `rm -rf` de diretorio arbitrario via symlink em `/tmp` 1777 |
| `refutador` | REFAZ as medicoes em vez de aceita-las | teto que nao congela, mutantes irreproduziveis, guarda tautologica, manifesto truncado |

**O `rm -rf` so apareceu porque alguem plantou um symlink e executou o bloco literal.** Leitura
de diff nao o encontrou em duas passadas. Ele era pre-existente da onda 11 e vivia noventa
linhas acima do defeito que a onda 12 estava corrigindo, no mesmo arquivo.

Consequencia de metodo, e ela nao depende deste repositorio: **cobertura de revisao nao e
quantidade, e heterogeneidade de modo**. Ler, executar hostilmente e refazer a medicao sao
oraculos diferentes; nenhum substitui os outros.

---

## 5. Defeitos introduzidos pelas proprias correcoes

Sinal degenerativo observado nas tres ondas: correcao N+1 na mesma regiao introduz defeito novo.

Onda 11: os tres bloqueantes do portao final estavam DENTRO das correcoes dos tres criticos da
revisao anterior. Um deles - `trap` sem `exit` - trocou "morre deixando mutante" por "ignora o
sinal e continua mutando".

Onda 12: o endurecimento de `apply-managed.sh` quebrou `--dry-run` e `--enforce`, isto e, o
unico passo publicado que liga `allowManagedHooksOnly`. **Endurecimento que empurra o operador
para fora do mecanismo de seguranca e regressao de seguranca**, porque ele passaria a chamar o
worker direto, pulando snapshot, rollback e a checagem de raiz root-owned do ADR 0026.

Onda 13: o teto `D_MAX`, publicado no ADR como "o mecanismo que faltava", nao congelava nada.
`D_E` contava `{candidate, promoted}` e a policy declara `initial_state: quarantine` - o estado
em que toda capability NASCE ficava fora da contagem. A proibicao escrita no cabecalho
("nunca levantar o teto") foi redigida contra o ataque errado: ninguem precisava levantar o
teto, bastava usar o estado default.

---

## 6. Erros de afirmacao, e a direcao deles

Duas afirmacoes falsas sobre o proprio repositorio foram feitas e corrigidas por revisao
externa. Ambas na mesma direcao:

| afirmado | real |
|---|---|
| "`methodology.py` nunca abre um artefato de skill" | abre: itera as promovidas e le cada `.md` - inclusive por codigo escrito na mesma sessao |
| "8 de 10 agentes nao podem escrever" | 8 de 10 nao recebem `Write`/`Edit`; os 10 tem `Bash`, logo nenhum e tecnicamente read-only |

As duas INFLAM a garantia do repositorio. Nao e ruido aleatorio: e vies na direcao favoravel ao
objeto que se estava defendendo. A segunda tem consequencia de modelo de confianca que nenhuma
das partes tinha nomeado - **o argumento de revisao independente pressupoe que o revisor nao
possa adulterar o objeto revisado, e com `Bash` ele pode**. A independencia e procedimental,
nao isolada. O repositorio ja registrava isso em `execution/agents/refutador.md`, secao
"Read-only e CONTRATO, nao sandbox".

---

## 7. Sonda de runtime: o que a doc promete e o binario nao confirmou

A doc do Claude Code documenta `InstructionsLoaded`, `ConfigChange`, `FileChanged`,
`PostToolBatch` e `WorktreeCreate`, e `ConfigChange` aceita bloqueio com matchers que incluem
`policy_settings`. Isso foi conferido verbatim na fonte.

Sonda E2E contra o binario `2.1.234`, projeto com `CLAUDE.md` presente, via
`--include-hook-events`:

```
emitidos ............ SessionStart, UserPromptSubmit, Stop
InstructionsLoaded .. AUSENTE
```

**Limite declarado, e ele e serio:** nao foi possivel fazer um hook registrado via `--settings`
EXECUTAR - nem `SessionStart`, que sabidamente funciona. Tres tentativas, todas vacuas ate a
troca do metodo de marcador para o stream de introspecao. Logo o resultado esta mais proximo de
"nao sei medir" do que de "medi e nao esta la".

Veredito: `NOT_VERIFIED`. A cadeia `registration -> event production -> observation ->
enforcement` nao foi reproduzida, e por isso `ConfigChange` NAO foi promovido a mecanismo de
seguranca nesta sessao, apesar de ser a peca de maior retorno por esforco identificada.

---

## 8. Estado ao final

```
componentes governados ...... 49  (adapter 11, agent 10, config 1, doctool 5, hook 14, skill 8)
conformidade ................ 49/49 ok | 0 divergentes | 0 ausentes | 0 orfaos
skills instaladas ........... 8, todas state=candidate, installed=true
divida de avaliacao D_E ..... 8, teto D_MAX=8
capabilities com dossie ..... 0
agentes com dossie .......... 0
```

`D_E` conta apenas skills. Os dez agentes tampouco tem dossie; se a mesma regra for estendida a
eles, a divida real e 18. Isso NAO esta implementado e fica registrado como divida.

---

## 9. O que permanece NOT_VERIFIED

**A eficacia externa do harness.** E ha um argumento estrutural, nao apenas ausencia de
execucao: a literatura disponivel mede pass rate, falha funcional e regressao de eficiencia.
Nenhum trabalho conhecido mede

```
P(agente declara sucesso | verificador reprova)
```

que e a propriedade que este harness alega comprar. Num benchmark que pontua "a tarefa passou",
um harness que se recusa a declarar pronto sem evidencia aparece como CUSTO PURO. Os trabalhos
existentes limitam bem o custo do procedimento e sao estruturalmente silenciosos sobre o
beneficio.

Dimensionamento, para quando o experimento existir: o spread de harness medido em
arXiv:2606.12344 sobre o MESMO modelo (GLM 5.1) e de **12,5 pp** (60,9 -> 73,4), contra 29,4 pp
de spread de modelo. O numero `19,1 -> 73,4` do abstract e o extremo entre adapter minimo e
completo, e os 27,4 pp sao o maximo sobre dois modelos. Um experimento dimensionado para 25-30
pp devolveria `p > 0,05` por subpotencia e produziria o pior desfecho possivel: um
`NOT_VERIFIED` que se le como refutacao.

Tambem permanece nao verificado: se o runtime de fato usa `description` para rotear (a
afirmacao vem da doc primaria, nao de sonda), e a cadeia de enforcement dos cinco eventos novos.

---

## 10. O que este registro NAO afirma

Nao afirma que o harness funciona. Afirma que ele **falsifica os proprios claims com
frequencia mensuravel** - o que e propriedade diferente e mais fraca:

```
F_interno > 0        medido, com corpus
Delta Q_externo > 0  NAO VERIFICADO
```

Confundir as duas seria exatamente o erro que as tres ondas existem para tornar dificil.

---

## ERRATA - 2026-08-19

Este registro e datado e nao se reescreve; o que segue corrige, sem apagar, duas afirmacoes da
secao 8 que as ondas 14 e 15 tornaram falsas.

**1. `teto D_MAX=8` deixou de existir.** A onda 14 removeu o teto depois de a auditoria externa
medir duas fugas: o mesmo PR podia adicionar capability e elevar a constante, e pagar um dossie
abria vaga para outra divida entrar sem que o numero subisse. A fronteira passou a ser relacional
contra o SHA-base. Ver ADR 0034.

**2. `a divida real e 18` era piso de UMA leitura, e a leitura estava errada em forma, nao so em
tamanho.** A onda 15 decompos a divida em quatro dimensoes com obrigacao de prova por tipo de
capability. Medido depois da decomposicao:

```
D_E = 89 obrigacoes em aberto sobre 34 capabilities
      E_M 18   E_U 25   E_C 25   E_S 21
```

> **ERRATA, onda 20 (`G17`).** O `34` desta linha e o denominador defeituoso que a onda 20
> corrigiu: `_divida` varria 33 registros e a linha dividia por `len(caps)` = 34, que inclui o
> tombstone `defesa-de-tese`. A medicao datada fica como foi observada; o ponteiro e para o
> ADR 0035, que publica a leitura corrente - 89 obrigacoes sobre 28 capabilities endividadas,
> 33 varridas, 34 entries. Ate esta onda o repositorio publicava 33 no ADR e 34 aqui para a
> MESMA medicao, sem ponteiro entre as duas.

O `18` reaparece, e nao por coincidencia: e exatamente a divida de E_M das 8 skills e dos 10
agentes. O que a frase original nao via e que os catorze hooks deviam prova de OUTRAS dimensoes,
e que oito deles nao tinham sequer E_M - nenhuma suite os executava. Ver ADR 0035.

O numero subiu de 8 para 89 porque a medicao melhorou, nao porque o estado piorou. Um instrumento
que so melhora quando o numero cai mede o numero, nao o fenomeno.
