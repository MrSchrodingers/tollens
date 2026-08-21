# ADR 0037 - O frame e derivado, e a ausencia e delimitada

Data: 2026-08-20
Estado: aceito
Sucede: ADR 0036 (instalar nao e ativar)

## Contexto

A onda 17 corrigiu tres defeitos de afirmacao e construiu dois portoes para eles. A auditoria
seguinte leu o resultado e mostrou que **os dois portoes eram lint lexical com excecao
autodeclarada** - a forma que este repositorio vem eliminando desde o `D_MAX`, aparecendo agora
dentro das proprias correcoes contra ela.

Tres achados, os tres reproduzidos antes de aceitos.

## **G11** - o frame do corpus nao era derivado do corpus

O cabecalho declarava, a mao:

```
purpose          "... ondas 11 a 15 ..."
source_of_truth  "... docs/adr/0031..0035"
```

enquanto os dados, no mesmo arquivo, ja tinham:

```
ondas observadas   [11, 12, 13, 14, 15, 17]
ADRs referidos     0035, 0036
N observado        52
```

E a `reading` seguia dizendo "com o universo completo" depois de o proprio portao ter sido
rebatizado para declarar completude apenas RELATIVA ao frame dos IDs estruturados.

    ScopeDeclared(C)  DIFERENTE DE  ScopeObserved(C)

Corrigir `15 -> 17` e `0035 -> 0036` seria a proxima reincidencia. O frame passou a ser
DERIVADO: `derived` traz `n_findings`, `wave_min`, `wave_max`, `counts_by_mode`, `sources` e
`open_findings`, todos computados dos findings por `evidence/corpus/render.py`, e o portao
reprova se o bloco divergir. `MCC8` mata a edicao a mao.

Tambem saiu a expressao "achados de uma sessao": sessao e unidade experimental que este corpus
nao demonstra. Passou a ser "desta trajetoria de auditoria, neste repositorio".

## **G12** - o portao de negativa universal era lint, e a excecao era autodeclarada

O ADR 0036 dizia "portao que recusa negativa universal sobre literatura". A auditoria mediu
quatro reformulacoes triviais da mesma proposicao passando com `rc=0`, mais o token de escape
absolvendo qualquer linha.

As frases NAO sao reproduzidas aqui, e a razao e o proprio portao: elas sao a forma que ele
recusa, e cita-las neste ADR seria escrever a forma proibida numa linha nova. Isso poderia ser
resolvido com mais uma excecao - e mais uma excecao autodeclarada e exatamente o defeito que
este achado descreve. Elas vivem onde sao EXECUTAVEIS: `tests/mutation/corpus-completude.sh`,
mutantes `MCC10` e `MCC11`, que as aplicam a um ADR real e exigem reprovacao.

Isso e uma consequencia deliberada do desenho, e vale registrar porque incomoda: um portao que
recusa uma forma de frase torna essa forma inutilizavel tambem para quem a documenta. O preco e
que a evidencia precisa migrar da prosa para o teste - o que, neste repositorio, e a direcao
correta de qualquer forma.

Duas coisas diferentes, e a segunda e a grave:

**G12a - amplitude da claim.** O mecanismo e um LINT DE REALIZACOES LEXICAIS, nao um detector
semantico. Quatro reformulacoes triviais passavam. A frase do ADR prometia a classe e entregava
uma lista.

**G12b - a excecao dentro do objeto governado.** `[citacao-corrigida]` na propria linha absolvia
qualquer coisa, e quem escreve a claim escreve o token. E `D_MAX` outra vez, agora dentro da
correcao contra `D_MAX`.

A raiz nao e o regex. E que

```
PARA TODO p em Literatura, nao P(p)
```

nao e demonstravel por busca finita em literatura aberta - nao ha observacao que a sustente,
logo a secao 2 do CLAUDE.md ja a proibia e faltava a forma que a substitui. Ela existe agora:

```
NaoEncontrado(consultas, fontes, data)
```

`evidence/literature/searches/*.yaml` registra `claim_id`, `searched_at`, `sources`, `queries` e
`result.matching_studies`, com os limites do frame declarados no proprio arquivo. Um ADR so pode
afirmar ausencia referenciando `[busca:<id>]` que RESOLVA. A lista lexical foi ampliada, e a
claim sobre ela ENCOLHEU para o que ela e.

**A valvula de citacao deixou de ser autodeclarada.** Uma linha com a forma so e absolvida se
EXISTIR IDENTICA NA ARVORE BASE - fato que o PR nao pode forjar, o mesmo principio da onda 14.
Citar texto antigo para corrigi-lo continua possivel; inventar a propria absolvicao, nao.

Medido depois do fix, com as mesmas entradas que a auditoria usou: as quatro reformulacoes e o
token de escape passam a sair `rc=1`; `[busca:BL-9999]`, referencia morta, sai `rc=1`; e so
`[busca:BL-0001]`, que resolve para um registro real, sai `rc=0`. `MCC10` e `MCC11` fixam os
dois lados.

## **G13** - a excecao do portao de numeral era heuristica, e absorvia claim falsa

O lint de numeral absolvia se a janela de noventa caracteres anterior contivesse "antes",
"anterior", "primeira versao" ou "ja esteve". Medido:

```
"Antes de discutir severidade: sao 40 achados no corpus atual."   -> rc=0
```

Numero corrente FALSO, absolvido por uma palavra na vizinhanca. Excecao por janela lexical e
adivinhacao de intencao.

A excecao foi REMOVIDA, e a preocupacao legitima por tras dela - o corpus precisa poder
registrar o proprio erro - passou a ser atendida por `historical_states`, estruturado, que o
renderer imprime. `MCC9` mata o caso medido; `MCC6` foi reescrito e agora prova a direcao
correta: registrar historico ESTRUTURADO continua permitido.

O formato mudou de direcao, e essa e a correcao real:

```
antes    contagem estruturada -> humano escreve o numero -> regex tenta descobrir se copiou certo
agora    contagem estruturada -> renderer -> prosa
```

**LIMITE, dito com precisao porque a versao anterior errou exatamente aqui.** O lint que
sobrou recusa DUAS formas - `<N> achados` e `N=<N>` - e nada mais. Numero por extenso,
aritmetica em texto e referencia narrativa a uma onda passada ficam FORA. A garantia contra
essas nao vem do lint: vem de o frame ser derivado, onde nao ha o que copiar errado. Dizer que o
lint "garante coerencia entre prosa e dado" seria a amplitude que este ADR corrige.

## G6 dividido, porque `corrigido` cobria duas coisas

O corpus registrava `G6` com `status: corrigido`. A auditoria apontou que isso misturava a
falsidade documental com o fenomeno que a revelou. Passou a ser:

```
G6a  a claim "a entrega ja e conferida" era falsa       CORRIGIDA
G6b  evidencia de ATIVACAO nao existe                   ABERTA, sem instrumento
```

Um unico `corrigido` sobre os dois teria publicado a segunda como resolvida.

## O que a auditoria propos e este ADR nao fez

A proposta de unificar `G4`, `G5`, `G7` e `E_A` numa representacao comum de propriedades
observaveis da capability - `(P_pre, R_post, B_stop, I_context, O_telemetry, M_state)`, com
`kind` e obrigacoes derivados dela em vez de declarados - e a saida certa e esta registrada como
tal. Nao foi feita aqui: e desenho de taxonomia, nao correcao, e tem de vir como onda propria com
oraculo para cada propriedade. Fazer parte dela agora produziria o quarto patch da mesma familia.

## Limites, declarados

`G4`, `G5`, `G6b` e `G7` seguem abertos. `E_A` segue declarada e nao implementada.

O portao de ausencia na literatura garante FORMA, nao verdade: exige que exista um registro de
busca, e nao verifica que a busca tenha sido executada nem que suas fontes sejam adequadas. O
registro `BL-0001` declara o proprio frame como estreito - cobriu o ledger interno, nao arXiv
nem Crossref - e essa e a unica coisa que ele pode sustentar.

As referencias externas oferecidas pela auditoria seguem FORA do ledger. Nenhuma foi conferida em
fonte primaria nesta sessao, e o precedente do ADR 0011 - quatro de cinco citacoes falsas sob
vigilancia da regra que as proibia - torna a incorporacao por confianca o mesmo defeito que
`G8` corrigiu. A auditoria informou ter conferido a existencia de quatro delas; existencia nao e
o que o schema deste repositorio pede, que inclui metodo, scaffold, oraculo, repeticao e
incerteza. Incorporar exige leitura de texto completo.
