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
desde o `D_MAX`, aparecendo agora dentro da correcao contra ela, pela oitava vez.

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

A regra agora: modo que NOMEIA um agente obriga `found_by` igual a esse agente; modo que declara
"Sem agente" nao obriga nada. `MCC17` mata a atribuicao falsa, `MCC18` e o controle na direcao
inversa - forcar um agente onde nao houve seria inventar procedencia, o defeito simetrico.

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

`G4`, `G5`, `G6b`, `G7` e agora `G18` seguem abertos. `E_A` segue declarada e nao implementada.

O portao de procedencia confere que `found_by` bate com o agente que o modo NOMEIA. Ele nao
observa invocacao de agente - se ambos os campos forem preenchidos errado de forma coerente, ele
passa. E a mesma classe de limite do `state`: fecha a incoerencia, nao a autodeclaracao. A
evidencia de ATIVACAO continua sendo `E_A`, candidata e nao implementada, e este portao nao a
substitui.
