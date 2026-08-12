# Observacao - o contexto exigido pelo required check passa a ser unico por SHA

- Data: 2026-08-04
- Ambiente: cliente `git`/`gh` em Linux local; a decisao e do servidor do github.com
- Artefato avaliado: `8f7b543ef7d61239cb9e7bf5210e40f72cb4f38d` (PR #5)

## A pergunta

Um required status check e identificado por NOME. Se mais de um check-run com o mesmo nome
existe sobre o mesmo SHA, qual deles a regra avalia quando eles divergem?

A pergunta importa porque esta e a unica fronteira desta arquitetura que o ator governado nao
sobrepoe. Ambiguidade nela nao e detalhe de configuracao: e a fronteira deixando de ser
inequivoca justamente no ponto que ela existe para decidir.

## O estado ANTES - medido, nao inferido

`.github/workflows/verify.yml` chamava-se `verify`, disparava em `push` e em `pull_request`, e
tinha um unico job `verify`. Sobre o head do PR #4:

```
$ gh api repos/MrSchrodingers/evidence-gate/commits/ef307bf1a4aef4fae2dcc34dc83bd86d4b620b0c/check-runs \
    --jq '.total_count, (.check_runs[] | "\(.name) | \(.conclusion) | app=\(.app.slug) | id=\(.id)")'
2
verify | success | app=github-actions | id=92057531104
verify | success | app=github-actions | id=92057522494
```

DOIS check-runs homonimos, mesmo SHA, ids distintos. O mesmo padrao aparece na lista de
execucoes: `30928684646` (pull_request) e `30928681840` (push), ambas sobre `ef307bf`.

A limitacao registrada em C-016 - "qual deles o required check avalia quando divergem e NAO
VERIFICADO" - descrevia, portanto, uma ambiguidade REAL e presente, nao hipotetica.

## O tratamento

Um arquivo por gatilho, com nomes de job literais e distintos:

- `verify-pr.yml` - `on: pull_request, merge_group`, job `verify-pr`. E o contexto EXIGIDO.
- `verify-push.yml` - `on: push`, job `verify-push`. Roda a MESMA verificacao; nao e exigido.

A propriedade buscada nao e `|{check-runs chamados verify}| >= 1`, e sim
`|{check-runs com o nome do contexto exigido}| = 1`.

### Por que nao houve reuso de passos

Composite action e reusable workflow foram considerados e descartados por motivo verificado, e
nao por estilo:

- composite action nao aceita `timeout-minutes` em passo. Doc primaria "Metadata syntax", chaves
  aceitas em `runs.steps`: `run, shell, if, name, id, env, working-directory, uses, with,
  continue-on-error`. O passo de provisionamento depende desse limite.
- o nome do check-run resultante de `workflow_call` nao foi localizado na doc primaria.

Ambos exigiriam AFIRMAR um nome de contexto sem poder verifica-lo - que e exatamente o defeito
sob correcao. O preco da escolha e a duplicacao dos passos entre os dois arquivos, e esse preco
e cobrado pelo caso FE3 de `tests/unit/fronteira-externa.sh`, que compara a estrutura dos dois
jobs e reprova se divergirem.

## Predicao registrada ANTES da medicao

Se o nome do check-run acompanha o nome do job, o push desta branch deve produzir sobre o mesmo
SHA exatamente dois check-runs, com nomes `verify-pr` e `verify-push`, um de cada - e nenhum
chamado `verify`.

A premissa "o nome do check-run acompanha o nome do job" nao foi localizada na doc primaria; o
que havia era a medicao do estado anterior (job `verify` sem `name:` explicito produziu
check-run `verify`). Por isso os dois jobs declaram `name:` explicito e IGUAL ao job id: com ou
sem `name:`, o string resultante e o mesmo, e a premissa deixa de decidir o resultado.

## Medido

```
$ gh api repos/MrSchrodingers/evidence-gate/commits/8f7b543ef7d61239cb9e7bf5210e40f72cb4f38d/check-runs \
    --jq '.total_count, (.check_runs[] | "\(.name) | \(.conclusion) | id=\(.id)")'
2
verify-pr | success | id=92127228645
verify-push | success | id=92127142340
```

```
$ gh run list --limit 6 --json databaseId,headSha,conclusion,event,name \
    --jq '.[] | select(.headSha=="8f7b543...") | "\(.databaseId) \(.name) \(.event) \(.conclusion)"'
30949346779 verify-pr pull_request success
30949321347 verify-push push success
```

Predicao confirmada exatamente: dois check-runs, nomes distintos, um por evento, nenhum chamado
`verify`. `|{check-runs chamados verify-pr}| = 1`.

## Conclusao

Sobre este SHA, o contexto destinado a decidir merge e produzido por exatamente um check-run, e
o job que roda em `push` nao pode ser confundido com ele. A condicao de refutacao era simples e
nao se realizou: bastaria aparecer mais de um `verify-pr`, ou um `verify` remanescente.

## Limites declarados

- A medicao e sobre UM SHA, num repositorio, com um provedor. Nao estabelece comportamento geral
  do GitHub Actions - estabelece que, nesta configuracao, o contexto exigido e unico.
- **O ruleset ainda nao foi trocado.** No momento desta observacao a regra continua exigindo
  `verify`, um contexto que deixou de ser produzido. Enquanto nao for editada para `verify-pr`,
  a fronteira nao esta apenas ambigua: esta exigindo algo que ninguem reporta. Isto e
  fail-closed - nenhum PR fecha - mas por motivo errado, e nao foi medido aqui.
- Continua NAO VERIFICADO qual check-run o GitHub avaliaria se dois homonimos DIVERGISSEM. A
  correcao remove a condicao em vez de responder a pergunta; medi-la exigiria empurrar um commit
  vermelho de proposito para o branch protegido.
- Nada aqui mede eficacia de engenharia. Mede que o portao tem um nome so.

> NOTA DE INTEGRIDADE (2026-08-12): os comandos acima citam `MrSchrodingers/evidence-gate`
> porque foi contra ESSE nome que eles foram executados. O repositorio passou a se chamar
> `tollens` depois. A renomeacao automatica reescreveu estas linhas e o `blob_sha` do ledger
> acusou a divergencia - reescrever comando gravado faz o registro afirmar uma execucao que
> nunca ocorreu naquela URL, que e falsificacao de evidencia. Restaurado ao que foi rodado.
