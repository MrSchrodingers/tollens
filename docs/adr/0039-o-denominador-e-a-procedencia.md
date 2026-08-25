# ADR 0039 - O denominador que nao media o numerador, e a procedencia que ninguem conferia

Data: 2026-08-24
Estado: aceito
Sucede: ADR 0038 (referencia que resolve, e estado que nao e prosa)

## Contexto

A onda 19 corrigiu, na PROSA do relatorio, uma leitura que a revisao externa apontou: `34
capabilities` sao 34 ENTRIES do registry - 33 governadas mais o tombstone `defesa-de-tese` -, e
sem a nota o numero sugere 34 componentes ativos. Aquela correcao foi publicada sem
`finding_id`, e este ADR a registra em atraso como `G16`. A razao de registra-la esta na secao
sobre selecao retrospectiva, adiante.

Aplicar `G16` exigia conferir o numero na FONTE, e foi ai que a onda comecou.

## **G17** - o denominador nao media o numerador

`_divida` percorre so as capabilities em estado de divida:

```
capability-conformance.py:501   if cap.get("state") not in _EM_DIVIDA: continue
capability-conformance.py:448   _EM_DIVIDA = {"quarantine", "candidate", "promoted"}
```

e a linha impressa dividia por `len(caps)`:

```
D_E(head)=89 obrigacoes em aberto sobre 34 capabilities
registry: Counter({'candidate': 33, 'deprecated': 1})
```

Numerador de 33, denominador de 34, na mesma frase. A leitura que a revisao externa corrigiu na
prosa estava tambem na saida do instrumento que a mede.

### A primeira correcao fechava a realizacao, nao a classe

O primeiro PR desta onda trocou `34` por `33` e declarou o assunto encerrado. O `refutador`, lendo
o diff cru, mediu o que sobrava:

```
pares (capability, dimensao) em aberto : 89
capabilities DISTINTAS com >=1 aberta  : 28
em estado de divida                    : 33
entries no registry                    : 34
em divida SEM obrigacao aberta         : ['artifact-discipline.sh', 'ds4-notify.sh',
                                          'fable-guard.sh', 'poka-yoke-lint.sh',
                                          'subagent-probe.sh']
```

"89 obrigacoes sobre 33 capabilities" convida a ler "33 capabilities tem divida". Sao 28. A onda
inteira existe porque UM denominador foi lido como populacao ativa; publicar outro denominador
ambiguo teria trocado a realizacao do mesmo defeito - a forma que este repositorio vem eliminando
desde o `D_MAX`, aparecendo agora dentro da correcao contra ela.

Uma versao anterior deste paragrafo dizia "pela oitava vez". O numero nao e derivado de nada: o
`refutador` procurou a enumeracao e o contador explicito mais alto do repositorio e `0035:464`,
"quarto nivel". Afirmar 8 era exatamente o que a secao 2 do CLAUDE.md proibe, num ADR sobre
numeros que nao medem o que dizem medir. Removido, e nao substituido por outro numero - a
enumeracao nao existe.

A linha passou a publicar as tres populacoes e a relacao entre elas, e o numero que a frase
promete e o que ela mede:

```
D_E(head)=89 obrigacoes em aberto sobre 28 capabilities endividadas
populacao: 28 endividadas <= 33 varridas (estado em [...]) <= 34 entries no registry
```

### Severidade, dita com precisao porque a primeira versao errou aqui

Defeito de EXIBICAO, nao de assercao. As **oito** assercoes de CC4 comparam CONJUNTOS de pares
`(capability, dimensao)` e cardinalidades desses conjuntos; nenhuma le esse denominador. Os unicos
leitores de `len(caps)` em assercao sao `len(caps) > 0` e `len(caps) >= 5`, satisfeitos por 28,
por 33 e por 34. Nenhum veredito ja publicado por este repositorio muda.

A primeira versao da errata dizia "as duas checagens de CC4" - errado por fator quatro, num
documento cuja tese e que a descricao tem de bater com o que o instrumento faz.

### A propagacao foi pega pelo portao, a que ele alcanca

```
FAIL ADR 0035 publica D_E=89/34 e o portao mede 89/33
```

O que o portao NAO alcanca foi achado por leitura: `0035:463` publicava "`E_U` esta em aberto para
as 34 capabilities" - claim em presente, nao saida datada, e a mesma leitura errada doze linhas
abaixo da errata que a condena. `E_U` e obrigacao de 25 registros e esta aberta nos 25. E
`evidence/observations/2026-08-18:245` seguia publicando `34` para a mesma medicao, sem ponteiro.
Corrigir a instancia que um portao le e deixar a que nenhum portao le e a forma reduzida do mesmo
defeito.

Duas saidas datadas do ADR 0035 (`D_E(head)=0 ... sobre 34` e `D_E(head)=89 ... sobre 35`) ficam
como foram observadas, com nota de que usam o formato anterior. Reescrever observacao datada e
falsificacao de evidencia, nao correcao.

## **G18** - o ADR 0035 e espelho vivo do head, e isso nunca foi nomeado

ABERTO. `governance-links.py:121` obriga o ADR 0035 a publicar o D_E que o portao mede AGORA.
Aquele bloco, portanto, nao e registro datado: e espelho do head com aparencia de registro
datado. Qualquer mudanca de D_E - registrar capability, pagar dimensao, mexer em `_EM_DIVIDA` -
reprova o portao ate o ADR ser reeditado. Aconteceu duas vezes nesta onda.

O commit desta onda chegou a invocar "reescrever observacao datada e falsificacao" para justificar
nao tocar em nada, enquanto reescrevia a unica instancia que um portao forca. O criterio aplicado
nao era o principio: era o portao.

Nao fechado aqui. Ou o ADR publica o valor DATADO e um artefato gerado espelha o head, ou o portao
passa a conferir o gerado. E mudanca de contrato, nao correcao, e faze-la dentro deste patch seria
o mesmo erro que o ADR 0037 registrou ao adiar a taxonomia de capability.

## O portao de procedencia, e por que ele veio do premortem

O `refutador` recebeu seis pontos de ataque e derrubou dois que nao estavam na lista. No
contrafactual - "qual modo de erro NENHUM dos seis pegava?" - ele nomeou:

```
nada ligava `mode` a `found_by`
```

O corpus define `modes["leitura-estrutural"] = "Le o diff e cruza o texto com o codigo. Agente
`revisor-codigo`."` e o portao validava apenas que a CHAVE existisse. `G17` tinha entrado com esse
modo e `found_by` diferente: releitura da sessao principal publicada como output de um agente que
nao rodou, no unico campo do corpus que serve de comparacao entre modos de revisao, e que
`render.py` rende em `counts_by_mode`.

### A primeira versao do portao era `G12a`, na correcao que cita `G12a`

Ela lia o vinculo da PROSA: `re.compile(r"Agente \`([^\`]+)\`")` sobre a descricao do modo. O
`refutador` derrubou em tres direcoes, todas medidas em clone:

```
falso negativo   5 reescritas plausiveis (sem crases, com dois-pontos, em minuscula, outra
                 formulacao, aspas tipograficas) -> exit=0 com atribuicao falsa plantada,
                 e o contador da linha caindo de 3 para 2 modos com agente, sem assercao
falso positivo   1 frase explicativa acrescentada a outro modo -> 23 achados corretos reprovados
bomba armada     a descricao do modo NOVO desta onda contem "agente `revisor-codigo`" em prosa;
                 so a MINUSCULA impedia o casamento -> uma maiuscula reprovava o achado
                 principal da onda que construiu o portao
```

O ADR 0037 ja tinha julgado essa forma: *"O mecanismo e um LINT DE REALIZACOES LEXICAIS, nao um
detector semantico. Quatro reformulacoes triviais passavam. A frase do ADR prometia a classe e
entregava uma lista."* Esta versao prometia a classe e entregava a lista dos modos cuja descricao
contem a subcadeia `` Agente `x` `` - e achou-se uma reescrita a mais que no `G12a` original.

O erro estava no FORMATO, e a inversao que o corrige ja e doutrina deste repositorio desde a onda
18, escrita no cabecalho de `evidence/corpus/render.py`:

```
antes   vinculo escrito em prosa -> regex tenta descobrir se esta la
agora   vinculo E campo (`agent`), `null` quando o modo nao tem agente
```

`modes` deixou de ser `{nome: "descricao"}` e passou a ser `{nome: {"agent": ..., "desc": ...}}`.
Nenhuma prosa e interpretada; mencionar um agente numa descricao voltou a ser prosa inofensiva.

A regra: modo com `agent` obriga `found_by` igual; modo com `agent: null` obriga `found_by` igual
ao PROPRIO MODO - o que nao e a mesma coisa que obrigar a nomear um agente, e essa distincao e o
que impede a regra de virar o defeito simetrico. `MCC17` mata a atribuicao falsa, `MCC18` e o
controle: modo novo sem agente entra sem precisar inventar procedencia.

### A vacuidade tinha uma terceira realizacao, e a primeira correcao dela nao mordia

O `refutador` mediu, contra a versao com campo estruturado:

```
V1   leitura-estrutural -> agent: null, + atribuicao falsa   -> exit=0 PASS  (20 dos 65 achados
                                                                sem checagem)
V2   leitura-estrutural -> agent: ""   , + atribuicao falsa   -> exit=0 PASS
V3   TODOS os modos -> agent: ""                              -> exit=1  (a guarda usava None)
```

`V2` e pior em especie: `agent: ""` sobrevive a guarda de omissao - a chave EXISTE - e mesmo assim
cai fora do conjunto verificado, porque o teste era de veracidade e nao de tipo. Le-se como
declaracao, age como ausencia.

Duas guardas novas, com ALCANCES DIFERENTES, e dizer que uma cobre a outra seria a amplitude que
esta onda corrige:

1. **Coerencia interna, que vale AGORA.** Modo com `agent: null` cujos achados nomeiam outra coisa
   que nao o proprio modo esta se contradizendo: ou tem agente e deve declara-lo, ou o `found_by`
   esta errado. Nao ha terceira leitura. `MCC21` e `MCC22`.
2. **Ancora na arvore base**, o mesmo principio da onda 14: modo que tinha `agent` na base nao
   pode perde-lo no head. LIMITE, dito porque a versao anterior deste ADR erraria aqui: a base de
   hoje traz `modes` como STRING, anterior ao campo que este PR introduz, entao esta guarda nao
   morde nesta onda: ela fecha a partir do proximo commit. Quem fecha o buraco hoje e a coerencia
   interna. E por isso ela imprime `NAO VERIFICADO`, e nao `PASS` - um PASS que se sabe vacuo
   seria a unica linha da saida a afirmar mais do que mede, que e o defeito desta onda inteira.

E o que NENHUMA das duas fecha, declarado porque o `refutador` o realizou com exit code: trocar a
CHAVE em vez do valor. Reclassificar o `mode` de um achado, ou criar um modo sem agente e migrar
achados para ele, sai `rc=0` - o registro fica coerente e falso. E o `C1` do ADR 0035 aplicado ao
corpus em vez do registry. A ancora de `mode` contra a base fecha isso, e so pode ser construida
depois que a base carregar o schema estruturado - a mesma janela da guarda 2.

### `desc` tinha virado campo sem leitor

Consequencia medida da propria correcao: ao tirar o vinculo da prosa, `desc` ficou sem nenhum
consumidor no repositorio - antes a regex ao menos o lia, mal. Campo que ninguem le apodrece.
`render.py` passou a imprimir a taxonomia com agente e descricao, o que deslocou seis isencoes de
cobertura ancoradas por NUMERO DE LINHA (+12) e subiu a cobertura de 93,0 para 93,6. As duas
coisas foram corrigidas na fonte: ancoras realinhadas e catraca reapertada.

### `MCC18` era inerte, e contava como morto

O `refutador` provou por sha256 do corpus canonicalizado: o mutante escrevia
`found_by="aplicacao-de-instrumento"` nos tres achados que JA tinham esse valor, produzindo
arquivo byte-identico ao original. Passava, contava como MORTO, e nao exercitava direcao alguma -
`18/18` incluia um mutante que nao testava nada. Corrigido para escrever um valor DIFERENTE do
modo, que e a condicao que a regra tem de tolerar, com `assert` que reprova se o alvo voltar a
coincidir.

E a antivacuidade que faltava: a primeira versao IMPRIMIA o numero de modos com agente e nao o
assertava - se `agent` sumisse de todos os modos, o laco nao iteraria e o `PASS` sairia igual. O
portao era o sinal do proprio desligamento, ignorado. `MCC19` remove o vinculo de todos os modos e
exige reprovacao; `MCC20` exige que `null` seja DECLARADO, porque omissao nao e declaracao.

`G17` passou a declarar o modo novo `verificacao-de-fonte`, sem agente, que e o que de fato
ocorreu.

**O portao reprovou na primeira execucao, e nao pelo achado que o motivou.** `W15-7` e `W15-8`
traziam `found_by: "remedicao"` - o MODO no lugar do agente - contra os outros onze achados do
mesmo modo, e com `review_round: "refutador"` no proprio registro desde a onda 15. Corrigidos
lendo a evidencia que ja estava ali.

## Selecao retrospectiva, e por que `G16` entra em atraso

O `inclusion_criterion` do corpus exige que TODO defeito de uma rodada nomeada que altere
documentacao normativa seja registrado. `G16` - a correcao externa que originou esta familia -
ficou fora, porque o portao de completude so exige o caminho ADR -> corpus e a onda 19 nao usou
marcador estruturado.

O saldo desta onda sem ele seria **+1 para modo interno, +0 para `auditoria-externa`**, numa
familia que a auditoria externa originou. Isso e selecao condicionada ao desfecho, e e o mesmo
vies que a secao 9 do CLAUDE.md descreve no SkillsBench. Com `G16` registrado o saldo e +1 para
cada.

## Limites, declarados

`G4`, `G5`, `G6b`, `G7` e agora `G18`, `G19`, `G20` e `G21` seguem abertos.

`G21` e o achado mais importante desta onda, e ele nao veio de nenhum dos ataques pedidos - veio
da pergunta de fecho, "quatro rodadas ainda e convergencia ou ja e patch sobre patch?". A resposta
do `refutador` foi que o padrao degenerativo nao esta no portao, e sim em ele existir:

```
achados: 66 | violacoes de `found_by == (agent or mode)`: 0
```

`found_by` e funcao TOTAL de `mode`. Carrega zero informacao, e cinco condicionais mais seis
mutantes foram construidos nesta onda para conferir se a copia bate. E a inversao da onda 18
rodando ao contrario: `render.py` existe porque "contagem estruturada -> humano escreve o numero
-> regex confere a copia" era o formato errado, e aqui `mode` e estruturado, `found_by` e escrito
a mao, e um portao confere a copia.

O fecho e DERIVAR `found_by`, o que apaga a maior parte do aparato que quatro rodadas
construiram. Nao feito aqui, e a razao e a mesma que o ADR 0037 deu para adiar a taxonomia: e
mudanca de schema sobre 66 registros, e faze-la dentro do patch que criou o aparato seria a quinta
rodada da mesma onda. O que MUDA em relacao ao ADR 0037 e que o achado foi registrado no turno em
que apareceu - omitir o achado-pai da onda 19 custou uma rodada inteira a esta onda.

`G20` merece a nota porque nasceu de uma pergunta que eu fiz ao `refutador` e que ele respondeu
CONTRA a minha correcao. Registrar as tres balas da secao `Tambem ajustado` do ADR 0038 corrigiu a
selecao DAQUELA secao e nao a classe: o ADR 0036 tem secao irma, `Tambem corrigido`, com dois
defeitos que alteraram codigo e rotulo e que nao estao no corpus. Varre-la a mao seria fechar mais
uma realizacao. A classe e o portao de completude nao alcancar bala sem marcador estruturado, e
ela fica ABERTA. A nota de `G16`/`G16b`/`G16c` foi estreitada: afirma completude daquela secao, e
nao do corpus. `E_A` segue declarada e nao implementada.

O portao de procedencia confere que `found_by` bate com o `agent` que o modo declara. Ele nao
observa invocacao de agente - se ambos os campos forem preenchidos errado de forma COERENTE, ele
passa. E a mesma classe de limite do `state`: fecha a incoerencia, nao a autodeclaracao. A
evidencia de ATIVACAO continua sendo `E_A`, candidata e nao implementada, e este portao nao a
substitui.

O que ele deixou de ter e o limite LEXICAL, que a primeira versao tinha e nao declarava - e
declara-lo nao teria bastado, porque o modo de falha ja estava armado dentro do proprio diff.

`tests/unit/propriedades.sh` e FLAKY nesta maquina: o `refutador` mediu `PASS=30 FAIL=1` e, sem
alteracao de arvore, `PASS=31 FAIL=0` na reexecucao, com o par `supply-chain.sh (workflows reais)`
saindo inerte no regime cheio. A suite roda em `verify-pr.yml`. Nao e causado por esta onda - o
diff nao toca workflow, supply-chain nem propriedades - e nao esta corrigido aqui. Fica
REGISTRADO, nao normalizado.
