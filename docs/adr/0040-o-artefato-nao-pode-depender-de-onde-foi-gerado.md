# ADR 0040 - O artefato nao pode depender de onde foi gerado

Data: 2026-08-25
Estado: aceito
Sucede: ADR 0039 (o denominador e a procedencia)

## Contexto

Esta onda comecou por uma pergunta do operador que nenhuma das sete rodadas de auditoria tinha
feito: *"por que nao esta inteiramente deployado na maquina local, forcando todos os Claude Code a
usar?"*. A resposta exigiu medir a diferenca entre INSTALADO e IMPOSTO, e a medicao encontrou
quatro defeitos, um deles com `main` vermelho havia tres merges.

## **G22** - `main` estava vermelho, e a causa era o artefato depender do contexto

```
em branch (arvore difere da base)   TOTAL=31
em main   (arvore identica a base)  TOTAL=29
```

`tests/unit/capability-conformance.py` emite duas assercoes a menos quando a arvore e IDENTICA a
`origin/main`: as comparacoes contra a base viram `NAO VERIFICADO` - "arvore identica a base, nada
a discriminar" - em vez de `PASS`. Isso esta CORRETO como oraculo. O defeito e o consumidor:

```
docs/status.generated.md          grava 31, porque foi gerado na branch
scripts/status.sh --check         compara BYTE A BYTE, e em main mede 29
```

Todo merge para `main` estava garantido a falhar. E a leitura verde que esta sessao publicou duas
vezes vinha do run da BRANCH - `verify-push` da branch e `verify-push` do main sao runs distintos,
e so o primeiro foi olhado. Um relatorio de estado lido no lugar errado e indistinguivel de estado
bom.

> **ERRATA, onda 21b (`revisor-codigo`).** A primeira versao deste ADR dizia "tres merges" e
> "reprovou em 2026-08-21, 08-24 e 08-25". Sao **SEIS**, e o mais antigo e de 2026-08-19:
>
> ```
> failure 2026-08-25 da895481 PR #29     failure 2026-08-20 ec943c12 PR #26
> failure 2026-08-24 6e144fd8 PR #28     failure 2026-08-20 88cd17e6 PR #25
> failure 2026-08-21 ac0cb446 PR #27     failure 2026-08-19 0c41e78d PR #24
> success 2026-08-19 7ccf4945 PR #23
> ```
>
> Todas no mesmo passo. E o run mais antigo traz um TERCEIRO valor - `30`, nao `31` -, o que
> refuta a formulacao "31 na branch, 29 em main" como se fossem os dois unicos estados: a
> contagem varia com o quanto a arvore difere da base, nao entre dois valores fixos. Errar um
> numero por fator dois num ADR deste repositorio e a classe que a onda 20 inteira corrigiu, e
> aqui ela reapareceu na propria correcao dela.

    NumeroObservado(contexto)  DIFERENTE DE  Invariante

A correcao e a que o proprio arquivo ja aplicava a `managed-root-trust.sh` (sudo) e a `run.sh`
(ambiente): rotulo constante. Contagem que depende do contexto de observacao nao pode ser gravada
como invariante num artefato conferido por igualdade de bytes.

Medido depois do fix, e esta e a assercao que importa:

```
digest gerado em main    8f00d0c8f85eca313e142b0595404cbffb5500b7
digest gerado na branch  8f00d0c8f85eca313e142b0595404cbffb5500b7
status.sh --check em main   rc=0
```

## **G23** - metade da CI era reexecucao, e o argumento contra ela ja estava no arquivo

```
verify-pr, run 32795311156
  passo 16  scripts/status.sh --check   933 s
  outros 44 passos somados              949 s
  total                                1882 s      -> 49,6% num passo so
```

Duas causas, as duas medidas e nao inferidas.

**Dupla execucao.** `status.sh` rodava a suite para colher o `rc` e chamava `conta()`, que rodava a
MESMA SUITE DE NOVO para extrair `PASS=N`. Provado por experimento com suite instrumentada que
conta invocacoes: 2 execucoes para as 18 suites sem o marcador de ambiente, 1 para as 2 que o tem.
Custo ~125 s.

**Dez arneses reexecutados.** Os dez consomem 624 s e TODOS tem passo dedicado no workflow; aqui o
exit code so era reimpresso numa tabela markdown. O argumento para nao executar ja estava escrito
neste mesmo arquivo, duas vezes - para `install.sh` e para a varredura automatica: *"rodar a suite
e descartar o `$?` e execucao que nao produz sinal algum"*. Enunciar a regra nao a executa.

O rotulo e COMPUTADO: confere no workflow que o passo existe e imprime `NAO executado no CI` quando
falta. A onda 15 ja pagou por publicar essa frase sem conferir.

Medido, e as duas medidas NAO sao comparaveis entre si:

```
933 s   passo 16 do run 32795311156, no runner   (o "antes", em CI)
338 s   `status.sh --check` nesta estacao        (o "depois", local, medido pelo refutador)
393 s   idem, outra execucao                     (variancia local nao caracterizada)
```

**As versoes anteriores publicaram `-58%`, e esse numero nao existe.** Ele saia de dividir um
"depois" local por um "antes" de CI. Nao ha, em lugar nenhum deste repositorio, medicao LOCAL do
antes. E a decomposicao do proprio repo discorda: 624 s de arneses mais ~125 s de dupla execucao
sao 749 s de 933 s, o que projetaria ~-80% no CI - nao -58%. Duas linhas deste ADR chegaram a se
contradizer, uma atribuindo os 933 s ao CI e outra dizendo que a reducao "foi medida LOCALMENTE".

O que se sustenta: o passo custava 933 s de 1882 s no CI; a reexecucao saiu; localmente o gerador
roda em 338-393 s; **o efeito no CI nao foi medido**. As onze contagens de mutantes ficaram
identicas.

## **G24** - instalado nao e imposto, e 35 de 49 componentes sao gravaveis pelo ator

ABERTO.

```
IMPOSTO por root    /etc/claude-code/managed-settings.json  root:root
                    /opt/tollens/hooks/*.sh                 14 hooks, root-only

GRAVAVEL PELO ATOR  agent 10 | skill 8 | adapter 11 | doctool 5 | config 1   = 35 de 49
```

O `config: 1` e `~/.claude/CLAUDE.md`: **a regra que governa o ator e gravavel por ele**. E `D_MAX`
na camada mais externa - a mesma forma que a onda 14 removeu do teto, a 17 do token de citacao, a
19 do `state` e a 20 do `agent`. Sete rodadas de auditoria externa nao a tocaram, e o proprio
`install/verify.sh` a declara em toda execucao: `governed=user - politica ainda gravavel pelo ator`.
`conforme` sempre significou "os digests batem", nunca "nao pode ser alterado".

## **G25** - o escopo managed executa codigo do ator

ABERTO, e e o mais grave desta onda.

```
/opt/tollens/hooks/read-budget.sh:90     root-owned, imposto por managed-settings
  DOCTOOL="${DOCTOOL_BIN:-$HOME/.claude/tollens/document-tools/doctool.sh}"

resolve para  /home/ti/.claude/tollens/document-tools/doctool.sh
dono          ti:ti   -rwxr-xr-x   GRAVAVEL PELO ATOR
DOCTOOL_BIN no ambiente: 0    (nenhum override existe)
```

Um hook root-owned executa um script que o ator pode reescrever. A unica camada que o ator nao
controla depende de um arquivo que ele controla. E `read-budget.sh:91`, o fallback que deveria
proteger, resolve para `~/.claude/document-tools` - caminho que NAO existe, porque o real e
`~/.claude/tollens/document-tools`. Protecao que nao protege, e que so nao falha porque a linha 90
acerta.

Nao corrigido aqui: e mudanca de fronteira de confianca, exige `auditor-seguranca` antes do portao
final, e merece PR proprio. Registrado para nao virar "sempre foi assim".

## **G26** - `find` falha aberta nesta maquina, e eu conclui duas vezes a partir dela

```
$ find ~/.claude/agents -type f -newermt '-7 days'
bfs: error: ... -newermt "-7 days"
rc=0
```

O `find` desta maquina e `bfs`, e `-newermt '-7 days'` e ERRO DE PARSE que sai `rc=0`. Duas
medicoes desta sessao concluiram "0 escritas em 7 dias" a partir do vazio produzido por esse erro.
So foi pego por conferir contra um `-mmin` que achava 700 arquivos.

E a mesma familia do `grep -P` sob `LC_ALL=C` que a onda 16 achou no portao de emoji: ferramenta
que falha aberta, em silencio, e cuja saida vazia se le como resposta. O `refutador` cometeu a
versao dele no mesmo dia - `grep -E '[^\n]*'` exclui a letra `n` literal, e o falso-negativo quase
declarou um portao vivo como orfao.

## **G27** - o detector desta classe so roda DEPOIS do merge, e a lista e curada a mao

ABERTO, e o `revisor-codigo` o nomeou com precisao: **`verify-pr` nao pode reproduzir a condicao**
"arvore identica a `origin/main`", porque um PR por definicao difere da base. Confirmado nesta
branch: `TOTAL=31`. O unico detector da classe e o `verify-push` POS-MERGE - que e exatamente como
este defeito nasceu e sobreviveu a seis merges.

E a lista `BASE_DEPENDENTE` e digitada a mao num arquivo que argumenta contra listas digitadas a
mao. Tres detectores derivaveis foram tentados e MEDIDOS como insuficientes (o raciocinio esta no
proprio `scripts/status.sh`): grep de `NAO VERIFICADO` no fonte casa 18 das 20 suites; o mesmo grep
na saida capturada e assimetrico entre branch e main; e a contagem estatica de `chk` contra
`PASS+FAIL` nao discrimina - `hooks-de-guarda` deu 46=46 nesta estacao.

O fecho e a suite publicar contagem INVARIANTE (`PASS+FAIL+SKIP`), o que toca as 18 suites com
caminho de pulo. Nao feito aqui: seria taxonomia dentro de um patch, o erro que o ADR 0037
registrou.

## O que o `refutador` derrubou, e o que a onda 21c corrigiu

**A afirmacao "nao existe detector derivavel" era FALSA.** As ondas 21 e 21b publicaram, aqui e no
`scripts/status.sh`, que tres detectores foram tentados e nenhum se sustenta. Isso e claim de
EXISTENCIA, e o `refutador` produziu o quarto: **a suite fixa e impoe a propria contagem?**

```
EXPECTED=<literal> + exit 1     publica o numero - desvio ja e vermelho na suite
EXPECTED=$((...))               `variavel (ambiente)`
sem pino                        `variavel (base)`
```

Medido nas 20: 14 literal, 2 dinamicas, 4 sem pino - e as 4 CONTEM as 2 da lista curada. Zero
falsos negativos. Ele e propriedade ESTATICA DO FONTE, logo simetrico entre branch e main, que era
o furo do detector que lia a saida. E o erro dos tres anteriores era medir a coisa errada: nao
importa QUANTO a suite conta, importa se ela se AUTOFIXA.

A lista curada saiu. As duas suites sem pino que restavam - `fronteira-externa.sh` e
`contrato-de-instalador.sh` - receberam pino (13 e 34, medidos), o que as torna verificaveis em
vez de presumidas.

**A garantia da onda 21 nao tinha oraculo, e agora tem.** Esvaziar a lista e regenerar o artefato
passaria no `verify-pr` - um PR por definicao difere da base - e so o `verify-push` pos-merge
reprovaria. Foi assim que o defeito sobreviveu a seis merges. `tests/unit/regressao-gate.sh` passou
a exigir, em tempo estatico, que nenhuma suite sem pino publique numero. Validado por mutacao:
removido o `EXPECTED=54` de `claims.sh`, o oraculo reprova nomeando a suite.

**`F4`, que nenhum outro revisor viu.** A lista curada introduzia uma SEGUNDA ocorrencia textual de
duas suites dentro de `status.sh`, numa string de DADOS. O portao
`tests/unit/capability-conformance.py:485-488` usa `ref in _ger` - substring do arquivo - como
proxy de "foi executada pelo gerador". Medido pelo `refutador`: removendo so a linha do laco, o
portao continuava creditando `E_M`, e **13 das 17 evidencias `executed_suite` pagas apontam para
`hooks-de-guarda.sh`**, que nao tem passo dedicado em nenhum workflow. Era "mencao nao e execucao"
reintroduzido dentro do arquivo que persegue essa forma. Remover a lista fechou isso.

## Limites, declarados

`G4`, `G5`, `G6b`, `G7`, `G18`, `G19`, `G20`, `G21` seguem abertos, e `G24` e `G25` entram abertos.

`G6b` DEIXOU DE ESTAR BLOQUEADO, e isso e resultado desta onda: `InstructionsLoaded` existe no
binario 2.1.241 e DISPARA, verificado E2E e nao contra a documentacao. O payload traz `file_path`,
`memory_type` e `load_reason` - exatamente o observavel que separa `installed` de `loaded`. A
justificativa de tres ondas ("nao ha instrumento") era falsa; havia, e ninguem tinha testado.
Implementar `E_A` a partir dele e trabalho da proxima onda, nao desta.

O efeito no CI NAO foi medido - ver a errata do `G23`. O runner e outro ambiente, o passo `apt` e
bimodal por medicao propria, e a variancia local tambem nao foi caracterizada (338 s e 393 s em
duas execucoes). Dizer "-58%" ou "a CI cai para 19 min" e extrapolacao; o que se sustenta e que a
reexecucao saiu.
