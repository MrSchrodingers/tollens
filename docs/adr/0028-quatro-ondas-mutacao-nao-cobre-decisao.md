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
| 5 | (não commitado) | — | o filtro acima, e a causa estrutural registrada abaixo |

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
   ser pré-requisito do portão, para os executáveis de evidência deste repositório (os probes sob
   `evidence/probes/` e as suítes que os exercitam). O mecanismo que mede e aplica esse piso está
   sendo implementado por outro agente nesta mesma onda; esta decisão registra o que deve valer,
   não a implementação:
   - todo ramo de decisão que distingue `PASS`/`FAIL`/`NOT_VERIFIED` precisa ser executado por ao
     menos um caso da suíte, nas duas direções (tomado e não-tomado);
   - abaixo do piso, o portão reprova — mesmo com 100% dos mutantes declarados mortos;
   - o valor do piso é `[a ser preenchido pelo mecanismo]`. Não é fixado aqui: fixar um número
     sem medição, dentro da própria decisão que existe para corrigir números fixados sem medição,
     repetiria o defeito.

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

O corolário que `docs/adr/0020` deixou registrado (via `docs/method/CONHECIMENTO.md`, seção 8)
sobe um nível:

> "verificar o artefato não é verificar a integração" — corolário de 0020
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
  acima;
- toda claim que já citou contagem de mutantes como prova de suficiência precisa ser relida sob
  esta luz. `evidence/claims/C-018.yaml` é o caso concreto: a alegação usou 100% dos mutantes
  daquela onda como parte da evidência de suficiência em três momentos sucessivos (4/4, depois
  7/7, depois 11/11), e as três vezes foram seguidas por uma onda posterior que encontrou a mesma
  forma de defeito um nível acima. A mutação não mentiu em nenhuma das três — atestou
  corretamente sobre o código que existia. O limite é o que ela nunca poderia medir: o ramo que
  ninguém tinha escrito ainda.

### Limites explícitos

Este ADR **não cria o mecanismo**. O piso de cobertura de decisão está sendo implementado por
outro agente nesta mesma onda; até que ele esteja integrado ao portão e verificado em execução
real contra este repositório, o estado desta decisão é:

```text
ADVISORY, não GUARANTEE
```

— a mesma forma que `docs/adr/0027` declarou para si mesma, pela mesma razão: decisão sem
mecanismo, verificador observável e evidência fresca não é garantia, é intenção registrada.

Adicionalmente:

- cobertura de decisão, mesmo com piso em vigor, não prova que o teste afirma a coisa certa sobre
  o ramo que cobre — ver item 3 da Decisão. Um teste que executa e não afirma nada passa no piso;
- o filtro concreto que motivou este ADR (`r.get("type") == "required_status_checks"`, linha 278
  de `evidence/probes/github-ruleset.py`) continua ABERTO no momento em que este ADR é escrito.
  Corrigi-lo é mudança de código, e está fora do escopo deste documento;
- não há, ainda, medição de qual piso é alcançável neste repositório sem custo desproporcional de
  fixture. O valor "a ser preenchido pelo mecanismo" na Decisão 2 é uma lacuna deliberada, não um
  esquecimento;
- esta decisão vale para `evidence/probes/` e para as suítes que os exercitam. Não se estende,
  por ora, a outros executáveis de evidência do repositório (hooks, `install/`) — estendê-la exige
  decisão própria, quando o mecanismo existir e puder ser medido contra eles.

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
