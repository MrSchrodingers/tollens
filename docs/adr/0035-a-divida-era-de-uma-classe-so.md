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
D_E(head) = 89 obrigacoes em aberto sobre 34 capabilities
por dimensao: E_M 18   E_U 25   E_C 25   E_S 21
```

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

Mais oito avisos, dos quais seis eram defeito e foram corrigidos: `TypeError` em metadado
malformado introduzido pelo bloco novo (a base recusava limpo, o head quebrava); o portao
implementando duas das TRES condicoes que a propria policy declarava para `executed_suite`;
`orchestration/environment.json` citado na policy e inexistente; parser artesanal de frontmatter
errando cinco formas de YAML valido, todas fail-open, num repositorio que ja tinha um modulo
PyYAML que RECUSA rodar sem a dependencia; separacao de oraculo decidida por ordem de iteracao;
e o no `mutation`, mesmo ator e escopo irrestrito, fora da regra. Os dois restantes viraram
declaracao: a bijecao registry-manifesto cobre 33 dos 49 componentes, e os 16 de fora (`adapter`,
`doctool`) seguem sem obrigacao de prova modelada.

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
