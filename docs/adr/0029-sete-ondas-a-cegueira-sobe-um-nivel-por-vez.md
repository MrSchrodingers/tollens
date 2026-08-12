# ADR 0029 — Sete ondas: cada camada de verificação é cega a uma classe, e a cegueira só fecha subindo de texto para execução

**Status:** aceito
**Data:** 2026-08-12

## Contexto

O ADR 0028 registrou quatro ondas com a mesma forma de defeito e decidiu um predicado absoluto
de cobertura de decisão. Três ondas depois, o padrão continua — e agora há medição suficiente
para nomear a causa, que não é nenhuma das instâncias.

| Onda | Fechou | O que a onda seguinte encontrou |
|---|---|---|
| 3 | precedência mascarada DENTRO do laço (`V12`/`V13`/`V14`) | a mesma precedência ANTES do laço |
| 4 | a classe por schema na fronteira (`valida_campo`) | o filtro de `type` que decide quem chega ao schema |
| 5 | o filtro de `type`; mutação é cega à omissão → piso de cobertura | o piso é satisfazível por diluição |
| 6 | o piso diluível (igualdade exata + predicado absoluto + completude) | o container ilegível coagido em `Required(P) = False` |
| 6b | o container ilegível → `NOT_VERIFIED` | o `return` novo recusa medir `¬Bypass` com `ruleset_id` em mãos |
| 7 | o sétimo degrau; `not all` → `not any` na composição de rulesets | o oitavo, nomeado e não corrigido (ver abaixo) |

Sete correções, sete instâncias, uma só classe: **um ponto de decisão descarta medição já feita,
ou decide sobre campo que não leu.** Nenhuma revisão encontrou o mesmo defeito duas vezes; todas
encontraram a mesma FORMA um degrau adiante.

## A causa, medida

Cada camada de verificação é cega a uma classe específica, e a cegueira é estrutural, não
acidental:

1. **Auto-avaliação do agente** não distingue sucesso de falso sucesso. Juízes LLM atingem no
   máximo AUROC 0.65 em tau2-bench e 0.54 em AppWorld (`arXiv:2606.09863`, HTML v1). O sinal
   está distribuído na trajetória inteira: 0.924 excluindo a mensagem de fechamento contra
   0.934 só com ela.
2. **Verificador determinístico não é verdade** — 18,5% de desacordo com revisão humana em 496
   tarefas auditadas (`arXiv:2607.02577`, HTML v1) — **mas é o melhor oráculo disponível**:
   precisão 83,8 contra 69,8 do melhor juiz LLM, e o erro é unilateral. Em 420 avaliações,
   19 falso-negativos e ZERO falso-positivos. Erra por rejeitar, não por aprovar. Para um portão
   cujo inimigo é o falso sucesso, esse é o modo de falha correto, e a consequência é
   contraintuitiva: recall baixo dá vontade de afrouxar o portão, e afrouxar troca o erro barato
   pelo caro.
3. **Mutação é necessária e cega à omissão.** Medido neste repositório: substituir as duas
   detecções de violação do probe por `elif False:` deixava 78 asserções e 11 mutantes VERDES.
   Não se mata o ramo que ninguém escreveu.
4. **Cobertura pega a omissão e é satisfazível por diluição.** Medido: o mesmo ramo não
   exercitado reprova sozinho (87.0%, abaixo do piso) e passa acompanhado de 30 statements
   cobertos (89.0%, OK). O denominador mascara.
5. **A classe de mutante fantasma não fecha por análise estática.** A âncora de aplicação
   (mutação escrita + oráculo invocado) é checagem TEXTUAL: um bloco forjado dentro de
   `if false; then ... fi` a satisfaz sem que nada rode. Fechar exigiria EXECUTAR o script de
   mutação de um `subject_snapshot` potencialmente hostil — recusado por fronteira de segurança.
   O limite é declarado no docstring de `evidence/validate-claims.py`, não fingido como
   fechamento.

A generalização que fecha o argumento: **as camadas 1 a 4 são todas checagens sobre TEXTO** — a
narrativa do agente, o resultado de um comando, o código escrito, o ramo escrito. A classe 5
mostra o teto: existe defeito que só a EXECUÇÃO distingue, e há execução que uma fronteira de
segurança proíbe. Onde isso ocorre, o estado honesto é *classe limitada, com o limite nomeado*,
nunca *classe fechada*.

## O elo que faltava, e que só apareceu na sétima onda

`evidence/probes/github-ruleset.py` tinha, em 2026-08-11: 155 asserções, 20 mutantes, 83,3% de
cobertura de ramo, um piso no portão — e **zero invocações fora de `tests/`**. Ausente dos dois
workflows, de `install/manifest.lock` e de todo hook. A claim `C-018` ancorava numa observação
manual de 2026-08-10.

Pela fórmula que este repositório publica,

    Guarantee(g) <=> Policy(g) ^ Mechanism(g) ^ ObservableVerifier(g) ^ FreshEvidence(g)

seis ondas endureceram o `Mechanism`, e o `ObservableVerifier` nunca existiu. É a instância mais
nítida do corolário registrado em `docs/method/CONHECIMENTO.md:189` — *verificar o artefato não é
verificar a integração*. Um instrumento pode ser verificado à exaustão e proteger exatamente
nada.

Simetria medida no mesmo dia, na ponta oposta: `tests/unit/methodology.py` passa 47/47 com 100%
do código de produção ausente (verificado: árvore contendo apenas dois arquivos JSON, `TOTAL=47
FAIL=0`, exit 0), e também não é executado por CI, `status.sh` ou `run.sh`. Dois instrumentos nos
extremos da escala de rigor, ambos desligados.

## Decisões

**1. O probe entra em caminho de execução recorrente, fail-closed.** Instalado em
`verify-pr.yml` e `verify-push.yml`, com exit 0/1/2 e reprovação nos três casos não-zero. Tratar
`NOT_VERIFIED` como verde seria a mesma classe reproduzida duas vezes nesta série (o verde vácuo
do `per_file`, e o container ilegível). O mesmo vale para `tests/mutation/fable-guard.sh`, que
nasceu fora do CI.

**2. Toda citação de preprint carrega a VERSÃO.** Seis casos de deriva material medidos em um só
dia: `arXiv:2602.12670` (86 tarefas / 11 domínios / 7 configurações na v1 contra 87 / 8 / 18 na
v4), `arXiv:2606.20659` (a v1 não contém os números da v2), `arXiv:2602.16666` (14 modelos na
v1/v2, 15 na v3; "18 months" vira "24 months"), `arXiv:2604.12147` (16.991 trajetórias na v1,
21.120 na v3), `arXiv:2503.13657` ("five popular MAS frameworks" na v1, "7" na v2/v3, e uma
frequência mudando 11x), `arXiv:2408.02442` (a Tabela 2, com gramática livre de contexto, só
existe na v3). Citação sem `vN` é subdeterminada. Isto é ADVISORY até existir campo obrigatório
no validador de literatura — trabalho nomeado, não feito nesta onda.

**3. Baseline escolhido depois de ver que o baseline honesto não separa é classe, não acidente.**
Medida em dois artigos independentes: `arXiv:2602.12670` rejeita por construção as tarefas em que
a intervenção não separa (*"tasks with no measurable separation between conditions are rejected
as low-signal"*, verbatim, v4); `arXiv:2602.01011` mede contra `At Least One Correct` — um
oráculo por item, estritamente mais forte que o melhor membro — e o próprio artigo publica a
diferença (5–19%). Com o baseline honesto, o resultado do segundo se inverte em 4 de 5
benchmarks. Todo número citado como "efeito de X" deve declarar contra QUE baseline foi medido.

**4. `revisor-codigo` é obrigatório em diff de autorização, e a série é a prova.** Os dois
defeitos críticos das ondas 6b e 7 foram encontrados por `revisor-codigo`, e nenhum pelo
`refutador`, que rodou sobre o mesmo arquivo. As cegueiras são complementares: o refutador lê o
diff procurando o que a tese esconde; o revisor lê o arquivo inteiro procurando o que o diff não
tocou. A série pulou o segundo por cinco ondas.

## Limites explícitos

**O oitavo degrau existe e não foi corrigido.** No primeiro laço sobre `rules`, um elemento cujo
`type` é ilegível sofre `continue` sem que `ruleset_id`/`parameters` sejam olhados, mesmo quando
esses campos no mesmo objeto seriam legíveis. `V27`/`V28`/`V29` provam que isso não vira PASS
fabricado; não provam que não é `NOT_VERIFIED` onde deveria ser `FAIL`. Não foi corrigido
deliberadamente: exige desenho novo, e o padrão desta série indica que merece a mesma revisão
independente que encontrou os sete anteriores, não uma correção apressada.

**Dívida de mutação, medida.** 29% do executável de produção (18 arquivos, 1.809 linhas) não tem
mutante algum. `control/hooks/fable-guard.sh` era o pior caso — 148 linhas de superfície de
autorização — e foi coberto nesta onda com 12 mutantes. Os outros 17 arquivos permanecem, com
`install/hooks-spec.sh`, `install/manifest.sh` e os hooks de `execution/` no topo por linhas
descobertas.

**Mutantes grosseiros não discriminam.** `MK3` derruba 36 asserções de uma vez, `MV4` 28, `MD4`
19. Um mutante que mata 36 casos não informa qual caso protege qual garantia, e o arnês o credita
a um único alvo designado. Faltam mutantes finos onde hoje há grosseiros.

**A suíte não está inflada — isso foi medido, não suposto.** Ao longo da série, asserções +90%,
mutantes +104%, código de produção +88%; a razão asserção/mutante caiu de 5,12 para 4,79. Das
263 asserções adicionadas, 100% caíram em suítes interrogadas por mutação e nenhuma em suíte sem
mutante. Nenhuma asserção qualifica para remoção. Redundância estrita permanece INDECIDÍVEL: o
critério exige cobertura por asserção, e não há instrumento de cobertura para os ~24 executáveis
bash, que são a maior parte da produção.

**A janela do mutante em disco é estreita, não nula.** `trap ... EXIT` restaura sob `SIGTERM` nos
dois arnesses testados, e `SIGKILL` a `t=12s` também deixou a árvore limpa; mas um mutante foi
observado em disco uma vez, após interrupção durante a fração de tempo em que o arquivo está
mutado. `AM3` exercita apenas `tests/mutation/run.sh`.

**Defeitos de método cometidos nesta onda, pelo operador desta sessão, e registrados porque a
regra que eles violam é do próprio repositório.** Foi declarado `administration: read` em
`permissions` do workflow — escopo que NÃO EXISTE, conferido na fonte primária depois de quebrar.
Chave inválida invalida o workflow inteiro: a execução saiu `failure` com zero jobs, sem log e
sem anotação, um modo de falha pior que um passo vermelho. É a regra 1 da seção 6.3 do
`CLAUDE.md` — *toda instrução publicada é executada literalmente antes de ser publicada*.
Também foram afirmados três mecanismos a partir de experimentos que não discriminavam (o verde
vácuo reproduzido no ramo errado; o overflow de `[ -gt ]`; a falsificação da garantia de
`SIGTERM`), todos corrigidos por medição posterior. Enunciar a regra não a executa.
