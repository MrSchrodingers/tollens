# ADR 0028 — Quatro ondas, a mesma forma de defeito: mutação não cobre decisão

**Status:** aceito
**Data:** 2026-08-11

## Contexto

Quatro correções sucessivas sobre `evidence/probes/github-ruleset.py` mediram o mesmo bloco de
decisão — o laço que resolve `not Bypass(a,P)` e `enforcement` por ruleset aplicável — e cada uma
foi seguida de revisão independente que encontrou, no MESMO bloco, uma forma do defeito que a
correção anterior não cobria:

| Onda | Commit | O que fechou | O que ficou aberto |
|---|---|---|---|
| 2 | `4a1c046` | chave `bypass_actors` ausente da resposta, antes tratada como `[]` (medido: ninguém burla) | valor `null` explícito e tipo de campo inesperado |
| 3 | `1b66443` | valor nulo e tipo do CONTAINER (`bypass_actors` que não é lista) | tipo do ELEMENTO (lista de strings, não de objetos), e mais três pontos com a mesma forma |
| 4 | `f97fc70` | elemento, `parameters`, `enforcement`, `strict_required_status_checks_policy`, `ruleset_id` parcial — fechados por `valida_campo`, um validador de schema único na fronteira | o FILTRO que decide quais regras entram no laço de validação (linha 278): `rsc = [r for r in rules if isinstance(r, dict) and r.get("type") == "required_status_checks"]` descarta, em silêncio, qualquer regra cujo `type` não bata exatamente com essa string |
| 5 | `734283e` | o FILTRO da linha acima, e dois ramos irmãos com a mesma forma — fechados pelo mesmo `valida_campo`, um passo mais cedo na fronteira | a causa estrutural registrada abaixo, que motivou a Decisão 2 — cujo mecanismo, medido nesta reconciliação, reproduz a mesma forma de lacuna um nível acima (ver "Limites explícitos") |

Cada onda cresceu a mesma suíte e citou o crescimento como prova de suficiência:
`tests/unit/fronteira-viva.sh` foi de 34/34 (onda 2) para 55/55 (onda 3) para 78/78 (onda 4);
`tests/mutation/fronteira-viva.sh` foi de 4/4 (onda 2) para 7/7 (onda 3) para 11/11 (onda 4)
mutantes mortos no caso-alvo (`evidence/claims/C-018.yaml`, linhas 63–64, 97, 102, 145, 149).

O ledger da própria alegação registra o padrão. A onda 3 se descreveu, no `warrant` de C-018,
como tendo fechado "a CLASSE aberta" que a onda 2 deixara (`evidence/claims/C-018.yaml:75-78`).
O ADENDO da onda 4 chama essa afirmação de FALSA, citando quatro pontos novos com a mesma forma
de defeito — C1 (`ruleset_id` ausente), C2 (elemento de `bypass_actors`), A1 (`parameters` sem
guard), A2 (`enforcement`/`strict` coagidos em violação fabricada) — encontrados no MESMO commit
que a onda 3 declarara fechado (`evidence/claims/C-018.yaml:112-129`). O próprio texto da onda 4,
já precavido, se recusa a repetir a promessa: *"Esta correção NÃO reautoriza dizer 'a classe está
fechada': cada onda anterior fez exatamente essa afirmação e foi refutada pela onda seguinte"*
(`evidence/claims/C-018.yaml:154-155`). A onda 4 não caiu no mesmo erro de vocabulário — e mesmo
assim deixou aberto o filtro da onda 5, porque nem a suíte de regressão nem a suíte de mutação
tinham como apontar para um ramo de decisão que nenhum caso jamais executava.

### A causa, medida nesta sessão contra o HEAD `f97fc70`

1. `bash tests/unit/fronteira-viva.sh` → `PASS=78 FAIL=0`, exit 0.
2. `bash tests/mutation/fronteira-viva.sh` → 11/11 mutantes mortos no caso-alvo, exit 0.
3. As duas ÚNICAS linhas do arquivo que produzem uma reprovação por `enforcement`/`bypass` fraco
   são `elif enforcement != "active":` (linha 467) e `elif cucb != "never":` (linha 522).
   Substituindo as duas por `elif False:` e repetindo (1): `PASS=78 FAIL=0`, exit 0 — inalterado.
   A suíte de regressão não nota a remoção dos dois únicos caminhos que a promovem.
4. Com o mesmo mutante, um cenário isolado (`probe()` chamado diretamente, `gh_api` substituído
   por stub determinístico, sem rede) com `enforcement=evaluate` e
   `current_user_can_bypass=always` sai `PASS`. Contra o código original, o mesmo cenário sai
   `FAIL`.
5. `coverage run --branch` sobre a suíte de 78 asserções mede 78% do arquivo. As duas linhas que
   registram a reprovação — `problemas.append(...)` dentro dos dois `elif` de (3), linhas 471 e
   523 — aparecem na lista `Missing`: nenhum caso da suíte jamais as executa.

Setenta e oito asserções e onze mutantes não detectam a remoção dos dois únicos caminhos que
decidem se um `enforcement`/`bypass` fraco vira reprovação, porque mutação só pode matar um
mutante contra um caso que EXECUTA o ramo mutado. Onde não há caso, não há execução para
comparar, e o mutante sobrevive por definição — não por falha da técnica, mas por ausência do
material sobre o qual ela opera.

## Decisão

1. **Mutação continua obrigatória** para toda garantia de segurança (regra de método 2 desta
   configuração, registrada em `docs/adr/0020`). Ela prova que uma linha de detecção já escrita
   resiste à remoção — a única prova disponível de que uma asserção depende de fato do código que
   diz depender. Isso não muda.

2. **Mutação deixa de ser suficiente.** Cobertura de DECISÃO (branch coverage — todo desvio de
   `if`/`elif`/operador booleano curto-circuitado, não apenas toda linha) com piso mínimo passa a
   ser pré-requisito do portão, para os executáveis de evidência deste repositório. O mecanismo
   que mede e aplica esse piso foi implementado nesta mesma onda (`evidence/cobertura.sh`) e já
   roda no portão (`.github/workflows/verify-pr.yml`, `verify-push.yml`). Esta seção registra o
   que foi DECIDIDO — o predicado que o mecanismo deveria satisfazer. A distância medida entre
   isso e o que o mecanismo entregue de fato verifica está registrada em "Limites explícitos", ao
   final deste documento, e não é diferença editorial:
   - todo ramo de decisão que distingue `PASS`/`FAIL`/`NOT_VERIFIED` precisa ser executado por ao
     menos um caso da suíte, nas duas direções (tomado e não-tomado);
   - abaixo do piso, o portão reprova — mesmo com 100% dos mutantes declarados mortos;
   - o valor do piso: o mecanismo não fixa um único número, fixa um piso POR ARQUIVO — o valor
     medido no momento em que `evidence/cobertura.sh` foi introduzido, arredondado para baixo a
     uma casa decimal (comentário "PISO, NAO TETO, E MEDIDO, NUNCA ARBITRADO" no próprio script).
     Pisos vigentes (`evidence/cobertura.sh`, lista `ALVOS`) e cobertura medida mais recente
     (`docs/status.generated.md`, seção "Cobertura de decisao"): `evidence/probes/github-ruleset.py`
     78.8% (medido 83.3%), `evidence/validate-claims.py` 77.7% (medido 79.9%),
     `evidence/validate-literature.py` 92.3% (medido 92.3%),
     `evidence/runtime-probes/declared-capabilities.py` 90.0% (medido 90.0%),
     `orchestration/schedule.py` 88.4% (medido 88.4%) — os quatro últimos ficam fora de
     `evidence/probes/`, o escopo que este item declarava; ver "Limites explícitos".

3. **Cobertura é piso, não teto**, e o limite precisa ficar escrito, não implícito. Cobertura de
   decisão prova que o ramo EXECUTOU; não prova que a asserção sobre ele é a correta, nem que o
   caso testa a propriedade certa. Um `elif enforcement != "active": pass` — sem
   `problemas.append` — executaria o ramo, cobriria as duas direções, e passaria no piso sem
   proteger nada. A defesa contra essa forma continua sendo mutação (item 1). As duas técnicas se
   compõem; nenhuma substitui a outra:
   - cobertura de decisão prova que o ramo existe e roda;
   - mutação prova que o ramo, uma vez executado, tem efeito detectável quando removido;
   - nenhuma das duas prova que o efeito é o CERTO — isso continua exigindo leitura humana e
     revisão independente do que a asserção afirma, não apenas de que ela afirma algo.

O corolário que `docs/method/CONHECIMENTO.md` (seção 8) registra como síntese das três regras de
método — duas delas, mutação obrigatória e E2E contra o binário, com origem específica em
`docs/adr/0020`, linhas 88 e 67 respectivamente — sobe um nível. A frase abaixo não está, verbatim,
no texto de `docs/adr/0020`: verificado nesta sessão (`grep -n "verificar o artefato"
docs/adr/0020-*.md docs/method/CONHECIMENTO.md` → zero ocorrências no ADR, uma em
`CONHECIMENTO.md:189`), a citação correta é ao documento onde a frase de fato está:

> "verificar o artefato não é verificar a integração" — `docs/method/CONHECIMENTO.md:189`
>
> "matar mutantes não é cobrir decisões" — este ADR

## Consequências

### Positivas

- a lacuna de omissão deixa de depender de uma revisão independente pensar em procurá-la. Foi
  assim que a onda 5 apareceu — por acaso de quem revisou, não por mecanismo. Com piso de
  cobertura, ela aparece no portão, na execução seguinte a qualquer ramo novo não coberto;
- toda claim de segurança futura que citar contagem de mutantes como prova de suficiência passa a
  precisar, ao lado do número de mutantes, do número de cobertura de decisão e do que ficou fora
  dele — os dois números juntos, nunca um sozinho;
- a suíte de regressão e a suíte de mutação continuam válidas para o que sempre mediram; o piso
  não as substitui, adiciona um terceiro sinal que nenhuma das duas produzia.

### Custos e consequências desconfortáveis

- o custo de execução do portão sobe: medir cobertura de decisão em toda execução é trabalho
  adicional, e um piso real vai reprovar código que hoje passa — incluindo, no dia em que o
  mecanismo entrar em vigor, o próprio `evidence/probes/github-ruleset.py` no estado descrito
  acima. **Esta previsão foi testada nesta reconciliação e não se confirmou**: o mecanismo entrou
  em vigor e não reprovou o arquivo. A razão é estrutural, não acidental — ver "Limites
  explícitos";
- toda claim que já citou contagem de mutantes como prova de suficiência precisa ser relida sob
  esta luz. `evidence/claims/C-018.yaml` é o caso concreto: a alegação usou 100% dos mutantes
  daquela onda como parte da evidência de suficiência em três momentos sucessivos (4/4, depois
  7/7, depois 11/11), e as três vezes foram seguidas por uma onda posterior que encontrou a mesma
  forma de defeito um nível acima. A mutação não mentiu em nenhuma das três — atestou
  corretamente sobre o código que existia. O limite é o que ela nunca poderia medir: o ramo que
  ninguém tinha escrito ainda.

### Limites explícitos

**Atualizado nesta sessão — reconciliação contra o mecanismo real.** O texto original desta seção
dizia "este ADR não cria o mecanismo... até que ele esteja integrado ao portão... o estado é
ADVISORY". Isso deixou de ser o estado: o mecanismo foi integrado na mesma onda em que este ADR
foi escrito (`evidence/cobertura.sh`, commit `a6f7bb4`) e já roda no portão. O que segue substitui
o texto original pela medição contra o mecanismo como ele existe hoje, não como era esperado.

**O que foi DECIDIDO** (item 2 da Decisão): um predicado ABSOLUTO — todo ramo de decisão que
distingue `PASS`/`FAIL`/`NOT_VERIFIED` precisa ser executado por ao menos um caso da suíte, nas
duas direções.

**O que foi IMPLANTADO** (`evidence/cobertura.sh`, bloco final, linha 197: `ok = medido >= piso`):
uma RAZÃO — `percent_covered` agregado por arquivo, comparado a um piso. `percent_covered`, na
nomenclatura do próprio `coverage.py`, é `(linhas cobertas + ramos cobertos) / (total de linhas +
total de ramos)` do arquivo inteiro. Nenhum ponto do mecanismo verifica, ramo a ramo, se cada
desvio individual foi exercitado nas duas direções; ele soma o exercitado e divide pelo total.

**Os dois predicados não são equivalentes.** Uma razão agregada é satisfazível com um número
arbitrário de ramos nunca exercitados, desde que haja código coberto suficiente ao lado para
compensar. Medido nesta sessão, reproduzindo de forma independente contra o HEAD atual — que já
inclui o fechamento do filtro abaixo e o mecanismo de piso (ver comandos e saída completa em
"Evidência executável"): para `evidence/probes/github-ruleset.py`, `num_statements + num_branches
= 226 + 134 = 360` (denominador); `covered_lines + covered_branches = 190 + 110 = 300` (cobertos);
`300 / 360 = 83.33%`, `83.3%` arredondado para baixo — o número que `docs/status.generated.md`
registra para este arquivo. O piso declarado em `evidence/cobertura.sh` é `78.8%`; `78.8% de 360 =
283.68`, portanto o mínimo inteiro de unidades cobertas que satisfaz o piso é `284`. Entre o que
está coberto (300) e o mínimo exigido (284) há **16 unidades de folga** — margem que poderia estar
totalmente descoberta, em vez de distribuída, sem que o piso reprovasse.

Essa folga foi exercitada pelo portão final da onda 5: duas detecções de violação novas, inseridas
sem nenhum caso de teste que as exercitasse, couberam inteiramente dentro dela —
`evidence/cobertura.sh --check` continuou saindo `0`. Este passo específico (inserir as duas
detecções e rodar `--check`) não foi reexecutado nesta sessão, cujo escopo ficou restrito a
`docs/adr/`; é reportado aqui como medição do portão final da onda 5. O número de folga acima (16,
com numerador e denominador reproduzidos de forma independente nesta sessão) é consistente com
ele: 16 unidades é margem plausível para dois ramos de detecção inteiros passarem sem exercício.

**A previsão da seção "Custos e consequências desconfortáveis" — "um piso real vai reprovar
código que hoje passa" — não se confirmou, e a razão é estrutural, não acidental.** Cada piso em
`evidence/cobertura.sh` é "o número MEDIDO nesta sessão... arredondado para baixo" (comentário do
próprio script; mesma frase na mensagem do commit `a6f7bb4`). O piso foi calibrado A PARTIR DO
código que existia no momento em que o mecanismo foi introduzido — por construção, ele não pode
reprovar o código que o calibrou. Reprovaria uma REGRESSÃO futura (um ramo hoje coberto deixar de
ser exercitado); nunca prova, e nunca provou, que o código no dia da introdução satisfazia o
predicado ABSOLUTO da Decisão 2.

**O filtro que motivou este ADR está fechado.** `r.get("type") == "required_status_checks"`
(citado acima na linha 278, no estado em que este ADR foi originalmente escrito) foi substituído
por um laço que valida `type` via `valida_campo` antes de decidir se um elemento entra em `rsc`, e
classifica elemento ilegível como `nao_medidos` em vez de descartá-lo em silêncio — commit
`734283e`, mesma onda deste ADR; código atual a partir da linha 324 de
`evidence/probes/github-ruleset.py` (`nao_medidos = []` / `rsc = []`). Isto NÃO fecha a distância
descrita acima: o filtro era um defeito PONTUAL no código medido; razão-versus-predicado é um
limite estrutural do mecanismo que mede QUALQUER código, incluindo o já corrigido.

**O escopo do mecanismo é mais largo do que este ADR declarava.** A lista `ALVOS` de
`evidence/cobertura.sh` cobre cinco arquivos: `evidence/probes/github-ruleset.py`,
`evidence/validate-claims.py`, `evidence/validate-literature.py`,
`evidence/runtime-probes/declared-capabilities.py` e `orchestration/schedule.py`. Quatro dos cinco
ficam fora de `evidence/probes/`, e um (`orchestration/schedule.py`) fica fora de `evidence/`
inteiramente — mais largo do que "esta decisão vale para `evidence/probes/` e para as suítes que
os exercitam", como a versão original desta seção declarava. Essa extensão não tem decisão própria
registrada; fica como pendência, não como fato já decidido.

**Estado consolidado desta decisão.** Não é "sem mecanismo" — isso mudou. Não é "implementado
conforme decidido" — isso nunca foi verdade, e a distância acima é medida, não hipotética. É um
mecanismo real, em produção no portão, que implementa uma propriedade estritamente MAIS FRACA do
que a decidida — e um mecanismo errado presente no portão carrega um risco que a ausência de
mecanismo não carrega: a leitura de que "há piso de cobertura no CI" pode ser tomada como prova do
predicado absoluto da Decisão 2, quando não é. Pela mesma regra que este repositório aplica a
decisão sem verificador fiel:

```text
ADVISORY, não GUARANTEE
```

— não mais pela razão original (mecanismo inexistente), mas porque o mecanismo existente não é o
mecanismo decidido. O `Status: aceito` no cabeçalho deste documento permanece: ele registra que a
decisão (o predicado absoluto, e a doutrina de que mutação sozinha não basta) foi adotada, não que
esteja implementada — a mesma separação que `docs/adr/0027` já usa (`aceito` no cabeçalho, ADVISORY
no corpo, sem mecanismo algum). A situação aqui difere da de 0027 em GRAU, não em NATUREZA: há
mecanismo, e ele está errado; 0027 não tinha mecanismo nenhum. A mesma separação de rótulos
continua correta nos dois casos, pela mesma razão declarada em 0027 — decisão sem verificador
fiel ao que foi decidido não é garantia, é intenção registrada.

Fechar esta distância exige uma de duas coisas, e nenhuma foi feita: um segundo mecanismo que
verifique execução por ramo individual (não razão agregada), ou uma revisão explícita da Decisão 2
que substitua o predicado absoluto pelo predicado de razão como padrão intencionalmente aceito. Um
agente distinto está, nesta mesma onda, trabalhando no mecanismo; esta atualização registra o alvo
e a distância medida, não a correção.

Do texto original desta seção, ainda válido:

- cobertura de decisão, mesmo com piso em vigor, não prova que o teste afirma a coisa certa sobre
  o ramo que cobre — ver item 3 da Decisão. Um teste que executa e não afirma nada passa no piso.

## Evidência executável

Reproduzido nesta sessão, contra `evidence/probes/github-ruleset.py` no HEAD `f97fc70`, revertido
antes de qualquer commit (nenhum destes passos alterou o repositório):

- `bash tests/unit/fronteira-viva.sh` — `PASS=78 FAIL=0`, exit 0.
- `bash tests/mutation/fronteira-viva.sh` — 11/11 mutantes mortos no caso-alvo, exit 0.
- mutante ad hoc (as duas linhas `elif enforcement != "active":` e `elif cucb != "never":`
  substituídas por `elif False:`): `bash tests/unit/fronteira-viva.sh` permanece
  `PASS=78 FAIL=0`, exit 0.
- cenário isolado (`probe()` importado e chamado diretamente, `gh_api` substituído por stub em
  memória, sem rede e sem subprocesso): `enforcement=evaluate` + `current_user_can_bypass=always`
  → `FAIL` (`estado=FAIL`) contra o código original; `PASS` (`estado=PASS`) contra o mutante
  acima.
- `coverage run --branch` (coverage.py 7.13.4) sobre a suíte de 78 asserções: 78% de cobertura no
  arquivo; `Missing` inclui as linhas 471 e 523 — os dois `problemas.append(...)` que registram
  `enforcement` e `current_user_can_bypass` fracos.

### Reconciliação (2026-08-11, contra HEAD `8e65211`, worktree `wave6b/b4-adr`)

Nenhum dos passos abaixo alterou `evidence/probes/github-ruleset.py`, `evidence/cobertura.sh` nem
qualquer outro arquivo fora de `docs/adr/`; são leituras e execuções read-only.

- o marcador de placeholder que ocupava a Decisão 2 (colchetes indicando valor pendente de
  medição) não resta neste documento: verificado por busca do texto literal do marcador original
  sobre esta versão do arquivo → zero ocorrências.
- `grep -n "verificar o artefato" docs/adr/0020-*.md docs/method/CONHECIMENTO.md` → zero
  ocorrências em `docs/adr/0020-*.md`; uma em `docs/method/CONHECIMENTO.md:189`.
- `grep -n "56.*59\|56 -> 59\|56->59" docs/adr/0028-quatro-ondas-mutacao-nao-cobre-decisao.md`
  (versão anterior a esta reconciliação) → zero ocorrências. A contagem "56 -> 59 mutantes" que
  motivou o item 4 do prompt de delegação desta tarefa não está, e nunca esteve, neste documento;
  nenhuma correção de número de mutante foi necessária aqui.
- `bash evidence/cobertura.sh` (modo relatório, sem `--check`) — todas as seis suítes de
  `SUITES` verdes, `coverage combine`/`coverage json` bem-sucedidos, tabela final:
  `evidence/probes/github-ruleset.py` medido `83.3%` (bruto `83.33%`), piso `78.8%`, `OK`;
  `evidence/validate-claims.py` medido `80.0%` (bruto `80.07%`), piso `77.7%`, `OK`;
  `evidence/validate-literature.py` medido `92.3%` (bruto `92.36%`), piso `92.3%`, `OK`;
  `evidence/runtime-probes/declared-capabilities.py` medido `90.0%` (bruto `90.09%`), piso
  `90.0%`, `OK`; `orchestration/schedule.py` medido `88.4%` (bruto `88.45%`), piso `88.4%`, `OK`.
  Nota: para `evidence/validate-claims.py`, este valor (`80.0%`/`80.07%` bruto) diverge do que
  `docs/status.generated.md` registra (`79.9%`) — `docs/status.generated.md` é gerado e está fora
  do escopo de escrita desta tarefa; a Decisão 2 e a nota acima citam o valor de
  `docs/status.generated.md` por instrução explícita da delegação (copiar o que os arquivos
  dizem), não o valor desta reexecução. A divergência é reportada ao orquestrador, não resolvida
  aqui.
- reprodução independente do detalhamento de `evidence/probes/github-ruleset.py`: instrumentação
  equivalente à de `evidence/cobertura.sh` (sitecustomize + `COVERAGE_PROCESS_START`) isolada
  sobre `bash tests/unit/fronteira-viva.sh` (`PASS=117 FAIL=0`), seguida de
  `coverage json --include=evidence/probes/github-ruleset.py`. Saída relevante do `summary`:
  `covered_lines=190`, `num_statements=226`, `num_branches=134`, `covered_branches=110`,
  `percent_covered=83.33333333333333`. `226+134=360`; `190+110=300`; `300/360=83.33%`. Piso
  `78.8%` de `360` = `283.68`, mínimo inteiro `284`; folga = `300-284=16`.
- a alegação de que duas detecções de violação novas, sem teste, couberam na folga acima com
  `evidence/cobertura.sh --check` saindo `0` **não foi reexecutada nesta sessão** — inserir código
  de detecção está fora do escopo desta tarefa (`docs/adr/**` apenas). É registrada em "Limites
  explícitos" como medição do portão final da onda 5, relatada ao agente que redigiu esta
  reconciliação; a aritmética da folga (16 unidades, denominador e numerador acima) foi verificada
  de forma independente e é consistente com ela.
- verificação do filtro fechado: `grep -n 'required_status_checks"\]\|rsc = \[\]\|nao_medidos = \[\]'
  evidence/probes/github-ruleset.py` confirma o laço com `valida_campo` a partir da linha 324,
  substituindo o list comprehension original citado na linha 278 da versão anterior deste ADR.
