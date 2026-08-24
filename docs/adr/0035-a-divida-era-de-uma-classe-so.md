# ADR 0035 - A divida era de uma classe so

Data: 2026-08-19
Estado: aceito
Sucede: ADR 0034 (o teto que o proprio PR podia levantar)

## Contexto

O ADR 0034 tornou a divida de avaliacao monotonica contra o SHA-base e removeu o teto
autodeclarado. A auditoria seguinte aceitou o mecanismo e apontou o limite imediatamente acima
dele, que e de MEDIDA e nao de mecanismo:

> `D_E = 8` e correto para skills, mas `18` continua sendo so um piso. Skill e agente sao
> intervencoes diferentes. Melhor representar `D_E = (D_skill, D_agent, D_guidance, D_safety)`.
> E eu nao colocaria todos os hooks na mesma divida: `verify-gate.sh` deve prova de MECANISMO e
> SEGURANCA; `lentes.sh` deve prova de UTILIDADE.

A proposta e uma decomposicao por dimensao, `E(c) = (E_M, E_U, E_C, E_S)`, com obrigacao de
prova por tipo de capability. Este ADR a adota, e registra o que ela achou ao ser aplicada.

## O que a primeira aplicacao mediu

A dimensao E_M pergunta "faz o que diz fazer?". Aplicada ao inventario de hooks, respondeu antes
de qualquer codigo novo:

```
nenhuma mencao em tests/ .......... artifact-discipline, risk-trigger, self-mod-audit,
                                    poka-yoke-lint
mencionados SO como membro de um
conjunto de classificacao estatica
em tests/unit/run.sh:131-136 ...... lentes, graphify-scout-mode, subagent-probe, ds4-notify
executados por alguma suite ....... verify-gate, subagent-contract, session-integrity,
                                    read-budget, fable-guard, output-budget
```

**Oito de catorze hooks instalados na configuracao global do usuario, sem execucao em teste
algum.** Dois deles bloqueiam escrita. Dois sao citados em CLAUDE.md como garantia ativa. E o
segundo grupo e o caso mais nitido: `run.sh` CLASSIFICA quatro hooks - sabe o nome, sabe a
categoria - e nunca roda nenhum. E a forma do ADR 0030 outra vez, o verificador observando a
REPRESENTACAO da garantia em vez do fenomeno.

**A medicao precisou de tres tentativas, e as duas primeiras estavam erradas.** Isso faz parte
do achado, nao e nota de rodape:

1. `grep -c "exit 2"` no fonte. Dois falsos positivos em catorze: `self-mod-audit.sh` e
   `risk-trigger.sh` sao fail-open, e as ocorrencias estavam em COMENTARIO.
2. `grep -rlE "bash[^|;&]*<hook>.sh" tests/`. Errou para o outro lado: as suites atribuem o
   caminho a uma variavel (`GATE="$PWD/evidence/hooks/verify-gate.sh"`) e so depois executam.
3. Ocorrencia do basename com inspecao caso a caso. E a que sustenta o numero.

## Decisao

**A divida vira vetor.** `orchestration/evidence-policy.json` declara as quatro dimensoes, o
mapeamento dos sete `promotion_requires` existentes sobre elas, e a obrigacao por `kind`:

```
skill, agent          E_M  E_U  E_C  E_S
hook_gate             E_M            E_S
hook_guidance         E_M  E_U  E_C
hook_instrument       E_M
```

A policy vive FORA do portao. Um portao que carrega o proprio criterio e a forma que o ADR 0034
acabou de remover.

`hook_gate` nao deve E_U porque "bloquear melhora o desfecho" e proposicao sobre a POLITICA que
o portao aplica, nao sobre o portao. Isso e um julgamento desta policy, declarado como tal, e
nao um resultado medido.

**E_M e pagavel por suite executada; E_U e E_C, nao.** "Faz o que diz" e proposicao sobre o
artefato, e uma suite que o INVOCA e evidencia direta dela. "Melhora o resultado" exige
comparacao entre condicoes, que nenhuma suite deste repositorio produz.

**Mencao nao e execucao.** A evidencia por suite so vale se o texto da suite contiver o CAMINHO
da fonte. Creditar E_M por citacao teria reproduzido, dentro do instrumento, o defeito que o
instrumento existe para medir.

**Descoberta nao e criacao.** Registrar 25 componentes que ja rodavam MEDE divida preexistente;
e o oposto de contrai-la. A distincao e decidida por um fato que o PR nao pode forjar - a fonte
ja existir na arvore-base. Criacao continua permitida com uma condicao unica: a capability nova
precisa NASCER COM A DIVIDA ZERADA. Sem essa valvula o portao congelaria o repositorio, porque
um componente novo tambem reprovaria na bijecao com o manifesto se ficasse fora do registry.

**A descoberta e limitada pela bijecao registry x manifesto.** Sem ela bastaria nao registrar
para a divida sumir do instrumento. Com ela, inventario instalado e inventario governado sao o
mesmo conjunto, verificado por fonte e por tipo.

**Declarar `paid` e uma afirmacao, e uma afirmacao falsa REPROVA.** Rebaixar silenciosamente a
"nao paga" bastaria enquanto a capability existisse nos dois lados da comparacao, e NAO basta no
commit que a descobre - ali ela esta fora do conjunto comum e a monotonicidade nao a alcanca.

## Divida medida, depois da decomposicao

```
D_E(head) = 89 obrigacoes em aberto sobre 33 capabilities
por dimensao: E_M 18   E_U 25   E_C 25   E_S 21
```

> **ERRATA, onda 20 (`G16`).** Ate 2026-08-24 este bloco publicava `sobre 34 capabilities`,
> copiado da saida do portao. O numero 89 esta certo e nao mudou; o DENOMINADOR estava errado.
> `_divida` percorre so as capabilities em `_EM_DIVIDA` - as 33 em `candidate` - enquanto a linha
> impressa dividia por `len(caps)`, que inclui o tombstone `defesa-de-tese`, em `deprecated`.
> Numerador de 33 sobre denominador de 34, na mesma frase. A correcao esta em
> `tests/unit/capability-conformance.py`, e a linha passou a nomear as duas grandezas em vez de
> confundi-las. **O defeito era de EXIBICAO, nao de assercao**: as duas checagens de CC4 comparam
> CONJUNTOS de pares `(capability, dimensao)` e nunca leram esse denominador, entao nenhum
> veredito publicado por este repositorio muda com a correcao.
>
> Vale registrar de onde veio: a mesma confusao - ler "34 capabilities" como "34 componentes
> ativos" - ja tinha sido apontada pela revisao externa NA PROSA do relatorio. Corrigir a prosa
> e ir conferir o numero na fonte foi o que exps a instancia dentro do instrumento. A correcao
> de uma afirmacao encontrou o defeito no que a media.

`E_M = 18` sao exatamente as 8 skills e os 10 agentes. Os catorze hooks passaram a ter mecanismo
pago. O numero total PIOROU - de 8 para 89 - porque a medicao melhorou; e a leitura correta do
salto, e ela vale a pena ser dita: um instrumento que so melhora quando o numero cai mede o
numero, nao o fenomeno.

Skill e agente nao tem E_M pago de proposito. `methodology.py` abre os artefatos de skill e
resolve as invocacoes publicadas; `capabilities.sh` confere o frontmatter dos agentes contra a
capacidade declarada. As duas coisas sao propriedades de FIACAO, nao de mecanismo. Contabiliza-las
como E_M repetiria, um nivel abaixo, o erro de amplitude que esta onda corrige.

## EvidenceValidity: o dossie tem data de validade

`Valid(c, t0)` nao implica `Valid(c, t1)`. Um dossie e registro de experimento PASSADO, e deixa
de valer quando muda aquilo sobre o que concluiu. Duas dependencias sao conferidas por digest
computado no portao - `artifact_digest` e `policy_digest` -, duas ficam DECLARADAS - `runtime` e
`model` -, porque um portao nao observa de dentro qual modelo executa a sessao. Exigir o campo
torna a dependencia visivel; nao a torna medida.

A regra NAO se aplica a evidencia por suite executada, e a razao e a assimetria entre as duas
formas: **dossie e registro, suite e producao.** A suite e reproduzida a cada execucao da CI; se
o componente mudar e ela continuar passando, a evidencia continua valida porque acabou de ser
produzida de novo. So o registro precisa de validade temporal.

## Amplitude da claim: `writes: false` nao e confinamento

O registry declarava `single_writer: true` e marcava oito agentes com `writes: false`. As duas
coisas sao lidas como ISOLAMENTO, e nenhuma e isso: os dez agentes recebem `Bash`, entao um
agente sem `Write`/`Edit` ainda pode `sed -i`, `rm`, `git apply`.

```
writes=false  NAO IMPLICA  ausencia de capacidade de escrita
```

Mesma classe do `--dry-run` da onda 13b, e mesma correcao: nao estreitar a prosa e sim tornar a
amplitude verificavel. O registry passa a declarar `write_confinement: "none"` e
`single_writer_is_scheduling_only: true`, e o portao exige que a declaracao case com o fato
medido no frontmatter dos agentes - declarar `sandbox` com agentes de shell REPROVA.

## Separacao de oraculo: tres artefatos, tres afirmacoes

```
orchestration/schedule/*.json   red -> writes ["**"], produces ["failing-test"]
README.md, README.pt-BR.md      RED["tdd: estado RED<br/>writes: tests/"]
execution/agents/tdd.md         "GREEN: implemento o minimo suficiente para passar"
```

Nenhum verificava o outro, e o README ja estava FALSO contra o schedule. Entre as duas saidas
possiveis - TDD classico com `tdd` fechando RED+GREEN, ou separacao de oraculo -, adota-se a
segunda, pela mesma razao que o `refutador` existe: quem escreve o teste que decide o veredito
nao deveria ser quem escreve o codigo que o teste julga. Nao ha medicao propria sustentando que
a separacao produza codigo melhor; a justificativa e de independencia do oraculo, declarada como
principio.

A regra entrou no VALIDADOR, nao apenas nos artefatos: `orchestration/schedule.py` recusa
configuracao em que o no de `failing-test` declare escrita irrestrita, e recusa que o mesmo ator
produza `failing-test` e `diff`. Com isso `red` passa a declarar `["tests/**"]` - o primeiro no
de codigo deste repositorio com escopo real, situacao que o proprio docstring do modulo previa
como hipotetica.

## Um mutante EQUIVALENTE, declarado em vez de forcado

`MHG15` remove a guarda de tamanho de `output-budget.sh` e a suite continua verde. Nao e
assercao fraca: uma SEGUNDA guarda independente (`[ "$NEWSZ" -ge "$SZ" ]`) descarta o corte que
nao encolhe, e o mutante nao muda comportamento observavel algum. O arnes declara `want=0` e
registra a redundancia; `MHG16` remove AS DUAS e mostra que a assercao e, de fato, sensivel.
Forcar uma morte aqui teria exigido enfraquecer o hook.

## O que a CI custa, medido

Do log real do run 32192196023 (PR #22):

```
run 32192196023 (bom)     verify-pr total 21m50s;  apt 53s  (4%)
run 32292789516 (lento)   verify-pr total 41m1s - o dobro, mesmo codigo
run 32290684256 (ruim)    apt-get install bateu o `timeout 300`; o `update` seguinte estourou
                          o teto de 12min do passo e MATOU o job
```

O ramo "apt nao foi acionado" NUNCA executa: `ubuntu-24.04` nao traz nenhuma das tres, entao o
apt e acionado em toda execucao.

**A PRIMEIRA REDACAO DESTE PARAGRAFO ESTAVA ERRADA, e o erro e de metodo.** Ela dizia, com o
numero de UMA execucao: "o ganho de tempo seria de ~4%; a recomendacao de containerizar esta
certa quanto a reprodutibilidade e errada quanto a eficiencia". A revisao independente marcou o
n=1 como risco, e a execucao seguinte - o proprio PR desta onda - o realizou: o mesmo passo
consumiu mais de doze minutos e derrubou o build. O custo do apt nao e ~4%: e BIMODAL, ~53s
quando o mirror coopera e job-killing quando nao. Generalizar de uma amostra e exatamente o
que este repositorio condena, e foi feito aqui, dentro do ADR que condena.

Corrigido, o veredito muda de lado: a imagem OCI pinada por digest e o fix certo nos DOIS eixos
- hermeticidade (as versoes servidas sao as do dia: poppler 24.02.0, pandoc 3.1.3, ffmpeg
6.1.1-3ubuntu5) e disponibilidade. Fica declarado como BLOQUEIO conhecido, nao como
inconveniencia: ate ela existir, todo PR desta suite depende de um sorteio de mirror. Subir o
limite de tempo nao entra: o proprio cabecalho do workflow registra duas tentativas anteriores
de fazer isso (180->420->300), e perseguir uma distribuicao de rede nao e corrigir uma causa.

## A segunda rodada: cinco criticos DENTRO desta onda

Tudo acima descreve a PRIMEIRA versao desta onda. Ela foi submetida a `revisor-codigo` antes do
merge, e voltou com cinco criticos, todos medidos em copia descartavel. Registrar isso e o ponto,
nao a nota de rodape: **tres dos cinco eram a mesma classe que esta onda diz corrigir, cometida
dentro da correcao.**

**C1 - o `kind` era o criterio e morava no objeto governado.** A tabela de obrigacoes saiu do
portao para `evidence-policy.json` - correto -, mas a CHAVE de entrada nela ficou em
`registry.json`, editavel pelo mesmo PR. Medido: reclassificar seis `hook_guidance` para
`hook_instrument` derruba a divida de 89 para 77 com o portao VERDE, porque a monotonicidade
proibe crescer e reclassificar encolhe. E o ADR 0034 um nivel acima, outra vez. Fechado por regra
de conjunto: reclassificar para um tipo que deve MAIS e progresso e passa; para um que deve
MENOS, reprova.

**C2 - `source` arbitrario contornava a regra de criacao.** "A fonte ja existia na base" e um
fato que o PR nao pode forjar, mas o PR escolhe QUAL caminho declarar. Medido: capability nova
com `kind: agent` e `source: "README.md"` entrava com +4 obrigacoes e o caso escrito para pegar
isso imprimia PASS pelo nome. Fechado amarrando a fonte a forma canonica do tipo, e exigindo
fonte unica.

**C3 - CC6 aceitava a claim exata que existia para impedir.** A regra so exigia
`write_confinement: none` quando havia agente `writes: false` COM shell. Marcar os dez agentes
como `writes: true` esvaziava a condicao e `sandbox` passava - e a clausula de antivacuidade
imprimia `PASS ha agentes writes:false a conferir (com shell: 0)`, um rotulo afirmando o que a
propria contagem negava. Fechado trocando o gatilho: a pergunta certa nao e quem declarou nao
escrever, e se existe ator com shell.

**C4 - os numeros publicados contradiziam o artefato do mesmo commit.** O ADR dizia
`D_E = 87 sobre 33`; o portao media `89 sobre 34`. A prosa foi escrita antes de a ultima
capability entrar. Fechado corrigindo os tres arquivos E fazendo `tests/unit/governance-links.py`
RECONFERIR o numero do ADR contra a saida do portao - a mesma forma que ja recontava o corpus,
agora aplicada ao arquivo que JUSTIFICA a onda.

**C5 - `_digest_de` ignorava o leitor.** Declarava receber o leitor e lia sempre do disco: ao
avaliar a base, o dossie vinha do blob-base e o digest do artefato vinha do HEAD. Qualquer PR que
tocasse o componente invalidava os dossies DA BASE, inflando `d_base` e AFROUXANDO a
monotonicidade - fail-open, na direcao exata que a onda 14 existiu para fechar. Latente hoje
(zero dossies), e o mecanismo-titulo da onda errando no caminho sem cobertura. Fechado fazendo a
ref viajar com o leitor, e o discriminante agora e o proprio PR: todo PR muda um arquivo, e para
esse arquivo os digests de disco e de base TEM de diferir. Medido com o defeito reintroduzido em
copia: `TOTAL=30 FAIL=2`.

Mais oito avisos, dos quais seis eram defeito e foram corrigidos. Eles recebem ID aqui porque
a rodada seguinte mostrou que achado sem identificador nao entra em contagem nenhuma - e um
corpus so pode ser conferido quanto a COMPLETUDE contra identificadores que existam:

**A1** - `TypeError` em metadado malformado, introduzido pelo bloco novo: a base recusava limpo
com `SCHEDULE_ERROR`, o head saia por traceback.
**A2** - o portao implementava DUAS das tres condicoes que a propria policy declarava para
`executed_suite`.
**A4** - parser artesanal de frontmatter errando cinco formas de YAML valido, todas fail-open,
num repositorio que ja tinha um modulo PyYAML que RECUSA rodar sem a dependencia.
**A5** - `orchestration/environment.json` citado na policy e inexistente.
**A6** - separacao de oraculo decidida por ordem de iteracao (`setdefault`: o primeiro produtor
de `diff` vencia).
**A7** - o no `mutation`, mesmo ator e escopo irrestrito, fora da regra.

Os dois restantes viraram declaracao: **A3**, a bijecao registry-manifesto cobre 33 dos 49
componentes, e os 16 de fora (`adapter`, `doctool`) seguem sem obrigacao de prova modelada; e
**S6**, fonte compartilhada entre capabilities, fechada junto de C2.

E o efeito colateral da onda sobre suites vizinhas foi de mesma natureza, e vale registrar
porque quase passou por "contaminacao de ambiente": `tests/unit/schedule.sh` tem contagem
esperada fixa; `tests/unit/cobertura.sh` isenta cobertura POR NUMERO DE LINHA e faz
`str.replace` mudo de uma ancora que a onda deslocou; `tests/unit/claims.sh` derivava uma ancora
falsa de `git hash-object README.md`, que deixa de existir como objeto quando o README tem
mudanca nao commitada. As tres reprovaram, e o primeiro diagnostico - "as suites ficaram
vermelhas porque rodaram em paralelo com as sondas do revisor" - estava ERRADO: eram defeitos
reais, dois deles introduzidos por esta onda e um pre-existente que ela expos. As isencoes de
cobertura foram reancoradas e a contagem voltou a exatamente 35 itens, o que e a evidencia de
que houve deslocamento e nao descoberta de codigo sem teste.

## O que o primeiro teste do portao de emoji encontrou

Vale isolar, porque e o retorno mais direto da onda inteira e nao estava previsto. A suite nova
reprovou DENTRO de `scripts/status.sh` e passava isolada. A diferenca era uma linha do gerador:

```
export LC_ALL=C
```

Sob locale C, o `grep -P` da classe de emoji nao "nao casa" - ele ERRA:

```
$ LC_ALL=C grep -P '[\x{1F300}-\x{1FAFF}...]'
grep: character code point value in \x{} or \o{} is too large       -> rc=2
```

E a linha do hook era `grep -P "$EMOJI" >/dev/null 2>&1 && { bloqueia; }`. Em `A && B`, **rc=2
(erro) e indistinguivel de rc=1 (nao achou)**: o `&&` nao dispara, o hook sai 0, e o emoji passa.
O `2>&1` engolia ate a mensagem do grep. A garantia que CLAUDE.md secao 8 declara estava
desligada, silenciosamente, em todo processo que herdasse aquele ambiente - e nao havia teste
que pudesse acusar, porque ate esta onda o hook nao tinha teste nenhum.

A correcao tem duas camadas, e a segunda vale mais que a primeira:

1. locale UTF-8 pinado para aquele `grep` - conserta o caso conhecido;
2. `rc` fora de {0,1} passa a BLOQUEAR - conserta a classe. Portao que nao consegue checar nao
   pode responder "limpo".

Tres casos pinam isso, e a razao de serem tres e instrutiva. AD9 (emoji sob `LC_ALL=C` bloqueia)
e AD10 (com `grep` inutilizavel o portao bloqueia) nao bastam: com o fail-closed no lugar,
REMOVER o pino de locale nao afrouxa nada - o grep erra e o portao bloqueia. O efeito real de
perder o pino e o oposto, bloquear TODO conteudo sob locale C, e so um CONTROLE NEGATIVO sob o
mesmo locale o enxerga. Dai AD11. O mutante MHG17 sobreviveu ate ele existir.

Duas armadilhas de shell foram pagas no caminho e ficam registradas porque nenhuma e obvia:
`set -euo pipefail` faz um pipeline que sai 1 ENCERRAR o hook antes do `case` (a primeira versao
da correcao matava o hook em todo conteudo limpo); e `VAR=x funcao` no bash define a variavel
para a funcao sem exporta-la ao `bash` filho que ela lanca - o caso AD9 passava sem nunca
exercitar `LC_ALL=C`, e foi o mutante que denunciou.

## A terceira rodada: o portao final derrubou a propria correcao

A versao anterior foi ao `refutador` com os cinco criticos ja fechados. Veredito: **NAO
MERGEAR**, com tres achados, dois deles reproduzidos com codigo de saida. Os dois primeiros sao,
outra vez, a familia que esta onda persegue - e o primeiro e a **terceira recorrencia
consecutiva**.

**F1 - o criterio saiu do portao e continuou editavel pelo PR.** A tabela de obrigacoes foi para
`evidence-policy.json`, fora do portao, e o ADR celebrou isso: *"A policy vive FORA do portao. Um
portao que carrega o proprio criterio e a forma que o ADR 0034 acabou de remover."* A frase
estava errada. O portao carregava a tabela do DISCO e a usava para julgar os DOIS lados:

```
$ # em copia, com proof_obligations esvaziado no mesmo PR
D_E(head)=0 obrigacoes em aberto sobre 34 capabilities
PASS  a divida das ja conhecidas nao cresce contra origin/main: head=0 base=0
TOTAL=30 FAIL=0
```

Mover o arquivo nao removeu a forma - trocou o nome da constante. `D_MAX` (onda 14), `kind`
(segunda rodada), `proof_obligations` (agora): tres vezes o mesmo insumo vindo do lado que o PR
controla. Fechado pela mesma regra da onda 14, aplicada um nivel acima: **o criterio do lado BASE
vem da ARVORE BASE**, mais a regra simetrica `obrigacoes_head[kind] SUPERSET obrigacoes_base[kind]`.
Medido depois do fix, com base sintetica igual ao head: o mesmo ataque sai `TOTAL=31 FAIL=2`.

**F2 - o C5 sobreviveu na funcao vizinha.** A correcao do "leitor ignorado" foi aplicada em
`_digest_de` e nao em `_pagas`, na condicao que a propria segunda rodada tinha acabado de
acrescentar:

```python
_ger = _le_do_disco("scripts/status.sh") or ""     # ignora o leitor
```

Medido com base==head: retirar a enumeracao de uma suite fazia a divida subir de 89 para 102
**enquanto o portao imprimia "nao cresce"**. Segunda reincidencia de "leitor ignorado" no mesmo
arquivo, e ela quebra a monotonicidade, que e a garantia-titulo da onda 14.

**F3 - claim publicada falsa.** `docs/status.generated.md` afirmava "passo dedicado no CI" para
TODO arnes de mutacao, e para os dois desta onda nao havia passo algum: 43 mutantes rodavam so na
estacao do autor. O rotulo era literal, impresso sem conferir. Duas correcoes: os dois arneses
ganharam passo dedicado - custo medido ANTES de decidir, 37s e 42s, o que torna "executar" mais
barato que "explicar" -, e o rotulo passou a ser COMPUTADO contra o workflow, para que nao possa
voltar a mentir sem que alguem o veja.

**O limite que o fix de F1 NAO cobre, e ele e deste commit.** A regra compara a tabela do head
com a da base, e neste commit a base nao TEM tabela - `evidence-policy.json` nasce aqui. O portao
imprime `bootstrap: ... a tabela do head julga os dois lados NESTE commit`. A excecao e limitada
por um fato que o PR nao pode forjar (a ausencia do arquivo na arvore anterior) e vale uma unica
vez; do proximo commit em diante `MCAP26` e `MCAP27` cobrem os dois caminhos. Registrar isso e
obrigatorio: seria facil publicar "F1 fechado" e omitir que, no commit que fecha, ele ainda esta
aberto.

E o que o portao final NAO conseguiu derrubar, tentando: a valvula de criacao (enumerou a arvore
da base e nao achou fonte nao registrada casando as formas canonicas), o portao de emoji, a
amplitude de `writes: false`, a separacao de oraculo, o autoteste do C5, e a reancoragem das
isencoes de cobertura - esta ultima com a ressalva de que a justificativa do autor ("contagem
identica prova deslocamento") e INSUFICIENTE, N adicionados e N removidos dariam o mesmo numero;
a propriedade se sustenta por outra evidencia, o deslocamento uniforme +5/+48 batendo com os
hunk headers do diff.

## A quarta rodada: o corpus estava consistente e incompleto

Depois do merge, o relatorio publicado para revisao externa voltou com quatro correcoes. Duas
sao de redacao, uma e de fato, e a quarta e uma fuga nova. A de fato e a que importa, e ela e a
tese deste repositorio aplicada ao instrumento que a documenta.

**G1 - `8 -> 89` nao e serie temporal.** A prosa dizia "o numero subiu de 8 para 89 porque a
medicao melhorou". As UNIDADES mudaram: a metrica antiga contava `skill sem dossie`, a nova
conta pares `(capability, dimensao)`. Sao estimadores diferentes sobre populacoes diferentes, e
apresenta-los como uma variavel medida em `t0` e `t1` e o mesmo erro de comparabilidade que este
repositorio cobra da literatura que cita.

**G2 - o `18` antigo e o `E_M = 18` novo sao a mesma POPULACAO, nao a mesma GRANDEZA.** A errata
dizia "e nao por coincidencia: e exatamente a divida de E_M das 8 skills e dos 10 agentes". Os
dezoito componentes sao os mesmos; o estimando nao e. Cardinalidade igual nao e identidade
semantica.

**G3 - o corpus estava internamente consistente e SELETIVAMENTE INCOMPLETO.** Este e o achado.
`tests/unit/governance-links.py` recontava `counts_by_mode` contra as linhas PRESENTES e nunca
conferiu se as linhas presentes eram TODOS os achados da fonte que o proprio corpus declara -
os ADRs. Faltavam dezesseis: os cinco criticos e oito avisos do `revisor-codigo`, e os tres do
`refutador`, todos da onda 15, todos documentados no ADR que o corpus cita como fonte.

Sobre esse universo, o relatorio publicado afirmou que a auditoria externa fora o modo mais
produtivo das ondas 13-15. Com o universo completo, a ordem se inverte:

```
                          antes (26)   depois (42)
leitura-estrutural            2            15
remedicao                     6             9
auditoria-externa             6             6
aplicacao-de-instrumento      3             3
                          (ondas 13-15)
```

Os modos INTERNOS acharam mais que a auditoria externa, e por margem larga. O que a auditoria
externa tem de distinto nao e volume, e POSICAO: ela acha defeitos DENTRO de correcoes que os
modos internos acabaram de aprovar, tres vezes seguidas. Isso e complementaridade demonstrada;
superioridade quantitativa o dado refuta.

    corpus internamente consistente  NAO IMPLICA  corpus completo

Fechado com tres coisas, e a ordem entre elas importa: um CRITERIO DE INCLUSAO explicito - todo
defeito de rodada nomeada que resultou em alteracao entra -, IDENTIFICADORES nos avisos que ate
entao viviam em prosa (achado sem identificador nao entra em contagem nenhuma), e um portao que
exige que todo ID citado com marcador estruturado num ADR exista no corpus. Discriminante
medido: removendo `F2` e RECONTANDO `counts_by_mode` - isto e, preservando a consistencia
interna -, o portao novo reprova.

**G4 - a capability nova ainda escolhe a propria carga de prova.** A regra de nao-rebaixamento
protege capability JA CONHECIDA, comparando contra a base. Para uma capability NOVA nao ha lado
base, e os tres tipos de hook aceitam a mesma forma de `source`. Reproduzido:

```
$ # hook novo que BLOQUEIA de verdade (exit 2), declarado hook_instrument
D_E(head)=89 obrigacoes em aberto sobre 35 capabilities
TOTAL=31 FAIL=0        <- divida inalterada, portao verde
```

Devendo so `E_M`, ele paga com uma suite que o invoca e entra com divida zero. E a continuacao
da familia num quarto nivel: `D_MAX` -> `kind` de capability existente -> `proof_obligations` ->
**classificacao de capability nova**. Cada correcao subiu um nivel e o parametro restante seguiu
sob controle do avaliado.

NAO FECHADO NESTA ONDA, e por decisao declarada: fechar exige um estado `hook_unclassified` com
obrigacao conservadora e uma dimensao de prova de CLASSIFICACAO - propriedades OBSERVADAS
(`can_block`, `injects_context`) decidindo o tipo, em vez de o autor declara-lo. Isso e desenho
proprio, nao remendo, e empilha-lo aqui repetiria o padrao de correcao N+1 que este ADR
documenta em tres niveis. Fica registrado com a reproducao acima, que e o que permite a proxima
onda comecar do fato e nao da suspeita.

**G5 - `E_S` dispensado para guidance nao esta fundamentado.** `hook_guidance` e
`guidance_document` nao devem `E_S` hoje. A justificativa da policy fala do portao, nao da
guidance: uma instrucao injetada em toda sessao pode induzir chamada de tool perigosa, alterar
confianca ou autorizacao, e interagir com outra guidance. A dispensa e aceita como decisao
provisoria e nao como conclusao - fechar exige definir o ORACULO de `E_S` para intervencao
textual, que hoje nao existe.

## Limites, declarados

`E_U` esta em aberto para as 34 capabilities e continua sem instrumento: nao ha corpus de
tarefas nem harness de A/B neste repositorio. A eficacia externa segue `NAO VERIFICADO`.

A isencao de descoberta significa que, no commit que registra uma capability, ela fica fora da
comparacao com a base. A janela e fechada pela assercao de lastro - `paid` sem evidencia valida
reprova -, nao pela monotonicidade.

A classificacao de hook em gate/guidance/instrument foi medida por execucao para nove dos
catorze; para os demais vem do contrato declarado no cabecalho do proprio hook, conferido contra
a suite que ja os executava. Nao ha, neste repositorio, prova de que um hook classificado
`guidance` seja incapaz de bloquear em alguma trajetoria nao exercitada.

`fable-guard.sh` tem falso positivo medido e NAO estreitado: uma linha de Bash com uma seta ASCII
e o token do sentinela satisfaz o detector sem que haja escrita. Afrouxar um detector fail-closed
para conveniencia de quem escreve teste troca seguranca por ergonomia - o custo do falso positivo
e um round-trip, o do falso negativo e o modelo fabricar a propria autorizacao. O comportamento
fica PINADO por teste, para que estreita-lo passe a exigir declaracao.
