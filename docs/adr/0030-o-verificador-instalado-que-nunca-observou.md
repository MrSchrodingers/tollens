# ADR 0030 - O verificador instalado que nunca observou

Data: 2026-08-12
Estado: aceito
Precede: nao ha
Sucede parcialmente: ADR 0029 (as nove ondas), ADR 0007 (decisao sobre `memory:`), ADR 0011
(a clausula `correlacao 1`), ADR 0026 (nome do instalador de fase 2)

## Contexto

Duas auditorias externas independentes leram o repositorio em 2026-08-12, sem contato entre si
e por caminhos diferentes. Convergiram em cinco pontos. Esta onda existe para responder ao que
elas nomearam, e o achado central nao foi nenhum dos cinco: foi o que a tentativa de responder
ao primeiro deles revelou.

## O achado que organiza os demais

A onda 9 integrou `evidence/probes/github-ruleset.py` ao CI e o relatorio daquela onda disse
"instalado, fail-closed, condicionado ao RULESET_READ_TOKEN". Cada palavra e literalmente
verdadeira. A medicao:

```
$ gh run view 31641449160 --log | grep -a "CONTRA A API REAL"
  env:
    GH_TOKEN:                                     <- VAZIO
  NAO VERIFICADO: RULESET_READ_TOKEN ausente.
$ gh api repos/MrSchrodingers/tollens/actions/secrets --jq '.secrets[].name'
                                                  <- nenhum
```

O segredo nunca foi configurado. O probe tem 188 assercoes, 30 mutantes, 86% de cobertura de
ramo com piso em catraca - e **nunca mediu nada contra a API real em execucao automatica**.
Toda execucao desde a integracao caiu no ramo da lacuna e saiu 0.

Isto e a mesma forma do ADR 0029, um degrau abaixo do ultimo que ele registra. La, o elo era
`Mechanism` endurecido seis vezes enquanto `ObservableVerifier` nunca existia. Aqui o
`ObservableVerifier` existe, esta instalado, e **nunca observou**. Instalado e executado sao
proposicoes diferentes, e o relatorio da onda 9 confundiu as duas - o autor foi eu.

O quantificador que faltava:

```
CI_SUCCESS   =/=>   para toda garantia critica g:  Verified(g)
```

## O que esta onda mudou

### 1. Um job por termo do quantificador

`verify-live-policy` saiu de dentro de `verify-pr` e virou job proprio, com gemeo
`verify-live-policy-push` de nome distinto - o ruleset casa por NOME de contexto, e homonimo
entre workflows tornaria um required check futuro ambiguo. Sem o segredo o job sai **2**, nao 0:
o GitHub so oferece success/failure para um passo de `run:`, entao o unico mapeamento honesto de
`NOT_VERIFIED` e nao-verde.

O segredo passou a existir em 2026-08-12, com um PAT de escopo `Administration: Read` restrito a
este repositorio. Medido antes de gravar: o token devolve `bypass_actors` (0 atores) e o probe
sai PASS. `verify-live-policy` NAO entrou na lista de required checks nesta onda - promove-lo e
decisao separada, tomada depois de haver historico de execucao verde.

**Defeito que esta propria mudanca quase introduziu.** `FE4` de `tests/unit/fronteira-externa.sh`
definia o gemeo de push por exclusao e exigia que houvesse exatamente UM. Com dois jobs por
arquivo o contador quebrou - mas o problema silencioso era outro: o job NOVO do lado do PR nao
responde a `push`, logo nao era gemeo de ninguem e **escapava inteiramente da checagem de
paridade**. Um arquivo podia ganhar job que o outro nao tem, sem reprovar. FE4 passa a parear por
PAPEL e exigir bijecao entre os dois arquivos. Tres mutantes, tres mortes.

### 2. Capability: de adjetivo a mecanismo, e o limite que continua aberto

Oito agentes que `orchestration/registry.json` declara com `writes: false` recebiam `Write` e
`Edit` no runtime. O discriminante foi medido antes de haver documentacao: acrescimo nao
solicitado em 8/8 dos que declaravam `memory: user` e 0/4 dos que nao declaravam. A causa foi
depois confirmada em fonte primaria, verbatim de
`https://code.claude.com/docs/en/sub-agents.md`, secao "Enable persistent memory":

> "Read, Write, and Edit tools are automatically enabled so the subagent can manage its memory
> files."

O campo saiu dos oito, nas duas arvores. `declared-capabilities.py` ganhou a propriedade
correspondente: exit 1 com 16 violacoes sobre o estado anterior, 0 sobre o corrigido, 1 de novo
se `memory:` reaparecer em um unico agente.

**O que isso NAO fecha, e a afirmacao contraria seria o defeito.** Os oito mantem `Bash`, que
escreve por `>`, `tee`, `sed -i`, `python3 -c` ou `git apply` - superficie estritamente maior que
`Write` e `Edit`. O verificador afirma "capacidade declarada compativel com contrato declarado",
nao "read-only". Ha caso de suite que reprova se essa linha de limite sumir da saida.

Read-only como MECANISMO exige sandbox de filesystem. Ver a secao de limites.

### 3. O caminho sancionado que nao terminava

`execution/adapters/documents/media.json` declarava `pipeline` onde o executor itera `.plans[]`.
`doctool.sh plans <png>` saia 5 com erro cru de `jq`; `probe` devolvia `"tool":"null"`. Nenhum
verificador conferia conformidade de adaptador - a CI fazia `jq -e .`, que e sintaxe. Um fork de
schema atravessou nove ondas por ali. `evidence/validate-adapters.py` fecha a classe.

E havia um segundo defeito atras: `read-budget.sh` consultava o registro ANTES do teto de
tamanho, negando imagem por EXTENSAO. A receita que ele mesmo imprime manda reduzir e ler o
resultado - e o resultado reduzido tambem e imagem, tambem caia no registro, e tambem era negado.
Medido: 640914 bytes contra teto de 2 MB, `exit 2`. **O plano terminava em "agora leia", e a
leitura era impossivel.** Um portao cuja saida ele mesmo bloqueia nao e portao, e armadilha - e a
consequencia pratica, nesta mesma sessao, foi eu ter de PERGUNTAR ao operador qual imagem era
qual em vez de olhar.

### 4. Monotonicidade da observabilidade, como invariante

```
Information(x') SUBSET Information(x)  =>  Verdict(x') NAO-MELHOR-QUE Verdict(x)
```

Seis verificadores reais, dois regimes cada, vereditos comparados. O delegado **recusou a ordem
que a delegacao sugeria** e a recusa esta certa: nao `PASS > NOT_VERIFIED > FAIL`, mas `PASS`
como unico topo, com `FAIL` e `NOT_VERIFIED` abaixo e INCOMPARAVEIS. Duas razoes verificaveis: o
consumidor real nao distingue 1 de 2; e a ordem total reprovaria a correcao que o ADR 0029
declara correta. `FAIL` afirma violacao MEDIDA, `NOT_VERIFIED` afirma AUSENCIA de medicao - nao
estao no mesmo eixo.

O mutante que importa nao e o sintetico: e uma copia do probe com `EXIT[PASS_PARCIAL]` de volta a
0, a decisao da onda 8. Reverter a onda 9 agora mata a propriedade.

### 5. Cadeia de suprimentos por conteudo

`==` inline pinava a versao de TOPO e deixava seis dependencias transitivas livres e sem hash.
`--require-hashes` sobre 13 pacotes e 307 hashes, gerado dentro de `ubuntu:24.04` (Python 3.12.3,
a familia do runner) porque resolver na Python 3.14 local produziria um fecho que o runner
poderia recusar. `S2` cresceu exatamente como o proprio comentario dele previa por escrito que
teria de crescer.

## Decisoes

1. **Garantia critica nao compartilha check-run com verificacao estatica.** Um job por termo.
2. **`NOT_VERIFIED` nunca mapeia para a conclusao externa de `VERIFIED`.** Sem medicao, o job
   sai 2, e 2 nao e verde.
3. **Nenhum agente com `writes: false` declara `memory:`.** Verificado por mecanismo.
4. **Paridade entre workflows e por bijecao de papel**, nao por contagem de gemeos.
5. **Nome de arquivo nao declara obsolescencia sobre codigo portante.**
   `apply-managed-legacy.sh` era o worker vivo que `apply-managed.sh` invoca em toda instalacao,
   incluindo producao. Renomeado para `apply-managed-worker.sh`. O nome era o defeito; nome que
   diz "legado" sobre codigo portante convida a remocao errada.

## Limites, declarados

**O sandbox de filesystem esta ATIVO e o `denyRead` NAO pegou.** Medido nesta sessao apos ativar
o escopo managed e instalar `@anthropic-ai/sandbox-runtime`:

```
NoNewPrivs: 1   Seccomp: 2   Seccomp_filters: 1
/etc            BLOQUEADO
~/.ssh          LEGIVEL          <- denyRead declarado, sem efeito observado
repo, $HOME     gravaveis
```

O sandbox contem: `/etc` saiu do alcance e `sudo` deixou de funcionar a partir da ferramenta Bash
(`no new privileges`). Mas a lista de `denyRead` que a politica declara nao produziu efeito
observavel - provavelmente porque a sessao ja estava em curso quando a politica mudou. Logo:
**read-only por mecanismo permanece NAO VERIFICADO**, e a politica atual contem um termo que
afirma proteger e nao foi observado protegendo. Isso e a forma deste ADR aplicada a esta onda.

**O efeito da remocao de `memory:` nao e observavel na sessao que a fez.** O registro de agentes
resolve na inicializacao. O discriminante para uma sessao NOVA esta em
`evidence/runtime-probes/capabilities.md` (vetor A1m, com a expectativa INVERTIDA por esta onda) e
na errata do ADR 0007.

**A eficacia externa continua ausente.** Nenhuma linha desta onda mede se o Tollens produz
software mais correto que o mesmo modelo sem ele. As duas auditorias convergem nisso e estao
certas: falta benchmark pareado com corpus congelado, pre-registro, analise clusterizada e
replicacao por terceiro. O que existe e evidencia INTERNA.

**Uma auditoria errou por deriva de versao.** A primeira afirma que `arXiv:2608.03836` esta em v2
e que "196 obligations" nao existiria, e usa isso como exemplo de "garbage in". Medido: a API do
arXiv devolve `v3, updated 2026-08-08`; a v3 contem o verbatim "the reference conjunction is
additionally TLAPS-proved unbounded (196 obligations)" e a v2 nao. Sexta instancia de deriva de
versao medida em um unico dia, e desta vez pegou o auditor. Nao desqualifica a auditoria;
confirma a exigencia de `vN` em toda citacao.

**Tres defeitos meus nesta onda, achados por rodar as suites e nao por reler o diff:**
renomeei um rotulo de assercao que era contrato com `propriedades.sh`, e as nove propriedades
passaram a reportar veredito VAZIO; a antivacuidade nova reprovava quando o workflow nao usa
`-r`; e inventei duas variaveis de shell que nao existiam no arquivo que estava editando. Nenhum
apareceria em inspecao.

**Uma falha intermitente foi perseguida ate o mecanismo, em vez de normalizada.**
`repository-hygiene.sh` reprovou uma vez e passou na seguinte, sobre `.mcp.json`. Causa medida:
o runtime mascara arquivos de configuracao com bind mounts no namespace da sessao (176 deles), e
o tipo exposto OSCILA - o mesmo caminho apareceu como `character special file / nobody / 666` e
como `regular empty file / ti / 444` com minutos de diferenca. O predicado passou a usar o
discriminante estavel (ser ponto de montagem, nao rastreado, sem conteudo), com as tres condicoes
exigidas em conjunto.
