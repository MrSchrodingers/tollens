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

Todo merge para `main` estava garantido a falhar. Nao foi deslize: `verify-push` reprovou em
2026-08-21, 08-24 e 08-25. E a leitura verde que esta sessao publicou duas vezes vinha do run da
BRANCH - `verify-push` da branch e `verify-push` do main sao runs distintos, e so o primeiro foi
olhado. Um relatorio de estado lido no lugar errado e indistinguivel de estado bom.

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

Medido: 933 s -> 393 s localmente (-58%). As onze contagens de mutantes ficaram identicas.

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

## Limites, declarados

`G4`, `G5`, `G6b`, `G7`, `G18`, `G19`, `G20`, `G21` seguem abertos, e `G24` e `G25` entram abertos.

`G6b` DEIXOU DE ESTAR BLOQUEADO, e isso e resultado desta onda: `InstructionsLoaded` existe no
binario 2.1.241 e DISPARA, verificado E2E e nao contra a documentacao. O payload traz `file_path`,
`memory_type` e `load_reason` - exatamente o observavel que separa `installed` de `loaded`. A
justificativa de tres ondas ("nao ha instrumento") era falsa; havia, e ninguem tinha testado.
Implementar `E_A` a partir dele e trabalho da proxima onda, nao desta.

A reducao de 933 s para 393 s foi medida LOCALMENTE. O runner e outro ambiente, e o passo `apt` e
bimodal por medicao propria - a variancia entre runs nao foi caracterizada. Dizer "a CI cai para
19 min" seria extrapolacao; o que se sustenta e que a reexecucao saiu.
