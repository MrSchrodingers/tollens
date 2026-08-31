# ADR 0041 - O kernel guardava a classe errada de erro

Data: 2026-08-26
Estado: aceito
Sucede: ADR 0040 (o artefato nao pode depender de onde foi gerado)

## Contexto: um defeito banal atravessou 18.274 caracteres de instrucao

Em 2026-08-26, 15h10, uma sessao operando sob o kernel completo, com escopo managed imposto,
modo estrito de hooks e os dez agentes disponiveis, afirmou ao operador que um campo era "novo no
model, migration, serializer e UI". O campo existia. Estava no diff NAO COMMITADO da propria
sessao, em branch chamada `feat/honorarios-congenere-por-faixa`, com cinco linhas de comentario
que a propria sessao havia escrito explicando a distincao entre o dado e o parametro da regra.

Contestada pelo operador, a sessao MEDIU, e a medicao deu resultado errado: um `grep -A20` a
partir da declaracao da classe cortava antes da linha 190, onde o campo esta. O resultado errado
foi apresentado como confirmacao, em tabela, com ancoras de arquivo e linha.

A cronologia foi medida e nao inferida:

```
managed CLAUDE.md instalado   2026-08-25 15:14
allowManagedHooksOnly=true    2026-08-25 17:27
a sessao                      2026-08-26 15:10
```

O aparato estava em vigor. Nao havia atenuante de ambiente.

## O diagnostico: assimetria de classe, nao lacuna de regra

A leitura facil e "faltou uma regra". Ela e falsa e leva a resposta errada, que seria acrescentar
a quinquagesima primeira regra a um documento de cinquenta.

O kernel completo protege, com rigor consideravel, contra UMA classe de erro:

```
FALSO POSITIVO DE CONCLUSAO      dizer que esta feito sem estar
```

Seccao 1 exige teste que falhava e agora passa. Seccao 2 exige fonte primaria. O hook
`verify-gate` barra o encerramento. Os 200 mutantes existem para provar que os portoes
discriminam. A arquitetura possui NUMEROSOS mecanismos explicitos contra false success - a
formulacao anterior deste ADR dizia "cerca de 50 regras", numeral retorico sem criterio de
contagem, exatamente o que este repositorio aprendeu a nao usar.

E nenhum mecanismo explicito equivalente foi identificado para a classe simetrica:

```
INTERVENCAO DESNECESSARIA        agir sobre o que ja esta satisfeito
```

A formulacao "falso positivo de necessidade" era estreita demais e semanticamente nebulosa. A
categoria correta e ACTION CALIBRATION, e ela e uma matriz, nao um par:

| Estado real | Agente decide agir | Agente decide nao agir |
|---|---|---|
| mudanca necessaria | intervencao correta | OMISSAO |
| mudanca desnecessaria | INTERVENCAO DESNECESSARIA | no-op correto |

Com duas taxas que se medem separadamente:

```
NeedPrecision = TP / (TP + intervencao desnecessaria)
NeedRecall    = TP / (TP + omissao)
```

O Tollens foi otimizado para RECALL - "nao deixe passar coisa errada" - e nao tem instrumento
para precision. Isso explica a forma da reclamacao operacional melhor que qualquer regra isolada:
o operador nao se queixa de que o sistema deixa erro passar; queixa-se de que ele faz o que nao
precisava, no lugar errado, demorando.

E ha uma consequencia de desenho que decorre disso e que este ADR nao havia extraido: **NO-OP
precisa ser desfecho de primeira classe.** O fluxo implicito era `pedido -> planejar -> agir ->
verificar`. Ele comeca em "como fazer", nunca em "ha algo a fazer". A maquina de estados correta
verifica NECESSIDADE antes de planejar, e `ja satisfeito` e um terminal legitimo - nao um
fracasso, nao um caso degenerado.

A assimetria tem explicacao historica e ela esta no proprio corpus: dos 85 achados registrados
ate a onda 22, uma classificacao exploratoria por palavra-chave estimou 73 como sendo sobre o
PROPRIO aparato. O numero e indicativo e nao estimativa - o classificador foi escrito pelo agente
que o executou, o que e exatamente o vies que este repositorio persegue em outros contextos -,
mas a direcao e forte: o kernel foi escrito por um processo que passou a maior parte do tempo
auditando a si mesmo, e auditoria de si produz regras contra afirmar conclusao falsa, nao contra
afirmar necessidade falsa.

## O segundo mecanismo: o tamanho do kernel era ele proprio um modo de falha

O kernel declarava, na primeira secao, que "texto aqui custa em toda sessao", e carregava 18.274
caracteres. Havia ainda uma segunda copia identica na projecao de usuario. Documentos de
instrucao sao CONCATENADOS pelo runtime, nao sobrescritos - a sonda de ativacao desta onda
observou `Managed` e `User` entrando no contexto na MESMA sessao. O custo real era 36.548 bytes,
cerca de 9.100 tokens, em toda sessao.

O kernel citava `arXiv:2402.14848` (FLenQA) para sustentar que comprimento sozinho degrada. Duas
observacoes sobre essa citacao, e as duas importam:

1. Ela nao esta no ledger de literatura deste repositorio. Nove trabalhos estao registrados com
   veredito de verificacao por entrada; este nao. A citacao vive na prosa do kernel e nunca
   passou pelo instrumento que o proprio repositorio construiu para citacoes.
2. Se o efeito que ela descreve for real, ele se aplicava ao proprio kernel. Um documento que
   argumenta contra comprimento e cresce ate 4.568 tokens esta em contradicao operacional com a
   propria tese.

Nao afirmo relacao causal entre o tamanho e o defeito de 2026-08-26. Afirmar isso exigiria
experimento pareado que nao foi feito. O que se sustenta e mais fraco e ainda assim relevante: o
mecanismo que o kernel invoca para justificar concisao militava contra o kernel.

## O terceiro mecanismo: a documentacao era excelente sobre o assunto errado

O repositorio tem, na onda 22, 40 ADRs, 26 suites, 16 arneses de mutacao, nove entradas de
literatura com veredito, um corpus de 85 achados com frame derivado, e portoes que se validam por
mutacao. Isso e infraestrutura de pesquisa de qualidade nao trivial.

Ela documenta o aparato. Nao documenta os modos de falha do TRABALHO. Nao ha, em nenhum dos 40
ADRs, uma taxonomia dos erros que uma sessao comete ao atender um pedido real: afirmar
necessidade falsa, cortar a janela de uma medicao, contradizer o proprio diff, expandir escopo.

A consequencia e direta: um sistema pode ser exaustivamente verificado quanto a coerencia interna
e permanecer sem cobertura sobre o desfecho que importa. Este repositorio ja registrava a forma
geral disso - `consistencia interna NAO IMPLICA completude`, ADR 0036 - e a aplicou ao corpus.
Nao a tinha aplicado a si mesmo.

## A correcao: remover, nao acrescentar

Tres mudancas, e nenhuma delas e uma regra nova sobre o mesmo eixo.

**O kernel encolheu 84%**, de 18.274 para 2.924 bytes. O que saiu foi metodo de pesquisa, lentes
de analise, topologia de reviewers, estrategia de leitura de midia, e o racional cientifico -
tudo isso continua VERSIONADO em `execution/config/CLAUDE.md` e passou a ser documento de
laboratorio, nao instrucao de runtime.

**O kernel passou a viver em UM escopo.** A copia da projecao de usuario saiu do manifesto, que
foi de 49 para 48 componentes. Bytes de instrucao carregados: 36.548 -> 2.924, reducao de 92%.

A unidade e BYTES CARREGADOS QUANDO AMBOS CARREGAM, nao custo por sessao. A telemetria desta onda
mede `Managed` em 5 de 8 sessoes observadas, e sessoes de subagente nao carregam instrucao - logo
afirmar custo por sessao exigiria agregacao por `session_id`, que nao foi feita. E
`bytes != tokens != custo efetivo de atencao`: as tres sao grandezas diferentes e so a primeira
foi medida aqui.

**Duas regras novas, e as duas sao sobre a classe que nao existia:**

```
1. Antes de afirmar que algo precisa ser feito, verifique se ja esta feito
   - inclusive no seu proprio trabalho nao commitado
2. Medicao errada e pior que nenhuma medicao
   - confira que o instrumento acha o caso positivo conhecido
```

A segunda tem efeito observavel e ele foi medido. Com o kernel enxuto em vigor, a resposta a uma
premissa falsa passou a incluir controle positivo da propria sonda:

```
$ ls -la /nao/existe/x.py
ls: cannot access '/nao/existe/x.py': No such file or directory   exit=2

Controle positivo da sonda:
$ ls -la /etc/claude-code/CLAUDE.md >/dev/null; echo $?
0
O `ls` retorna 0 para arquivo que existe, 2 para ausente - a sonda discrimina.
```

O kernel de 18.274 caracteres nao produziu esse comportamento nas observacoes desta sessao. Isso
e OBSERVACAO MOTIVADORA, nao evidencia de superioridade: n=1 de cada lado, sem repeticao, sem
controle de infraestrutura e sem cegamento.

**Duas regras sairam.** Elas sao MECANISMOS CANDIDATOS diretamente compativeis com os sintomas
observados, e foram removidas para teste causal - nao porque a causalidade esteja demonstrada.
Plausibilidade mecanistica nao e causalidade, e afirmar o contrario neste documento seria cometer
o salto que ele critica.

`"bug preexistente sempre se resolve"` virou triagem - corrigir no mesmo trabalho apenas se
bloquear o requisito atual, compartilhar causa raiz, ou envolver seguranca, perda de dado ou
irreversibilidade; caso contrario registrar e seguir. A formulacao anterior incentivava expansao
de escopo, que e a reclamacao "peco uma coisa e ele sai fazendo outra".

O pipeline minimo obrigatorio de tres agentes virou tabela por risco. A evidencia do proprio
ledger nao sustenta a obrigatoriedade: `arXiv:2310.01798`, peer-reviewed, mede que auto-correcao
INTRINSECA - "sem a muleta de feedback externo", verbatim do registro - nao melhora e as vezes
piora raciocinio. Isso sustenta que contexto separado vale mais que segunda voz na mesma
resposta. NAO sustenta que revisor sempre supera ausencia de revisor, que e proposicao diferente
e nao medida aqui.

## O verificador deixou de descrever um escopo e concluir sobre o sistema

`install/verify.sh` publicava `ESTADO: conforme (governed=user)`. Era afirmacao verdadeira sobre
a projecao de usuario apresentada como descricao do sistema. Trocar a string por
`governed=managed` teria sido corrigir o rotulo sem corrigir o instrumento - a classe que a onda
20 corrigiu em outro campo.

As tres observacoes passaram a ser independentes:

```
PROJECAO USUARIO   48/48 ok
PROJECAO MANAGED   4 IMPOSTOS (root)
ATIVACAO           18 evento(s) Managed
  LIMITE           o log e `ti` - o ator governado pode forja-lo (G39). Indicio, nao prova.

GOVERNANCA GLOBAL  governed=managed
```

A linha de LIMITE existe porque `G39` e verdadeiro: o sumidouro da evidencia de ativacao e
gravavel pelo ator governado. Um verificador que publicasse ativacao sem essa ressalva estaria
cometendo, no proprio relatorio, a forma que este ADR descreve.

## Uma condicao de desenho que o encolhimento impoe

A filosofia usual ao encolher um kernel e "o que saiu volta por progressive disclosure" - isto e,
por skill carregada sob demanda. **Aqui essa saida nao esta disponivel**, e assumi-la seria erro:
a telemetria desta onda mede ZERO invocacoes automaticas das oito skills deste repositorio, com o
canal de skill comprovadamente funcional (uma skill NAO-Tollens foi observada disparando).

Portanto o kernel enxuto tem de bastar para trabalho normal SEM nenhuma skill deste repositorio.
Skills sao incrementais, nao supletivas. Trocar "contexto demais" por "contexto que nunca aparece"
seria substituir um defeito por outro pior, porque o segundo e silencioso.

## O que este ADR NAO afirma

Nao afirma que o kernel enxuto e melhor. Um caso de teste que ele resolve e o completo nao
resolveu e UMA observacao, com n=1 de cada lado, sem repeticao e sem controle de infraestrutura.

A afirmacao que se sustenta e mais estreita e verificavel: o kernel completo estava em vigor, com
carimbo de hora dos dois lados, e nao impediu o defeito.

A comparacao que decidiria - Vanilla contra Lite contra Full, sobre tarefas reais fora deste
repositorio, com repeticao, ambiente congelado e oraculo independente - continua NAO EXECUTADA, e
e o trabalho de maior valor pendente. `evidence/evaluation-protocol.json` ja contem quase todo o
desenho necessario; ele foi escrito para comparar `with_skill` contra `without_skill` e precisa
ser promovido a protocolo de avaliacao de harness.

## Limites, declarados

A classificacao "73 de 85 achados sobre o proprio aparato" e exploratoria, por palavra-chave
definida pelo agente que a executou. Ela indica direcao, nao magnitude. Uma classificacao com
criterio pre-registrado e classificador independente daria outro numero.

A citacao de FLenQA permanece fora do ledger. Ela sai do kernel enxuto por isso, e nao por ter
sido refutada.

`G39` e `G40` seguem abertos: o instrumento que mede ativacao nao e imposto, e apresentou falso
negativo parcial cujo mecanismo nao foi determinado. Enquanto isso, ativacao e indicio.
