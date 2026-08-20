# ADR 0036 - Instalar nao e ativar, e a prosa nao e o dado

Data: 2026-08-20
Estado: aceito
Sucede: ADR 0035 (a divida era de uma classe so)

## Contexto

A onda 16 fechou a completude do corpus contra os identificadores dos ADRs. A auditoria seguinte
leu o `main` resultante e trouxe cinco achados. Nenhum e defeito de codigo. Todos sao defeitos de
AFIRMACAO, e tres deles sao a mesma familia num nivel novo.

## **G6** - instalar nao e ativar, e essa era a base de uma dispensa

`orchestration/evidence-policy.json` dispensava `guidance_document` de `E_M` com esta razao:

> um documento nao tem mecanismo proprio - ele e texto entregue ao modelo, e que a entrega ocorre
> ja e conferido por `install/verify.sh` contra o digest do manifesto.

Falso como escrito. `install/verify.sh` demonstra:

```
bytes_instalados == bytes_esperados
```

e nao:

```
o runtime CARREGOU o documento no contexto do modelo
```

Sao proposicoes diferentes, e a segunda e a que a dispensa precisava. A sonda de eventos de
runtime deste repositorio esta NAO VERIFICADA desde a onda 13 - o proprio registro observou
`SessionStart`, `UserPromptSubmit` e `Stop`, nao observou `InstructionsLoaded`, e nao validou o
proprio caminho de registro. Portanto a afirmacao de entrega nao tinha lastro em lugar nenhum.

E a forma canonica deste repositorio, num lugar onde ela ainda nao tinha sido nomeada:

```
representacao do mecanismo  NAO E  o fenomeno
```

A dispensa foi reescrita para dizer o que de fato se sabe, e a ATIVACAO virou divida declarada em
`dimensions_candidatas.E_A` - uma dimensao que pergunta se a capability e ACIONADA quando deveria
e nao acionada quando nao deveria. Ela NAO esta implementada, e o campo diz isso: exige oraculo de
runtime que este repositorio nao tem, e esta bloqueada pela sonda NAO VERIFICADA.

A distincao importa alem do documento. Um hook pode existir e nao disparar no evento; uma skill
pode ser boa quando executada e piorar o sistema por roteamento ruim. O vetor atual colapsa os
tres casos em `E_M`.

## **G7** - `hook_gate` mistura prevenir com rejeitar depois

A policy tem uma classe unica para portao, e os portoes deste repositorio operam em eventos
diferentes. Medido:

```
$ printf 'def f(:\n' > /tmp/x/quebrado.py
arquivo existe ANTES do hook?    sim
poka-yoke-lint (PostToolUse)  -> exit=2
arquivo existe DEPOIS?           SIM - o efeito ja ocorreu
```

`artifact-discipline.sh` roda em `PreToolUse` e IMPEDE a escrita. `poka-yoke-lint.sh` roda em
`PostToolUse` e bloqueia depois de o arquivo existir. `verify-gate.sh` roda em `Stop` e barra o
encerramento. Os tres saem 2, e as tres garantias sao diferentes:

```
prevencao        o efeito nao ocorre
rejeicao posterior  o efeito ocorreu e o modelo e obrigado a tratar
terminal         o encerramento e barrado, o efeito ja esta na arvore
```

Tratar as tres como `hook_gate` com a mesma obrigacao `(E_M, E_S)` e amplitude de claim: `E_S`
de um portao preventivo pergunta "erra fechado?", e de um portao posterior pergunta "o dano ja
feito e reversivel, e alguem o ve?". NAO CORRIGIDO nesta onda, por decisao declarada: separar a
classe muda a taxonomia da policy e exige definir a obrigacao de cada uma, o que e desenho
proprio. Fica registrado com a medicao acima.

## **G10** - a prosa derivada nao conferia com o dado

A onda 16 fechou "faltam linhas no corpus". Sobrou a forma menor da mesma classe: o corpus foi de
26 para 47 achados e a PROSA dentro dele continuou dizendo "40 achados", "N=40", "tres dos 40
achados". O portao reconferia `counts_by_mode` e nao olhava numeral em texto.

```
dados estruturados corretos  NAO IMPLICA  prosa derivada correta
```

Terceira aparicao de "numero declarado que ninguem confere" nesta serie - depois do `D_MAX` e dos
numeros do ADR 0035. Fechado com portao: todo numeral escrito como `<N> achados` ou `N=<N>` nos
campos de prosa do corpus tem de bater com o total real, com excecao explicita para numeral
marcado como estado ANTERIOR - senao a regra proibiria o corpus de registrar o proprio erro.
`MCC5` mata a violacao, `MCC6` e o controle de direcao que preserva o numeral historico.

A mesma passagem trazia aritmetica errada: dizia "os DEZESSEIS ... cinco criticos e seis avisos
... e os tres", que soma catorze. Sao oito avisos. Corrigido no corpus e no comentario do portao.

## **G8** - negativa universal sobre literatura, contradita pelo proprio ledger

O ADR 0033 afirmava:

> Nenhum trabalho conhecido mede `P(agente declara sucesso | verificador reprova)`  [citacao-corrigida]

E `evidence/literature/arxiv-2606.09863.yaml`, no MESMO repositorio, registra que o estudo "mede
diretamente o fenomeno que motiva a regra dura deste repositorio", com as tres metricas: 45-48%
em tau2 single-control, 3% em dual-control telecom, 75,8% em AppWorld. O ADR 0010 cita o mesmo
paper. Um ADR e um ledger afirmando o oposto, e nada os confrontava.

O ADR 0011 ja documentava que 4 de 5 citacoes deste repositorio eram falsas, sob vigilancia
nominal da regra que as proibia. Esta e a quinta, de forma diferente: nao uma citacao falsa, mas
uma negativa universal - que e inverificavel por construcao, porque nao se cita evidencia da
ausencia de toda a literatura.

**AGRAVANTE DE METODO, e ele fica registrado porque e o pior desta onda.** Esta contradicao foi
apontada por auditoria externa numa rodada ANTERIOR e REFUTADA por engano. A refutacao se apoiou
numa busca truncada por `head -8`, cujos acertos no ADR ficaram abaixo do corte, e foi publicada
com a frase "nao corrijo o que nao foi afirmado". Concluir ausencia a partir de observacao
truncada e a forma mais barata do defeito que este repositorio persegue, e ela foi cometida ao
NEGAR o defeito - o que e estritamente pior que comete-la ao afirmar algo.

Fechado nos dois lados: errata no ADR 0033, e portao que recusa negativa universal sobre
literatura em qualquer ADR fora de errata (`MCC7`).

A lacuna REAL, que sobrevive a correcao: nao ha demonstracao causal, pareada contra baseline
equivalente, de que este harness REDUZA aquele desfecho. O desfecho ja foi medido; o efeito deste
aparato sobre ele, nao.

## **G9** - a proveniencia do modo `auditoria-externa` era afirmacao sem lastro

O corpus descrevia o modo como "revisor humano, fora da sessao". Isso nao e observavel deste
lado: a revisao chega mediada pelo operador e nao ha evidencia de quem ou o que a produziu. A
distincao muda a leitura do dado - um dos mecanismos causais plausiveis para a complementaridade
observada e diversidade de modelo ou de harness, e atribui-la a expertise humana escolheria um
mecanismo que este corpus nao mediu. O campo passou a dizer o que se sabe, e um limite novo
registra que qualquer leitura causal aqui esta escolhendo mecanismo nao medido.

## Tambem corrigido

`tests/unit/methodology.py` chamava de `promovidas` o conjunto derivado do registry, e imprimia
"ha skills promovidas a conferir (medido: 8)". As oito estao em `state: candidate`. O mecanismo
estava certo desde a onda 13; o VOCABULARIO publicado pelo teste continuava o da arquitetura que
a onda 13 removeu.

O rotulo do portao de completude dizia `PASS corpus COMPLETO`. Passou a dizer que a completude e
RELATIVA ao frame dos IDs estruturados nos ADRs - defeito descrito em ADR sem identificador fica
fora deste frame, e `MCC4` fixa que o corpus pode conter mais do que os ADRs citam.

## Limites, declarados

`G4` (classificacao de capability nova), `G5` (`E_S` para guidance) e `G7` (semantica temporal de
portao) seguem ABERTOS, com reproducao registrada. `E_A` esta declarada como dimensao candidata e
nao implementada.

A auditoria apontou tres itens que esta onda NAO tratou: as isencoes de cobertura cuja
justificativa historica ja expirou e que deveriam ter `expires_at`; a duplicacao estrutural entre
`scripts/status.sh --check` e os passos do workflow, que executa as mesmas suites duas vezes; e a
atualizacao do ledger de literatura com trabalhos recentes. Os tres estao registrados aqui e nao
foram feitos.

Sobre o ledger: a auditoria ofereceu cinco referencias novas. NENHUMA foi adicionada, porque
nenhuma foi conferida em fonte primaria nesta sessao. Dado o precedente do ADR 0011 - quatro de
cinco citacoes falsas sob vigilancia da regra que as proibia -, adicionar referencia por
confianca seria repetir exatamente o defeito que este ADR corrige em G8.
