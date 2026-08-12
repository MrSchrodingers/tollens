# Observacao - Applies(P,r) medido contra o endpoint autoritativo do GitHub

- Data: 2026-08-10
- Ambiente: Linux, `gh version 2.96.0 (2026-07-02)`; GitHub `MrSchrodingers/tollens`
- Fecha: o quantificador ausente da formula publicada (ver `docs/HANDOFF.md` e a delegacao que
  originou `evidence/probes/github-ruleset.py`)

---

## 0. O defeito que motivou o probe

Ate 2026-08-10 o ruleset `20385799` estava `enforcement: active`, `bypass_actors: []`,
exigindo `verify-pr` com `strict_required_status_checks_policy: true` - e
`conditions.ref_name.include` era `[]`, isto e, a regra se aplicava a ZERO refs. A formula
publicada, `ExternalGate(P,a) <=> RequiredCheck(P) ^ not Bypass(a,P)`, ficava SATISFEITA
enquanto o portao nao valia para ref nenhuma: faltava o termo de aplicabilidade. Provas
independentes registradas na delegacao: `gh api repos/MrSchrodingers/tollens/rules/branches/main`
retornava `[]`, e o commit `8d76a93` entrou direto na `main` sem PR, 15 minutos depois do ultimo
update do ruleset. Corrigido para `include: ["~DEFAULT_BRANCH"]` antes desta observacao.

`tests/unit/fronteira-externa.sh` e ESTATICO (le os arquivos de workflow) e por construcao NAO
podia ter detectado isso: o YAML dos workflows nunca mudou, so a configuracao do ruleset no
servidor. A propriedade correta:

    Gate(P,a,r) <=> Applies(P,r) ^ Required(P) ^ not Bypass(a,P)

## 1. PASS - o ruleset corrigido, medido contra `main`

```
$ python3 evidence/probes/github-ruleset.py
alvo: MrSchrodingers/tollens@main  contexto exigido: verify-pr
estado: PASS
motivo: Gate(P,a,r) satisfeita para 'main': contexto 'verify-pr' e exigido por regra ativa
aplicavel, strict_required_status_checks_policy=true, bypass_actors=[] em todos os rulesets de
origem ([20385799]).
exit=0
```

Corrobora, via `GET /repos/.../rules/branches/main` (autoritativo) e
`GET /repos/.../rulesets/20385799` (bypass/enforcement), o mesmo estado que a auditoria manual
desta sessao ja tinha lido em `gh api repos/MrSchrodingers/tollens/rulesets/20385799`:
`enforcement: "active"`, `bypass_actors: []`, `current_user_can_bypass: "never"`,
`conditions.ref_name.include: ["~DEFAULT_BRANCH"]`.

## 2. FAIL - Applies(P,r) = False, medido contra uma ref que o ruleset NAO cobre

```
$ python3 evidence/probes/github-ruleset.py --branch nao-existe-nunca-xyz
alvo: MrSchrodingers/tollens@nao-existe-nunca-xyz  contexto exigido: verify-pr
estado: FAIL
motivo: Applies(P,r) = False: nenhuma regra ativa se aplica a ref 'nao-existe-nunca-xyz'.
Resposta vazia do endpoint autoritativo - a mesma forma do defeito medido em 2026-08-10
(conditions.ref_name.include == []).
exit=1
```

**Limite deste controle, declarado sem rodeio**: o endpoint `rules/branches/{branch}` "nao
exige que a branch exista - ele resolve quais regras se aplicariam a uma branch com esse nome"
(comportamento documentado pela API, reproduzido aqui). Este caso mede Applies(P,r) = False
para uma ref que o padrao `~DEFAULT_BRANCH` NAO cobre - a mesma FORMA de resposta vazia do
defeito original, mas nao o defeito original em si, que cobria ZERO refs (inclusive `main`).
Reproduzir o defeito original exigiria reverter `conditions.ref_name.include` para `[]` no
ruleset real, o que esta EXPLICITAMENTE PROIBIDO nesta tarefa ("nao altere o ruleset no
GitHub"). A reproducao EXATA do defeito historico (resposta vazia para TODA ref, `main`
inclusive) fica em `tests/unit/fronteira-viva.sh` (caso V2), com o cliente de API STUBADO -
determinística e sem tocar o ruleset real.

## 3. NOT_VERIFIED - oraculo indisponivel (fail-closed), medido contra um repositorio inexistente

```
$ python3 evidence/probes/github-ruleset.py --owner MrSchrodingers --repo nao-existe-repo-xyz
Estado: NAO VERIFICADO - a lacuna de oraculo (rede/token/API) impede o veredito. Nao declare
PASS nem FAIL por auto-avaliacao.
alvo: MrSchrodingers/nao-existe-repo-xyz@main  contexto exigido: verify-pr
estado: NOT_VERIFIED
motivo: gh api repos/MrSchrodingers/nao-existe-repo-xyz/rules/branches/main falhou: gh: Not
Found (HTTP 404)
exit=2
```

O mesmo caminho de codigo trata qualquer falha de `gh api` (404, 401 sem token/token invalido,
timeout de rede, `gh` ausente do PATH) como NOT_VERIFIED / exit 2 - nunca como PASS por omissao
de sinal. Verificado tambem sem credenciais (`GH_TOKEN` invalido) contra `main`: `HTTP 401`,
mesmo tratamento.

## Limites declarados

- As tres medicoes desta sessao usam UM token (o do operador desta maquina, com `repo` no
  escopo) e UM SHA do estado do ruleset (`updated_at: 2026-08-10T11:06:16.378-03:00`, ainda a
  configuracao vigente na data desta observacao). O probe nao afirma nada sobre o estado do
  ruleset em datas futuras - se ele mudar, a proxima execucao mede o novo estado, e e para isso
  que o probe existe: nao para provar uma vez, mas para poder ser rodado de novo.
- O caso 2 mede a FORMA do defeito (resposta vazia -> FAIL), nao o defeito historico exato
  (que cobria `main`), pela restricao de nao alterar o ruleset real. A reproducao exata vive na
  suite stubada.
- `current_user_can_bypass` no endpoint de ruleset individual reflete o ATOR do token usado
  para medir - aqui, um token com `admin: true` sobre o repositorio, a maior autoridade
  possivel. `bypass_actors: []` e a garantia mais forte quando de fato MEDIDA (vale para
  QUALQUER ator, nao so o medido); `current_user_can_bypass` e checado como reforco redundante,
  nao como substituto. **CORRECAO (ver Adendo abaixo)**: a frase original desta observacao
  afirmava que `bypass_actors: []` "e o que o probe exige para PASS" - isso NAO era verdade no
  commit medido aqui (`e98629d`/`cfcad5b`). O probe entao vigente tratava um campo AUSENTE da
  resposta (o caso de um token sem acesso de escrita ao ruleset) da mesma forma que um campo
  presente e vazio (`detalhe.get("bypass_actors") or []`), e teria saido PASS sem ter medido
  nada. A garantia so passou a ser genuinamente EXIGIDA no commit
  `4a1c04678fae7394cc51f17094fe9f5ec818d481`.
- Nao mede se um administrador poderia DESATIVAR o ruleset (fora do escopo de Applies/
  Required/Bypass sobre a regra ja configurada) - o mesmo limite ja declarado em
  `evidence/observations/2026-08-04-fronteira-externa-e-contrato-no-runtime.md`.

## Adendo - a garantia que a secao "Limites declarados" descrevia mais forte do que era

Achado CRITICO da revisao independente, corrigido no commit `4a1c04678fae7394cc51f17094fe9f5ec818d481`
(depois desta observacao original). A frase acima, tal como escrita em 2026-08-10, dizia que
`bypass_actors: []` "e o que o probe exige para PASS". Isso confundia DUAS coisas: o que este
token de `admin: true` MEDIU naquele momento (bypass_actors, de fato, `[]`), e o que o CODIGO do
probe efetivamente EXIGIA para sair PASS (naquele commit, nao exigia a presenca do campo -
apenas que ele, SE presente, nao fosse verdadeiro). Um GITHUB_TOKEN de Actions com
`contents: read` - o perfil que este arquivo e `evidence/claims/C-018.yaml` recomendam para
execucao AGENDADA - nao tem acesso de escrita ao ruleset, e a API do GitHub so devolve
`bypass_actors` a quem tem ("Get a repository ruleset",
https://docs.github.com/en/rest/repos/rules): "To prevent leaking sensitive information, the
bypass_actors property is only returned if the user making the API request has write access to
the ruleset."

### Reproducao ANTES da correcao, contra um repositorio de terceiro (github/docs)

O token desta sessao tem `repo` no escopo mas NAO administra `github/docs` - a mesma classe de
acesso limitado de um `GITHUB_TOKEN` de Actions. Contra o probe no commit `e98629d` (o codigo
que esta observacao original mediu):

```
$ python3 evidence/probes/github-ruleset.py --owner github --repo docs --branch main --context archives
alvo: github/docs@main  contexto exigido: archives
estado: PASS
motivo: Gate(P,a,r) satisfeita para 'main': contexto 'archives' e exigido por regra ativa
aplicavel, strict_required_status_checks_policy=true, bypass_actors=[] em todos os rulesets de
origem ([19633356]).
exit=0
```

PASS fabricado: o probe afirma `bypass_actors=[]` sobre um campo que a resposta nao continha.
Confirmado diretamente contra a API:

```
$ gh api repos/github/docs/rulesets/19633356 | python3 -c \
  "import json,sys; d=json.load(sys.stdin); print('bypass_actors' in d, 'current_user_can_bypass' in d)"
False True
```

`bypass_actors` ausente; `current_user_can_bypass` presente com valor `"never"`. Este segundo
campo, ao contrario de `bypass_actors`, nao exigiu acesso de escrita nesta medicao. O probe
corrigido trata a ausencia de QUALQUER um dos dois com a mesma doutrina, por defesa em
profundidade, mesmo sem evidencia de que `current_user_can_bypass` tambem dependa de escrita.

CONTROLE, o mesmo repositorio onde o token E admin do ruleset (`MrSchrodingers/tollens`,
ruleset `20385799`): `bypass_actors` presente (`[]`), `current_user_can_bypass` presente
(`"never"`) - o caso que a observacao original mediu, e o unico caso em que a frase corrigida
era, coincidentemente, verdadeira sobre o ESTADO, ainda que falsa sobre o CODIGO.

### Reproducao DEPOIS da correcao (commit `4a1c04678fae7394cc51f17094fe9f5ec818d481`)

```
$ python3 evidence/probes/github-ruleset.py --owner github --repo docs --branch main --context archives
estado: NOT_VERIFIED
motivo: Applies(P,r) e Required(P) valem e nenhuma violacao foi encontrada nos campos medidos,
mas not Bypass(a,P) NAO foi medido por completo - PASS exigiria medir, nao supor: ruleset
19633356: 'bypass_actors' ausente da resposta - not Bypass(a,P) NAO foi medido. A API so devolve
este campo a quem tem acesso de escrita ao ruleset.
exit=2

$ python3 evidence/probes/github-ruleset.py
estado: PASS
motivo: Gate(P,a,r) satisfeita para 'main': contexto 'verify-pr' e exigido por regra ativa
aplicavel, strict_required_status_checks_policy=true, bypass_actors=[] em todos os rulesets de
origem ([20385799]).
exit=0
```

Contra `MrSchrodingers/tollens`, onde o campo E genuinamente medido (token com write no
ruleset), o resultado nao muda: PASS continua PASS, porque agora e uma afirmacao MEDIDA, nao
suposta por omissao.
