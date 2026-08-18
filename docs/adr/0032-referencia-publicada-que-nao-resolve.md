# ADR 0032 - Referencia publicada que nao resolve

Data: 2026-08-17
Estado: aceito
Sucede parcialmente: ADR 0025 (skills evidence-gated), ADR 0030 (o verificador instalado),
ADR 0031 (onde o experimento roda)

## Contexto

O hook de inicio de sessao anunciou `conformidade: 44/49 ok | 4 divergentes | 1 ausentes` e a
frase "o que roda NAO e o que o repositorio declara". A medicao contra o repositorio vivo:

```
$ bash install/verify.sh
conformidade: 48/48 ok | 0 divergentes | 0 ausentes | 0 orfaos
```

O hook executa `install/verify.sh` a partir de `/opt/.tollens-src`, o snapshot root-owned que a
fronteira managed exige (ADR 0026). Esse snapshot esta na onda 9. O verificador estava correto;
o REFERENTE e que era outro. Este e o ADR 0030 de novo, um nivel acima: nao o verificador que
nunca observou, mas o que observou a copia errada.

Puxar esse fio expos quatro classes de referencia publicada que nao resolve.

## 1. O portao que lia um arquivo por skill

`tests/unit/methodology.py` ganhou, na onda 10, um resolvedor de invocacao `/x`. O achado que o
originou foi `design-system-proposal/SKILL.md` invocando `/direcao-de-arte` em QUATRO pontos,
skill que nao existe.

Os quatro pontos foram corrigidos em `SKILL.md`, e o portao nascido junto passou a ler
exatamente o arquivo corrigido - `_f = _dir / "SKILL.md"`. Medido em 2026-08-17:

```
$ python3 tests/unit/methodology.py
TOTAL=50 FAIL=0

$ rg -n '/direcao-de-arte|/defesa-de-tese' execution/skills/promoted/ -g '*.md'
design-system-proposal/references/color-roles-and-review.md:26  /direcao-de-arte
design-system-proposal/references/color-roles-and-review.md:31  /direcao-de-arte
design-system-proposal/references/kickoff-prompt.md:28          /direcao-de-arte, /defesa-de-tese
design-system-proposal/references/lessons.md:4                  /defesa-de-tese
```

Quatro sobreviventes, na MESMA skill, um diretorio abaixo. A linha que monta `_locais` ja fazia
`rglob("*.md")`: os arquivos de apoio eram universo de RESOLUCAO e nunca fonte de LEITURA. O
portao conhecia os arquivos que se recusava a abrir. Alargado para todo `.md` da skill, ele
acusou CINCO - o quinto, `/produto`, era falso positivo vindo de `Marca(s)/produto(s)`, corrigido
no lookbehind junto com o caso `<` que ja estava tratado.

## 2. Comando publicado que nao existe

A regra de metodo diz que toda instrucao publicada ao usuario e EXECUTADA antes de ser publicada.
Dois comandos vivos falhavam:

```
$ bash scripts/medir-skills.sh            # passo 1 de /depreciar
bash: scripts/medir-skills.sh: No such file or directory
```

O arquivo real e `evidence/telemetry/medir-skills.sh`. O outro,
`bash tests/run.sh` em `docs/method/COMO-ADICIONAR-ECOSSISTEMA.md`, nunca existiu neste
repositorio; o par correto e `python3 evidence/validate-adapters.py` mais
`bash tests/mutation/adaptadores.sh`. Os tres foram executados antes desta linha ser escrita.

**O escopo do portao novo e estreito de proposito.** A varredura ampla de caminhos citados em
markdown rendeu 28 achados para 2 defeitos - 7% de sinal. Os 26 restantes se dividem em tres
classes que NAO se corrige:

| classe | exemplo | por que nao se toca |
|---|---|---|
| registro datado | `docs/adr/**` inteiro | o caminho era verdadeiro quando escrito; reescrever registro e falsificacao de evidencia |
| exemplo ilustrativo | `src/auth/session.py` como formato de ID | nao e comando |
| caminho de outro projeto | `python src/gen_tokens.py` | roda no artefato que a skill constroi, nao aqui |

O portao so casa caminho cujo primeiro segmento e diretorio de topo REAL deste repositorio,
precedido de interpretador.

## 3. Referencia por numero de secao

`~/.claude/CLAUDE.md` e o texto de maior autoridade do harness - suas regras sobrepoem o
comportamento default - e ate esta onda era o unico artefato do sistema fora do manifesto.

Havia oito referencias vivas a secoes dele por numero, e a numeracao ja tinha mudado sob todas:

- `Diretriz 13` e `13.1` (3x) - a secao nao existe; a config vai ate a 9
- `Diretriz 3.1` (4x) e `Diretriz 5` (1x) - a secao existe e diz OUTRA COISA

Resolver ERRADO e pior que nao resolver: o leitor confere, encontra texto, e conclui que a
citacao procede. Junto vinha uma capacidade morta - `C1-C10`, citada em quatro pontos como
checklist canonico, existia so na secao 13.1 de uma versao anterior do CLAUDE.md e nao sobrevive
em lugar nenhum do repositorio nem da config atual.

A correcao NAO foi renumerar. Numero de secao nao e identificador estavel: renumerar muda o
referente sem tocar na referencia, e nenhum portao detecta "resolve para outra ideia" - so
"resolve para o vazio". Cinco das oito resolviam, para a coisa errada. Foi removido o
acoplamento: as frases se sustentam sem o numero, e o portao reprova qualquer `Diretriz N` em
instrucao viva.

## 3b. O CLAUDE.md passa a ser governado, e por que isto e uma REVERSAO registrada

A primeira redacao desta ata declarava, na secao de limites, que o arquivo "continua fora do
manifesto" porque "e config privada e este repositorio e publico", e o comentario do portao em
`tests/unit/methodology.py` justificava a proibicao com "o referente nao e governado".

**A mesma onda o versionou.** Por instrucao explicita do operador, `execution/config/CLAUDE.md`
entrou como tipo `config` e o manifesto foi de 48 para 49 componentes. Duas revisoes
independentes pegaram a contradicao entre a ata e o commit - que e, literalmente, o defeito que
este repositorio existe para perseguir, cometido no documento que o corrige.

Fica como reversao declarada, nao como reescrita silenciosa. O que a decisao implica:

- **Triagem de conteudo antes de publicar.** Varredura por segredo, IP, e-mail, chave e caminho
  com usuario: limpa. Varredura independente do revisor por nome de cliente, host interno e
  topologia (14 classes): zero linhas. As 288 linhas sao metodologia.
- **Semeadura byte-exata**, para o primeiro `apply.sh` ser no-op comprovado (`cmp` identico) e
  nao um clobber silencioso.
- **Backup**, porque o conjunto de backup do `apply.sh` cobria `hooks agents skills` e
  `settings.json` e nao o novo destino. Sem isso, o segundo apply - o primeiro em que o arquivo
  vivo divergisse - destruiria 288 linhas de politica sem recuperacao. Medido e corrigido.
- **Fluxo de edicao invertido**, e isso e custo real: editar `~/.claude/CLAUDE.md` no lugar agora
  aparece como `DIVERGE`, e o proximo `apply.sh` sobrescreve. Passa a ser editar no repo e
  aplicar.

### O limite que a governanca NAO fecha

O tipo `config` fica no escopo de USUARIO. `install/apply-managed-worker.sh` restringe a politica
root-owned a `hook|adapter|doctool`, entao o texto de MAIOR autoridade do harness e distribuido
pelo canal MENOS governado, gravavel pelo ator, enquanto hooks de autoridade menor tem `/opt`
root-owned.

E abre superficie de divulgacao e de adulteracao durável: o repositorio e publico, e um PR de
terceiro que altere `execution/config/CLAUDE.md` e injecao de instrucao persistente e
cross-sessao com autoridade maxima no proximo `apply.sh`. O digest nao protege - ele e calculado
sobre a mesma arvore que o PR alterou, como `apply-managed-worker.sh` ja registra. O unico portao
e revisao humana de PR, e nenhum mecanismo deste repositorio substitui isso hoje.

## 4. Projecao que existe mas nao roteia

`orchestration/render.py` valida que cada agente tenha projecao em `.claude/agents/` e
`.codex/agents/`, e que os inventarios coincidam. Valida EXISTENCIA e INVENTARIO, nunca conteudo.

As dez projecoes carregam `description: "Projeção do agente canônico <nome>."` enquanto o
canonico traz o gatilho:

```
canonico:  PORTAO FINAL antes de declarar pronto ou fazer merge. Le a evidencia CRUA (git diff,
           saida de comando) e TENTA REFUTAR a solucao [...] Read-only, nunca corrige, nunca elogia.
projecao:  Projeção do agente canônico refutador.
```

Pela doc primaria (https://code.claude.com/docs/en/sub-agents.md, conferida 2026-08-17), o campo
`description` e o que o modelo usa para decidir delegar - "Claude uses each subagent's
description to decide when to delegate tasks" - e a precedencia poe `.claude/agents/` de projeto
ACIMA de `~/.claude/agents/` de usuario. Dentro deste repositorio, portanto, a descricao util
fica sombreada pela inutil, nos dez agentes.

`evidence/runtime-probes/declared-capabilities.py` compara `tools:` e `memory:` entre canonico e
projecao. Nunca `description:`. A degradacao nao era trade-off declarado: era campo que nenhum
portao olhava.

## Decisoes

1. O resolvedor de referencia le TODO `.md` sob o diretorio da skill, nao so `SKILL.md`.
2. Comando publicado em skill, agente ou documento de metodo tem de apontar para arquivo
   existente, com escopo restrito a caminho repo-relativo precedido de interpretador.
3. Instrucao viva nao cita secao do CLAUDE.md por numero. O referente nao e governado.
4. A projecao replica o `description` canonico, e um portao compara os dois.
5. Registro datado - `docs/adr/**` e skill em `deprecated/` - fica FORA de todos esses portoes,
   por desenho. Corrigir registro nao e higiene, e falsificacao.

Os itens 1, 2 e 3 foram validados por mutacao: reintroduzido o defeito num clone via
`TOLLENS_ROOT`, cada assercao reprova; o clone limpo fica verde.

## Limites, declarados

O CLAUDE.md agora e governado, mas so no escopo de usuario, e o canal publico que isso abre nao
tem portao automatico - ver 3b. A proibicao de citar secao por numero permanece: governanca
remove o caso "a secao nao existe" e nao remove o caso pior, "a secao existe e diz outra coisa".

O portao de comando so casa caminho precedido de interpretador. Caminho nu em prosa escapa - e ha
um exemplo vivo disso dentro do proprio arquivo recem-versionado, corrigido nesta onda.

Nenhum dos portoes desta onda observa o RUNTIME. Que o Claude Code de fato use `description` para
rotear, e que projeto tenha precedencia sobre usuario, vem da documentacao primaria citada na
secao 4, nao de sonda executada aqui. `evidence/runtime-probes/declared-capabilities.py` continua
comparando `tools:` e `memory:`, e agora `orchestration/render.py` compara `description:` entre
canonico e projecao - nenhum dos dois mede o que o runtime carregou.

O snapshot `/opt/.tollens-src` continua na onda 9 e so root pode atualiza-lo. Enquanto isso, o
relatorio de conformidade do inicio de sessao mede um referente desatualizado e deve ser lido
como tal.
