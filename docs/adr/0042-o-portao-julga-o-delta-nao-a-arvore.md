# ADR 0042 - O portao julga o delta, nao a arvore

Estado: aceito. Onda 25.

## O defeito, medido

O log do proprio portao (`~/.claude/evidence/*.jsonl`, 5054 registros) mostra **2942 `fail` contra
2110 `pass`** - 42% de aprovacao. Agregando o campo `detail` das 2942 reprovacoes: **um unico
motivo**, `falharam: python-analyzer`, o mais recente no mesmo dia da medicao.

A causa nao e o modelo reprovando em verificacao. E o adaptador rodando `ruff` sobre a **arvore
inteira**, entao qualquer turno num repositorio com divida preexistente reprova por trabalho que
nao e o do turno. Em `/var/www/amaral-intern-hub`, onde a telemetria mostra a maior parte da
atividade:

    173 diagnosticos na arvore
     87 dentro de 4 checkouts ANINHADOS   codigo de outras branches, fora do HEAD do turno
     86 no codigo do repositorio
        80 higiene    F401 73, F841 7
         6 quebra     F822 5, F811 1      defeitos REAIS, preexistentes

Contra 4 arquivos `.py` no ultimo commit.

Um portao que reprova 58% das vezes por motivo alheio ensina o operador a ignora-lo, e ai deixa de
ser portao. E a armadilha do "bug preexistente" que a onda 22 removeu das REGRAS e que seguiu viva
na CONFIGURACAO.

## A decisao

A pergunta muda. De `f(D(head))` - "esta arvore esta limpa?", cuja resposta nao depende do trabalho
feito - para `f(D(head) \ D(base))` - "este turno piorou alguma coisa?".

**Nao e um meio-termo entre `per_file` e arvore inteira.** A onda 24 tentou escolher um lado e
falhou nos dois: `per_file` elimina a divida alheia mas perde a quebra CRUZADA (remover uma funcao
quebra quem a chama, e esse arquivo nao esta no diff) e, medido, faz apagar um `.py` virar LACUNA e
bloquear. Sao DUAS CLASSES com escopos diferentes:

| Classe | Escopo | Por que |
|---|---|---|
| HIGIENE | so as LINHAS TOCADAS | divida de higiene alheia nao e do seu turno |
| QUEBRA | ARVORE INTEIRA, contra catraca | sua mudanca pode quebrar arquivo que voce nao tocou |

E uma terceira exclusao que nao tem trade-off: diagnostico dentro de **checkout aninhado** nunca
foi objeto do turno. As raizes sao DERIVADAS (diretorio com `.git` proprio), nunca lista de nomes -
`.worktrees` e convencao de quem criou, nao contrato.

## Identidade do diagnostico

Casar a catraca por `(arquivo, linha)` faz QUALQUER edicao acima deslocar tudo e gerar falso-novo
em massa: o baseline viraria ruido na primeira edicao. A chave e
`(caminho relativo, codigo, mensagem normalizada)`, com numeros da mensagem reduzidos a `#` - senao
`redefinition of unused 'x' from line 3` muda de digital quando o alvo se move, que e o mesmo
falso-novo pela porta dos fundos.

Isso nao e afirmado: `tests/unit/lint-delta.sh` LD6 e LD7 exercitam o mesmo defeito 44 linhas
abaixo (continua tolerado), outro simbolo no mesmo arquivo (bloqueia) e o mesmo simbolo em outro
arquivo (bloqueia).

## Onde a decisao mora

Em `evidence/lint-delta.py`, FORA do executor. A logica que decide bloqueio nao pode viver dentro
de um script de 400 linhas de shell que ninguem consegue exercitar isoladamente. O nucleo nao
executa analisador nem le repositorio: recebe diagnosticos, hunks e baseline, devolve veredito.
35 casos, e tres mutantes sobre as decisoes centrais - classificacao, catraca e escopo por hunk -
morrem.

O adaptador declara `scope: "delta"`, o mapa de campos da saida nativa e os `breakage_codes`.
Embutir os nomes de campo no nucleo faria cada ferramenta nova exigir edicao dele - e e assim que
um executor generico vira um executor de uma ferramenta so.

## O que o desenho errou, e quem pegou

Quatro defeitos apareceram por EXECUCAO, nenhum por leitura, e tres deles foram pegos pelos
proprios portoes deste repositorio:

1. `--hunks` obrigatorio matava a semeadura; o executor engolia o erro e seguia sem catraca.
   Pego pelo teste PONTA A PONTA - a suite unitaria nao via, porque sempre passava o argumento.
2. `> "$BLPATH"` criava o arquivo ANTES do programa rodar: emissao falha deixava baseline VAZIO,
   que bloqueava a re-semeadura e, se lido, toleraria nada. Escrita atomica.
3. **A catraca era semeada do estado ATUAL, anistiando a quebra do proprio turno.** Pego por
   `regressao-gate.sh` G1 ("falha em cache NAO vira sucesso na segunda parada"). O baseline passou
   a vir de `git archive HEAD` - leitura pura, sem registrar worktree nem tocar o indice.
4. Apos semear, o codigo forcava `RC=0` sem REJULGAR. A primeira parada passava sempre, inclusive
   para quebra recem-introduzida. Pego por G2 (anti-loop). Passou a rejulgar contra o baseline novo.

Nenhum caso do portao de regressao foi reespecificado. As 65 garantias antigas valem palavra por
palavra, e a guarda G_VAZIO ("acao nula nao aprova em silencio") foi replicada no ramo novo -
lista vazia de diagnosticos atravessaria o nucleo inteiro como "nada a bloquear".

## Custo declarado

A catraca BLOQUEIA UMA VEZ por repositorio, na criacao. A lacuna declarada nao e o julgamento -
esse acontece - e a TOLERANCIA recem-concedida, que nenhum humano revisou. O caminho do arquivo e
publicado para revisao ou remocao.

E o baseline e gravavel pelo ator governado, como o log de ativacao (G39). Indicio, nao prova.

## O que NAO se afirma

Que isto melhora a qualidade do trabalho. O que se afirma e o que foi medido: 2942 reprovacoes de
uma unica causa alheia ao turno deixam de ocorrer, quebra nova continua bloqueando, e quebra
preexistente e reportada a cada execucao em vez de bloquear. Se isso melhora o resultado do
operador e pergunta de experimento pareado, e esse continua nao executado.
