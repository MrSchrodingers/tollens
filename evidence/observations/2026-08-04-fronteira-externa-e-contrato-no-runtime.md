# Observacao - a fronteira externa impoe, e o runtime honra `exit 2`

- Data: 2026-08-04
- Ambiente: Linux, `claude-code 2.1.220`; GitHub `MrSchrodingers/tollens`
- Fecha: P1 do `docs/HANDOFF.md`, e a lacuna de teste E2E da regra de metodo 3 (CLAUDE.md 6.3)

---

## 1. A fronteira externa passa a IMPOR (P1)

Ate esta data o `README` e o `docs/status.generated.md` registravam, corretamente, que a CI
executava mas nao impunha: `CI = feedback`, nao `gate`.

### Configurado

Ruleset via API, sobre o branch default, com `bypass_actors: []` - lista vazia e o ponto
inteiro. Em rulesets o bypass so existe por concessao explicita; administrador NAO contorna
por ser administrador, ao contrario da branch protection classica, onde isso e uma flag.

```
gh api -X POST repos/MrSchrodingers/tollens/rulesets --input ruleset.json
-> id 20385799, enforcement "active", bypass_actors []
```

Regras: `pull_request` (0 aprovacoes - o portao e a CI sobre o SHA, nao revisao humana, e num
repo de um autor so exigir aprovacao seria deadlock), `required_status_checks` com contexto
`verify` e `strict_required_status_checks_policy: true`, `deletion`, `non_fast_forward`.

### Medido - e este e o ponto

Criar o ruleset nao e impor. A tese deste repositorio e que prosa nao substitui execucao,
entao o enforcement foi TESTADO:

```
$ git push origin fase1/contrato-ancora:main
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
remote: - Required status check "verify" is expected.
 ! [remote rejected] fase1/contrato-ancora -> main (push declined due to repository rule violations)
exit=1

$ git rev-parse --short origin/main
92908d1        # inalterado
```

O push partiu do token com `admin: true` sobre o repositorio - isto e, do proprio ator
governado, na sua maior autoridade. Foi recusado.

**`¬bypass(ator, politica)` deixa de ser aspiracao e passa a ser fato medido.** E a primeira
propriedade deste projeto que nao depende da boa vontade do ator.

### Limites declarados

- A garantia e do GitHub, nao deste repositorio: quem tem `admin` pode DESATIVAR o ruleset.
  O que foi provado e que nao ha bypass *dentro da regra*, nao que a regra seja irremovivel.
  Remover deixa rastro no audit log; contornar em silencio, nao. A diferenca importa e e o
  maximo alcancavel sem uma autoridade organizacional acima do dono do repositorio.
- `strict_required_status_checks_policy` exige a branch atualizada com a base; combinado com o
  check sobre o head SHA, e o mais proximo de "evidencia ligada ao mesmo snapshot" que a
  plataforma oferece.

---

## 2. O runtime HONRA `exit 2` em `SubagentStop`

Motivacao: a regra de metodo 3 (CLAUDE.md 6.3) nasceu de um hook que emitiu JSON perfeito por
duas versoes enquanto o runtime o rejeitava. `subagent-contract.sh` bloqueia por `exit 2` e
NUNCA fora exercitado contra o binario - a suite o testava contra a propria saida, exatamente
o anti-padrao que a regra nomeia.

Metodo: um hook adicional de `SubagentStop`, injetado SO na sessao de teste via `--settings`,
que bloqueia uma unica vez (marca de estado em arquivo) para nao iterar ate o block cap.

### Medido

```
SubagentStop: 8 execucoes de hook = 2 rodadas x 4 hooks (3 do usuario + 1 injetado)
  exit=2 error   SONDA-BLOQUEIO-E2E: ... (rodada 1)
  exit=0 success x3
  exit=2 error   CONTRATO DE RETORNO INCOMPLETO (agente: investigador). Faltou: ANCORA-DE-EVIDENCIA
  exit=0 success x3
```

Tres fatos independentes, todos observados:

1. **O runtime honra `exit 2` em `SubagentStop`**: houve uma SEGUNDA rodada, e o texto do
   stderr da sonda chegou ao subagente - que o citou no retorno seguinte. O bloqueio nao e
   inerte.
2. **`--settings` SOMA aos hooks de escopo de usuario**, nao os substitui (4 por rodada, nao 1).
3. **Um retorno REAL foi bloqueado por engano** - ver secao 3.

### Verificacao de que o hook nao estava inerte

`exit 0` sozinho nao distingue aprovacao de inercia. O payload real capturado pela sonda
mostra `agent_type: "investigador"` preenchido e `last_assistant_message` com 496 bytes: as
precondicoes do hook foram satisfeitas e o `exit 0` e decisao, nao ausencia de execucao.

---

## 3. O falso bloqueio que a medicao revelou

Payload real, rejeitado por `ANCORA-DE-EVIDENCIA` ausente, contendo tres comandos com saidas
coladas:

```
- Comando: `wc -l /home/ti/evidence-gate/install/verify.sh` -> saida
  `71 /home/ti/evidence-gate/install/verify.sh`, exit code `0`. (caminho HISTORICO: o repositorio se chamava evidence-gate quando esta observacao foi gravada; reescrever o caminho falsificaria o registro de uma execucao real)
```

Causa, isolada alternativa por alternativa e confirmada em nivel de byte:

```
$ grep -o 'exit code ..' msg.txt | xxd
00000000: 6578 6974 2063 6f64 6520 6030 0a    exit code `0.
                                    ^^ 0x60
```

As quatro alternativas da ancora deram 0 casamentos. `0x60` (crase) entre `code ` e `0`
derrotava o padrao `[[:space:]]*[=:]?[[:space:]]*`; e `wc` nao constava da allowlist fechada de
nomes de comando.

Corrigido na CLASSE em `36db96f` (tolerancia a pontuacao de markdown; FORMA de comando em vez
de NOME), com corpus de 15 casos e `tests/mutation/contrato.sh`.

## 4. Cadeia completa de um bloqueio (PreToolUse)

Para provar que a decisao de um hook muda o estado do runtime, e nao so imprime:

```
tentativa de Write com emoji no conteudo
  PreToolUse hook_response: exit=2, outcome=error,
    stderr="Bloqueado: emojis nao sao permitidos (diretriz global)."
  arquivo alvo.md: NAO EXISTE apos a tentativa
  resposta do modelo: "Bloqueado: o hook artifact-discipline.sh rejeita emojis ... O arquivo
    nao foi criado."
```

Decisao do hook -> runtime impede a escrita -> modelo observa e explica. Os tres elos medidos.

## Limites declarados

- Uma versao de runtime, uma plataforma.
- O comportamento sob `CLAUDE_CODE_STOP_HOOK_BLOCK_CAP` continua nao medido; a sonda bloqueou
  UMA vez de proposito, justamente para nao iterar ate o cap.
- Nada aqui mede eficacia de engenharia. Mede que o mecanismo executa e que suas decisoes
  chegam ao runtime e ao modelo.

---

## Adendo - a formulacao precisa, e o falso alarme que quase publiquei

Ao reconferir o portao no fim da sessao (re-teste, nao memoria), `git push origin HEAD:main`
foi ACEITO e `origin/main` avancou. A leitura imediata seria "o ruleset parou de impor", e ela
contradiria tudo o que este arquivo afirma.

**Era falso alarme, e o que o mostrou foi o CONTROLE.** O SHA empurrado era exatamente o head
do PR #3, com os dois check-runs `verify` verdes e `mergeStateStatus: CLEAN`. O GitHub aceitou
e registrou `state: MERGED`, `mergedAt: 2026-08-04T16:16:12Z` - isto e, tratou o push como a
conclusao do merge, nao como um desvio dele.

Controle executado em seguida, com commit NOVO e nenhum PR associado:

```
$ git commit --allow-empty -m "teste do portao externo: commit sem PR"
$ git push origin HEAD:main
remote: error: GH013: Repository rule violations found for refs/heads/main.
remote: - Changes must be made through a pull request.
remote: - Required status check "verify" is expected.
 ! [remote rejected] HEAD -> main     exit=1
$ git rev-parse --short origin/main   ->  617e80e   (inalterado)
```

### A formulacao correta

Errado: "push direto para main e recusado".
Certo: **um artefato que nao passou por PR com os required checks verdes nao chega a `main`.**

Empurrar um SHA que ja satisfaz TODOS os requisitos nao e contornar a politica - e cumpri-la.
A propriedade que interessa nunca foi "o comando `git push` falha"; e
`¬bypass(ator, politica)`, e ela se sustenta: o ator, na sua maior autoridade, nao consegue
colocar em `main` codigo que a CI nao aprovou sobre aquele mesmo snapshot.

### Por que isto fica registrado

Uma observacao sem controle teria produzido uma refutacao FALSA de uma garantia verdadeira -
o erro simetrico do que este repositorio persegue, e igualmente caro. O primeiro teste da
sessao (recusa com GH013) e este (aceite) diferem em UMA variavel: a existencia de um PR
satisfeito. Sem variar essa variavel de proposito, qualquer um dos dois resultados sozinho
autorizaria a conclusao errada.
