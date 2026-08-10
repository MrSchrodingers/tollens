# Observacao - Applies(P,r) medido contra o endpoint autoritativo do GitHub

- Data: 2026-08-10
- Ambiente: Linux, `gh version 2.96.0 (2026-07-02)`; GitHub `MrSchrodingers/evidence-gate`
- Fecha: o quantificador ausente da formula publicada (ver `docs/HANDOFF.md` e a delegacao que
  originou `evidence/probes/github-ruleset.py`)

---

## 0. O defeito que motivou o probe

Ate 2026-08-10 o ruleset `20385799` estava `enforcement: active`, `bypass_actors: []`,
exigindo `verify-pr` com `strict_required_status_checks_policy: true` - e
`conditions.ref_name.include` era `[]`, isto e, a regra se aplicava a ZERO refs. A formula
publicada, `ExternalGate(P,a) <=> RequiredCheck(P) ^ not Bypass(a,P)`, ficava SATISFEITA
enquanto o portao nao valia para ref nenhuma: faltava o termo de aplicabilidade. Provas
independentes registradas na delegacao: `gh api repos/MrSchrodingers/evidence-gate/rules/branches/main`
retornava `[]`, e o commit `8d76a93` entrou direto na `main` sem PR, 15 minutos depois do ultimo
update do ruleset. Corrigido para `include: ["~DEFAULT_BRANCH"]` antes desta observacao.

`tests/unit/fronteira-externa.sh` e ESTATICO (le os arquivos de workflow) e por construcao NAO
podia ter detectado isso: o YAML dos workflows nunca mudou, so a configuracao do ruleset no
servidor. A propriedade correta:

    Gate(P,a,r) <=> Applies(P,r) ^ Required(P) ^ not Bypass(a,P)

## 1. PASS - o ruleset corrigido, medido contra `main`

```
$ python3 evidence/probes/github-ruleset.py
alvo: MrSchrodingers/evidence-gate@main  contexto exigido: verify-pr
estado: PASS
motivo: Gate(P,a,r) satisfeita para 'main': contexto 'verify-pr' e exigido por regra ativa
aplicavel, strict_required_status_checks_policy=true, bypass_actors=[] em todos os rulesets de
origem ([20385799]).
exit=0
```

Corrobora, via `GET /repos/.../rules/branches/main` (autoritativo) e
`GET /repos/.../rulesets/20385799` (bypass/enforcement), o mesmo estado que a auditoria manual
desta sessao ja tinha lido em `gh api repos/MrSchrodingers/evidence-gate/rulesets/20385799`:
`enforcement: "active"`, `bypass_actors: []`, `current_user_can_bypass: "never"`,
`conditions.ref_name.include: ["~DEFAULT_BRANCH"]`.

## 2. FAIL - Applies(P,r) = False, medido contra uma ref que o ruleset NAO cobre

```
$ python3 evidence/probes/github-ruleset.py --branch nao-existe-nunca-xyz
alvo: MrSchrodingers/evidence-gate@nao-existe-nunca-xyz  contexto exigido: verify-pr
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
  possivel. `bypass_actors: []` e a garantia mais forte (vale para QUALQUER ator, nao so o
  medido), e e o que o probe exige para PASS; `current_user_can_bypass` e checado como reforco
  redundante, nao como substituto.
- Nao mede se um administrador poderia DESATIVAR o ruleset (fora do escopo de Applies/
  Required/Bypass sobre a regra ja configurada) - o mesmo limite ja declarado em
  `evidence/observations/2026-08-04-fronteira-externa-e-contrato-no-runtime.md`.
