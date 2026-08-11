#!/usr/bin/env bash
# FRONTEIRA VIVA - Applies(P,r) medido no SERVIDOR, nao inferido do YAML.
#
# POR QUE ESTA SUITE EXISTE - defeito MEDIDO, nao inferido (2026-08-10).
#
# `tests/unit/fronteira-externa.sh` e ESTATICO: le os arquivos de workflow deste repositorio.
# O defeito que esta suite protege era, por definicao, INVISIVEL a essa leitura - o YAML dos
# workflows nunca mudou. O que mudou foi a configuracao do ruleset no GitHub:
#
#   enforcement: active, bypass_actors: [], exigindo `verify-pr` com
#   strict_required_status_checks_policy: true - e conditions.ref_name.include era `[]`.
#
# A formula publicada, ExternalGate(P,a) <=> RequiredCheck(P) ^ not Bypass(a,P), ficava
# SATISFEITA enquanto o portao nao valia para ref nenhuma: faltava o termo de aplicabilidade.
# A propriedade correta e Gate(P,a,r) <=> Applies(P,r) ^ Required(P) ^ not Bypass(a,P), e
# `evidence/probes/github-ruleset.py` mede Applies(P,r) contra o endpoint AUTORITATIVO
# (`GET /repos/{owner}/{repo}/rules/branches/{branch}` - o proprio GitHub resolvendo quais
# regras ativas se aplicam aquela ref).
#
# O QUE ESTA SUITE VERIFICA, E O QUE NAO VERIFICA
# ------------------------------------------------
# VERIFICA os caminhos do probe, com o cliente de API (o binario `gh`) SUBSTITUIDO por um
# stub deterministico mais cedo no PATH - a mesma tecnica de tests/unit/regressao-gate.sh (casos
# G6/G9) para simular ferramentas ausentes ou com resposta controlada. NENHUMA rede real e usada.
#   V1 - regras aplicaveis e o contexto exigido esta entre elas, sem bypass -> PASS, exit 0.
#   V2 - resposta VAZIA do endpoint autoritativo (o defeito real: nenhuma regra ativa se aplica)
#        -> FAIL, exit 1. Sem este caso a suite nao discrimina nada: um probe que sempre
#        retornasse PASS passaria em V1 e V3 igualmente.
#   V3 - API indisponivel (gh falha, ou gh ausente do PATH) -> NOT_VERIFIED, exit 2. Nunca PASS
#        por omissao de sinal - mesma doutrina de evidence/hooks/verify-gate.sh.
#   V4 - `bypass_actors` AUSENTE da resposta de rulesets/{id} -> NOT_VERIFIED, exit 2. Achado
#        CRITICO da revisao independente de 2026-08-10: a API so devolve este campo a quem tem
#        acesso de escrita ao ruleset (docs.github.com/en/rest/repos/rules); um GITHUB_TOKEN de
#        Actions com `contents: read` (a execucao AGENDADA que C-018 recomenda) nao tem essa
#        permissao. `detalhe.get("bypass_actors") or []` colapsava "ausente" em "medido: vazio"
#        e emitia PASS fabricado - o mesmo defeito que este probe existe para corrigir, agora
#        sobre o proprio termo not Bypass(a,P).
#   V5 - `bypass_actors` NAO vazio (ha ator que pode burlar a regra) -> FAIL, exit 1.
#   V6 - `current_user_can_bypass` AUSENTE da resposta -> NOT_VERIFIED, exit 2. Mesma doutrina de
#        V4, aplicada ao segundo campo que a correcao endereca.
#   V7 - `strict_required_status_checks_policy: false` numa regra aplicavel -> FAIL, exit 1: a
#        branch pode ficar desatualizada e ainda assim mergear.
#   V8 - contexto exigido fora do conjunto produzido pelas regras aplicaveis -> FAIL, exit 1
#        (Required(P) = False), e o probe NAO chama o endpoint de ruleset: sem contexto
#        satisfeito nao ha bypass a resolver.
#   V9 - resposta de rulesets/{id} que NAO e um objeto (oraculo malformado) -> NOT_VERIFIED,
#        exit 2. Antes da correcao, `detalhe.get(...)` sobre uma lista/string estourava
#        AttributeError e o processo saia com o traceback do Python - exit 1 (FAIL), nunca a
#        lacuna de oraculo que de fato houve.
#
# V10-V15 fecham um SEGUNDO achado CRITICO (2026-08-11): a correcao de V4/V9 tratou a CHAVE
# ausente e o OBJETO malformado, mas deixou a CLASSE aberta - VALOR nulo, TIPO errado, e a
# precedencia declarada (FAIL vence NOT_VERIFIED) nao implementada onde a medicao acontece em
# laco.
#   V10 - `bypass_actors` presente e `null` -> NOT_VERIFIED, exit 2. `atores = valor or []`
#        colapsava um valor nulo EXPLICITO na mesma forma de "medido: []" que V4 ja fechou para
#        a chave ausente - a INSTANCIA foi corrigida, o VALOR nulo continuava aberto.
#   V11 - `bypass_actors` de tipo que nao e lista (ex.: string) -> NOT_VERIFIED, exit 2, sem
#        traceback. Sem o guard de tipo, `**a` sobre os caracteres da string produzia TypeError
#        nao tratado - exit 1 por acidente do interprete, a mesma classe de falha que V9 ja
#        fechou para o OBJETO `detalhe`, agora sobre o CAMPO `bypass_actors` dele.
#   V12 - dois rulesets aplicaveis: um com `bypass_actors` NAO vazio (FAIL ja provado) e outro
#        que FALHA ao ser lido (rede/permissao) -> FAIL, exit 1. Antes da correcao, o
#        `return NOT_VERIFIED` dentro do laco descartava o FAIL ja acumulado assim que o
#        segundo ruleset falhava - a lacuna de medicao MASCARAVA a violacao provada.
#   V13 - mesma forma de V12, mas o segundo ruleset devolve algo que NAO e um objeto (em vez de
#        falhar por rede) -> FAIL, exit 1. O SEGUNDO ponto do laco que retornava cedo.
#   V14 - um UNICO ruleset aplicavel, `strict_required_status_checks_policy: false` (FAIL ja
#        medido ANTES do laco de bypass) e esse MESMO ruleset FALHA ao ser lido -> FAIL, exit 1.
#        `strict_flags` e medido fora do laco de bypass; a falha para RESOLVER bypass nao pode
#        apagar uma violacao ja medida em outro termo.
#   V15 - `strict_required_status_checks_policy: false` (medido, reprova) e `bypass_actors`
#        AUSENTE (nao medido) no MESMO ruleset -> FAIL, exit 1. Prova que a precedencia
#        declarada e ALCANCAVEL sem nenhum `return` cedo envolvido - e por isso precisa de
#        mutante proprio (MV7): sem ele, trocar a ORDEM dos dois `if` finais (nao_medidos antes
#        de problemas) sobrevive em silencio.
#
# V21-V31 fecham a QUINTA onda (2026-08-11, ver o docstring de evidence/probes/github-ruleset.py,
# secao "O SEXTO CAMPO, ANTES DO SCHEMA"): V21/V22 isolam `enforcement`/`current_user_can_bypass`
# PRESENTES mas invalidos (nao a ausencia, ja coberta por V19/V6) - garantias que o codigo ja
# implementava mas nenhum caso exercitava; V23-V25 isolam `strict_required_status_checks_policy`
# ausente/nulo/tipo-errado (so a variante `false` EXPLICITA tinha caso ate aqui); V26 isola o
# `context` ausente de um item de `required_status_checks`; V27-V29 isolam `type` ausente/nulo/
# elemento-nao-objeto no proprio `rules/branches/{branch}` - o filtro que decide quem chega a ser
# lido como `required_status_checks`, ANTES de qualquer schema; V30 reproduz o `TypeError` que a
# linha seguinte desse filtro estourava; V31 prova que o caminho FAIL legitimo (sem ambiguidade)
# sobrevive a refatoracao.
#
# V32-V33 fecham a SEXTA onda (2026-08-11): um `return` DENTRO da propria funcao `probe`, mas
# ANTES da agregacao de `strict_medidos` em `problemas`, descartava uma violacao de
# `strict_required_status_checks_policy` JA MEDIDA - a mesma classe de defeito que V12-V15
# fecharam para o laco de rulesets, agora um passo mais cedo, ANTES desse laco sequer comecar.
#   V32 - 'ruleset_id' AUSENTE da UNICA regra aplicavel + strict=false NA MESMA regra -> FAIL,
#        exit 1. Reproduzido nesta sessao: `estado: NOT_VERIFIED exit=2` antes da correcao, com
#        `strict_required_status_checks_policy` ja lido e medido como `false` na mesma regra cujo
#        `ruleset_id` ausente disparava o `return NOT_VERIFIED` antigo.
#   V33 - MESMA violacao de strict, mas descartada pelo OUTRO `return` precoce: Required(P) fica
#        indeterminado porque uma SEGUNDA regra aplicavel e ilegivel (`parameters` malformado) e
#        poderia ter exigido o contexto - antes da correcao isso saia NOT_VERIFIED mesmo com o
#        strict da primeira regra ja provando a violacao. As duas hipoteses sobre a regra ilegivel
#        (exigia o contexto ou nao) levam ao mesmo FAIL, entao NOT_VERIFIED descreveria uma
#        incerteza que nao existe.
#   V34 - NAO-REGRESSAO do fix de V32: MESMA forma ('ruleset_id' ausente da unica regra
#        aplicavel), mas SEM violacao alguma medida (strict=true) -> continua NOT_VERIFIED. Prova
#        que o novo guard `if problemas` do bloco `if not ruleset_ids:` gateia de fato no valor de
#        `problemas`, em vez de inverter o defeito para o lado oposto (FAIL fabricado sem nenhuma
#        violacao medida) - achado durante esta mesma sessao ao validar por mutacao: um mutante
#        que forca esse bloco a retornar FAIL incondicionalmente sobrevivia aos 127 casos V1-V33.
#
# NAO VERIFICA o servidor real do GitHub a cada execucao (isso e o proprio probe, exercitado
# manualmente contra o repositorio e registrado na evidencia da claim). Esta suite mede o
# COMPORTAMENTO DE DECISAO do probe diante de cada forma de resposta - nao a configuracao atual
# do ruleset, que pode mudar sem que este arquivo mude.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
PROBE="$PWD/evidence/probes/github-ruleset.py"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

command -v python3 >/dev/null 2>&1 || { echo "NAO VERIFICADO: python3 ausente - o probe nao pode ser exercitado." >&2; exit 2; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- O STUB DO CLIENTE DE API ---
# Roteia pela FORMA do endpoint pedido (rules/branches/* vs rulesets/*), nao pelo CONTEUDO -
# um stub que decidisse pelo conteudo estaria testando o proprio stub, nao o probe. O
# comportamento por caminho vem de STUB_MODE, lido do ambiente pelo stub em tempo de execucao.
FAKEBIN="$T/bin"; mkdir -p "$FAKEBIN"
cat > "$FAKEBIN/gh" <<'STUB'
#!/usr/bin/env bash
[ "${1:-}" = "api" ] || { echo "fake-gh: comando nao suportado: $*" >&2; exit 127; }
REQ="$2"
if [ "${STUB_MODE:-}" = "down" ]; then
  echo '{"message":"Bad credentials","documentation_url":"https://docs.github.com/rest","status":"401"}'
  echo "gh: Bad credentials (HTTP 401)" >&2
  exit 1
fi
case "$REQ" in
  */rules/branches/*)
    case "${STUB_MODE:-}" in
      empty) echo '[]' ;;
      # As variantes abaixo so divergem no que rulesets/{id} devolve: a resposta de
      # rules/branches e a mesma "regra aplicavel, contexto verify-pr presente" de `pass`.
      pass|bypass-ausente|bypass-nao-vazio|cucb-ausente|resposta-nao-dict|bypass-null|bypass-tipo-errado|enforcement-nao-active|cucb-nao-never)
        cat <<'JSON'
[
  {"type":"deletion","ruleset_source_type":"Repository","ruleset_source":"stub/repo","ruleset_id":999},
  {"type":"non_fast_forward","ruleset_source_type":"Repository","ruleset_source":"stub/repo","ruleset_id":999},
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      strict-false|strict-false-inacessivel|strict-false-bypass-ausente)
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":false,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      strict-false-ruleset-id-ausente)
        # (wave6, V32) o DEFEITO REPRODUZIDO: a UNICA regra aplicavel nao declara 'ruleset_id',
        # mas 'strict_required_status_checks_policy' JA foi lido e medido como 'false' NA MESMA
        # regra - o `ruleset_id` ausente e o `strict` medido convivem no MESMO objeto. Antes da
        # correcao, `if not ruleset_ids: return NOT_VERIFIED` rodava ANTES da agregacao de
        # `strict_medidos` em `problemas` e descartava a violacao ja provada.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "parameters":{"strict_required_status_checks_policy":false,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      strict-false-required-indeterminado)
        # (wave6, V33) MESMA violacao de strict, descartada pelo OUTRO `return` precoce: a
        # primeira regra (ruleset 501) tem strict=false JA MEDIDO mas exige 'outro-check', nao o
        # contexto pedido; a segunda regra (ruleset 502) e ILEGIVEL ('parameters' e uma string) e
        # PODERIA ter exigido o contexto pedido - Required(P) fica indeterminado. Antes da
        # correcao, `if context not in contextos: if nao_medidos: return NOT_VERIFIED` rodava
        # ANTES da agregacao de `strict_medidos`, descartando a violacao da primeira regra.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":501,"parameters":{"strict_required_status_checks_policy":false,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"outro-check","integration_id":15368}]}},
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo2",
   "ruleset_id":502,"parameters":"nao-e-um-objeto"}
]
JSON
        ;;
      ruleset-id-ausente-sem-violacao)
        # (wave6, V34) NAO-REGRESSAO: mesma forma de strict-false-ruleset-id-ausente (V32), mas
        # SEM nenhuma violacao medida (strict=true) - prova que o guard `if problemas` do bloco
        # `if not ruleset_ids:` REALMENTE gateia no valor de `problemas`, e nao apenas inverteu o
        # `return` antigo para sempre-FAIL. Sem este caso, um mutante que forca esse bloco a
        # retornar FAIL incondicionalmente (ignorando `problemas` vazio) sobrevive: mudo aqui
        # mesmo, a mensagem de saida seria APENAS a `motivo` mudando, sem NENHUM caso reprovar.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      duplo-inacessivel|duplo-nao-dict)
        # DOIS rulesets aplicaveis (501, 502): o segundo diverge por STUB_MODE em
        # */rulesets/502 abaixo - falha de rede (duplo-inacessivel) ou resposta nao-objeto
        # (duplo-nao-dict). O primeiro (501) sempre tem bypass_actors JA provado.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":501,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}},
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":502,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      contexto-fora)
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"outro-check","integration_id":15368}]}}
]
JSON
        ;;
      c1-parcial)
        # (C1): DUAS regras required_status_checks aplicaveis. A segunda NAO declara
        # 'ruleset_id' - o defeito exato que fazia a regra desaparecer do conjunto sem deixar
        # rastro em nao_medidos, e o portao emitir PASS com a afirmacao UNIVERSAL "bypass_actors
        # =[] em todos os rulesets de origem" sem ter resolvido bypass desta segunda regra.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":501,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}},
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo2",
   "parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15369}]}}
]
JSON
        ;;
      c2-elemento)
        # (C2): UMA regra aplicavel, ruleset_id valido - o defeito esta no ELEMENTO de
        # bypass_actors (ver */rulesets/* abaixo), nao nesta resposta.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      a1-parametros)
        # (A1): 'parameters' e uma STRING, nao um objeto. `r.get("parameters") or {}` deixava
        # passar qualquer coisa truthy, e o primeiro `.get()` seguinte estourava AttributeError.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":"nao-e-um-objeto"}
]
JSON
        ;;
      a2-coercao)
        # (A2): regra aplicavel legivel (contexto presente, strict medido) - o defeito esta na
        # resposta de rulesets/999 (ver abaixo), que omite 'enforcement' E 'bypass_actors'.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      schema-item-invalido)
        # 5o caso (forma inesperada que o SCHEMA recusa, distinto dos quatro acima): o item de
        # 'required_status_checks' dentro de 'parameters' nao e um objeto - um inteiro no lugar
        # de {"context": ...}. Prova que o mesmo mecanismo de schema (valida_campo com
        # tipo_item) cobre um QUARTO campo aninhado sem precisar de um guard escrito a mao.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[42]}}
]
JSON
        ;;
      strict-ausente)
        # (D3, wave5) 'strict_required_status_checks_policy' AUSENTE de 'parameters' - nao a
        # variante explicita 'strict:false' que V7/V14/V15 ja cobrem, e sim a chave que nunca
        # veio. O codigo ja tratava isto corretamente (valida_campo), mas nenhum caso isolava
        # esta forma - garantia sem teste, nao limitacao.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      strict-nulo)
        # (D3, wave5) valor NULL explicito - nao e chave ausente, mesma doutrina.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":null,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      strict-tipo-errado)
        # (D3, wave5) tipo que nao e booleano (string "true").
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":"true",
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}}
]
JSON
        ;;
      context-ausente-no-check)
        # (D5, wave5) o item de 'required_status_checks' e um objeto valido (o SCHEMA da lista ja
        # aceita), mas o proprio item nao tem a chave 'context'. `chk.get("context")` tratava
        # isto como "este item nao contribui contexto" - Required(P) = False FABRICADO, nao
        # medido (fail-closed na direcao, mas a mesma violacao doutrinaria de A2/C1).
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":999,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"integration_id":15368}]}}
]
JSON
        ;;
      tipo-ausente-com-regra-valida)
        # (D1, wave5, O QUINTO DEGRAU) DUAS regras aplicaveis: a primeira (ruleset 501) e uma
        # required_status_checks legivel e limpa; a segunda (ruleset 998) TEM a mesma forma mas
        # NAO declara 'type' - o filtro original a descartava em silencio, seu ruleset_id nunca
        # entrava em ruleset_ids, e o ruleset 998 (que na reproducao real tem bypass_actors nao
        # vazio) nunca era consultado. Aqui basta provar que o probe NUNCA emite PASS enquanto
        # esta regra permanecer ilegivel - nao precisa da parte "suja" do ruleset 998 para isso.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":501,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}},
  {"ruleset_source_type":"Repository","ruleset_source":"stub/repo2",
   "ruleset_id":998,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"outro-check","integration_id":99}]}}
]
JSON
        ;;
      tipo-nulo-com-regra-valida)
        # (D1, wave5) mesma forma de tipo-ausente-com-regra-valida, mas 'type' esta presente e
        # e null - nao e a mesma coisa que a chave ausente, mesma doutrina.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":501,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}},
  {"type":null,"ruleset_source_type":"Repository","ruleset_source":"stub/repo2",
   "ruleset_id":998,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"outro-check","integration_id":99}]}}
]
JSON
        ;;
      elemento-nao-dict-com-regra-valida)
        # (D1, wave5) o SEGUNDO elemento da lista de rules/branches nao e sequer um objeto - um
        # oraculo malformado no NIVEL do proprio elemento, nao so de um campo dele.
        cat <<'JSON'
[
  {"type":"required_status_checks","ruleset_source_type":"Repository","ruleset_source":"stub/repo",
   "ruleset_id":501,"parameters":{"strict_required_status_checks_policy":true,
   "do_not_enforce_on_create":false,
   "required_status_checks":[{"context":"verify-pr","integration_id":15368}]}},
  "elemento-nao-objeto"
]
JSON
        ;;
      rsc-vazio-tipo-misto)
        # (D2, wave5) NENHUMA regra e required_status_checks, e uma delas nao declara 'type' -
        # `tipos = sorted({r.get("type") for r in rules if isinstance(r, dict)})` estourava
        # TypeError ('<' not supported between instances of 'str' and 'NoneType') com {None,
        # "deletion"} - traceback nao tratado, exit 1 por acidente do interprete, nunca a lacuna
        # de oraculo que de fato existe (o segundo elemento pode ou nao ser required_status_checks
        # - nao ha como saber).
        cat <<'JSON'
[
  {"type":"deletion","ruleset_source_type":"Repository","ruleset_source":"stub/repo","ruleset_id":999},
  {"ruleset_source_type":"Repository","ruleset_source":"stub/repo2","ruleset_id":998}
]
JSON
        ;;
      rsc-vazio-tipos-conhecidos)
        # SEM ambiguidade: as duas regras tem 'type' legivel, nenhuma e required_status_checks -
        # Required(P) = False e uma conclusao MEDIDA aqui, nao suposta. Prova que a refatoracao
        # do filtro (acima) preserva o caminho FAIL legitimo, nao so o caminho NOT_VERIFIED novo.
        cat <<'JSON'
[
  {"type":"deletion","ruleset_source_type":"Repository","ruleset_source":"stub/repo","ruleset_id":999},
  {"type":"non_fast_forward","ruleset_source_type":"Repository","ruleset_source":"stub/repo","ruleset_id":999}
]
JSON
        ;;
      *) echo "fake-gh: STUB_MODE nao reconhecido: ${STUB_MODE:-<vazio>}" >&2; exit 1 ;;
    esac
    ;;
  */rulesets/*)
    # marcador: prova QUAL caminho realmente chamou este endpoint. `contexto-fora` NAO deveria -
    # sem contexto satisfeito, Required(P) ja e falso e nao ha bypass a resolver.
    : > "${STUB_MARKER:-/dev/null}"
    case "${STUB_MODE:-}" in
      bypass-ausente)
        # Achado CRITICO: a API so devolve `bypass_actors` a quem tem write no ruleset. Um
        # GITHUB_TOKEN de Actions com `contents: read` recebe a resposta sem essa chave.
        echo '{"id":999,"enforcement":"active","current_user_can_bypass":"never"}' ;;
      bypass-nao-vazio)
        echo '{"id":999,"enforcement":"active","current_user_can_bypass":"never",
               "bypass_actors":[{"actor_type":"Team","actor_id":42,"bypass_mode":"always"}]}' ;;
      cucb-ausente)
        echo '{"id":999,"enforcement":"active","bypass_actors":[]}' ;;
      enforcement-nao-active)
        # (D4a, wave5) 'enforcement' PRESENTE e MEDIDO, mas != 'active' - nao a ausencia (ja
        # coberta por A2/V19), e sim o valor que a defesa em profundidade do `elif enforcement !=
        # "active":` existe para pegar.
        echo '{"id":999,"enforcement":"evaluate","current_user_can_bypass":"never","bypass_actors":[]}' ;;
      cucb-nao-never)
        # (D4b, wave5) 'current_user_can_bypass' PRESENTE e MEDIDO, mas != 'never'.
        echo '{"id":999,"enforcement":"active","current_user_can_bypass":"always","bypass_actors":[]}' ;;
      resposta-nao-dict)
        # rulesets/{id} devolvendo um ESCALAR em vez de um objeto - oraculo malformado. Um
        # escalar (nao uma lista/string) e o caso que realmente PROVA a necessidade do guard:
        # `valida_campo` usa `nome not in objeto`, que nao estoura para lista/string (apenas
        # testa pertencimento/substring, sem crashar) - so um valor NAO ITERAVEL (int, bool,
        # null) reproduz o AttributeError/TypeError que o guard existe para evitar.
        echo '42' ;;
      bypass-null)
        # V10: valor NULL explicito - nao e chave ausente, e nao e "medido: []".
        echo '{"id":999,"enforcement":"active","current_user_can_bypass":"never","bypass_actors":null}' ;;
      bypass-tipo-errado)
        # V11: tipo que nao e lista - sem guard, `**a` sobre os caracteres da string produzia
        # TypeError nao tratado.
        echo '{"id":999,"enforcement":"active","current_user_can_bypass":"never","bypass_actors":"Team:42"}' ;;
      strict-false-inacessivel)
        # V14: o UNICO ruleset aplicavel FALHA ao ser lido; strict=false ja e FAIL provado ANTES
        # deste laco (rules/branches acima, modo strict-false-inacessivel).
        echo '{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest","status":"403"}'
        echo "gh: Resource not accessible by integration (HTTP 403)" >&2
        exit 1 ;;
      strict-false-bypass-ausente)
        # V15: strict=false (medido, reprova) + bypass_actors AUSENTE (nao medido) no MESMO
        # ruleset - a precedencia declarada e ALCANCAVEL sem nenhum `return` cedo envolvido.
        echo '{"id":999,"enforcement":"active","current_user_can_bypass":"never"}' ;;
      duplo-inacessivel)
        # V12: 501 com bypass_actors JA provado; 502 FALHA ao ser lido (rede/permissao).
        case "$REQ" in
          */rulesets/501)
            echo '{"id":501,"enforcement":"active","current_user_can_bypass":"never",
                   "bypass_actors":[{"actor_type":"Team","actor_id":42,"bypass_mode":"always"}]}' ;;
          */rulesets/502)
            echo '{"message":"Resource not accessible by integration","documentation_url":"https://docs.github.com/rest","status":"403"}'
            echo "gh: Resource not accessible by integration (HTTP 403)" >&2
            exit 1 ;;
          *) echo "fake-gh: ruleset nao stubado para duplo-inacessivel: $REQ" >&2; exit 1 ;;
        esac ;;
      duplo-nao-dict)
        # V13: mesma forma de duplo-inacessivel, mas o segundo ruleset devolve algo que NAO e
        # um objeto - o SEGUNDO ponto do laco que retornava cedo, nao o de rede.
        case "$REQ" in
          */rulesets/501)
            echo '{"id":501,"enforcement":"active","current_user_can_bypass":"never",
                   "bypass_actors":[{"actor_type":"Team","actor_id":42,"bypass_mode":"always"}]}' ;;
          */rulesets/502)
            echo '[]' ;;
          *) echo "fake-gh: ruleset nao stubado para duplo-nao-dict: $REQ" >&2; exit 1 ;;
        esac ;;
      c1-parcial)
        # (C1): so o ruleset 501 entra em ruleset_ids (a regra sem 'ruleset_id' nunca chega a
        # pedir rulesets/{id} nenhum) - este ruleset, sozinho, esta limpo. Se o probe ainda
        # emitisse PASS aqui, seria exatamente o PASS fabricado que C1 descreve: a segunda
        # regra nunca foi medida.
        echo '{"id":501,"enforcement":"active","current_user_can_bypass":"never","bypass_actors":[]}' ;;
      c2-elemento)
        # (C2): bypass_actors e uma LISTA (o container tem o tipo certo), mas o elemento e uma
        # string - nao mapeavel para `{"ruleset_id": rid, **a}`.
        echo '{"id":999,"enforcement":"active","current_user_can_bypass":"never","bypass_actors":["OrganizationAdmin"]}' ;;
      a2-coercao)
        # (A2): 'enforcement' E 'bypass_actors' ausentes da resposta - a forma exata que a onda 3
        # coagia em violacao fabricada ("enforcement='None'") em vez de registrar como nao
        # medida.
        echo '{"id":999,"current_user_can_bypass":"never"}' ;;
      *)
        echo '{"id":999,"enforcement":"active","bypass_actors":[],"current_user_can_bypass":"never"}' ;;
    esac
    ;;
  *) echo "fake-gh: path nao stubado: $REQ" >&2; exit 1 ;;
esac
STUB
chmod +x "$FAKEBIN/gh"

rodar(){  # $1=STUB_MODE  $2=arquivo de marcador (rulesets chamado?)  stdout/stderr em $T/out $T/err
  STUB_MARKER="$2" STUB_MODE="$1" PATH="$FAKEBIN:$PATH" \
    python3 "$PROBE" --owner stub --repo repo --branch main --context verify-pr \
    >"$T/out" 2>"$T/err"
  echo $?
}

echo "== V1. regras aplicaveis e contexto presente, sem bypass -> PASS =="
MRK="$T/chamou-ruleset-v1"; rm -f "$MRK"
RC="$(rodar pass "$MRK")"
chk "exit code 0" "$RC" 0
chk "relata estado PASS" "$(grep -q '^estado: PASS$' "$T/out" && echo sim || echo nao)" "sim"
chk "  cita a formula satisfeita" "$(grep -q 'Gate(P,a,r) satisfeita' "$T/out" && echo sim || echo nao)" "sim"
chk "  resolveu bypass/strict via o endpoint de ruleset (nao so rules/branches)" \
    "$([ -f "$MRK" ] && echo sim || echo nao)" "sim"

echo "== V2. resposta VAZIA do endpoint autoritativo -> FAIL (o discriminador) =="
# Sem este caso a suite nao mede nada: um probe que sempre retornasse PASS passaria em V1 e V3
# igualmente, e so a forma "vazio -> deve reprovar" prova que o probe le a resposta de verdade.
MRK="$T/chamou-ruleset-v2"; rm -f "$MRK"
RC="$(rodar empty "$MRK")"
chk "exit code 1" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo e Applies(P,r) = False" "$(grep -q 'Applies(P,r) = False' "$T/out" && echo sim || echo nao)" "sim"
# ANTIVACUIDADE OPERACIONAL: sem regra aplicavel, o probe nem tenta resolver bypass_actors -
# se ele chamasse mesmo assim, o marcador provaria que o short-circuit nao existe.
chk "  NAO chama o endpoint de ruleset (nada aplicavel = nada a resolver)" \
    "$([ -f "$MRK" ] && echo chamou || echo nao-chamou)" "nao-chamou"

echo "== V3. API indisponivel -> NOT_VERIFIED, exit 2 (fail-closed, nunca PASS por omissao) =="
MRK="$T/chamou-ruleset-v3"; rm -f "$MRK"
RC="$(rodar down "$MRK")"
chk "exit code 2" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  stderr declara NAO VERIFICADO (canal que o operador le)" \
    "$(grep -q 'NAO VERIFICADO' "$T/err" && echo sim || echo nao)" "sim"
chk "  nao produz PASS nem FAIL por omissao de sinal" \
    "$(grep -qE '^estado: (PASS|FAIL)$' "$T/out" && echo vazou || echo contido)" "contido"
# Segunda forma da MESMA doutrina: 'gh' nem instalado (nao so gh falhando). PATH SEM NENHUM
# diretorio (nem sequer um substituto de gh) - basta que 'gh' nao resolva. O interprete e
# invocado pelo CAMINHO ABSOLUTO (sys.executable): um PATH vazio nao impede o exec de um
# binario ja localizado, so a busca por comandos NAO qualificados como 'gh' dentro do probe.
PYBIN="$(python3 -c 'import sys; print(sys.executable)')"
NOBIN="$T/bin-sem-gh"; mkdir -p "$NOBIN"   # existe e esta vazio: PATH valido, sem 'gh' nele
RC2=$(PATH="$NOBIN" "$PYBIN" "$PROBE" --owner stub --repo repo --branch main --context verify-pr \
      >"$T/out2" 2>"$T/err2"; echo $?)
chk "  'gh' ausente do PATH tambem e NOT_VERIFIED (mesma doutrina, outra causa)" "$RC2" 2
chk "  e nomeia a dependencia ausente" "$(grep -q "'gh'" "$T/out2" && echo sim || echo nao)" "sim"

echo "== V4. 'bypass_actors' AUSENTE da resposta do ruleset -> NOT_VERIFIED (achado CRITICO) =="
# O defeito que esta rodada de correcao existe para fechar: antes, 'or []' sobre um campo NAO
# DEVOLVIDO (por falta de acesso de escrita ao ruleset - o caso de um GITHUB_TOKEN de Actions com
# `contents: read`) virava "medido: []" e o probe saia PASS. Reproduzido contra o servidor real
# em github/docs (ver evidence/observations); aqui a mesma forma, stubada e deterministica.
MRK="$T/chamou-ruleset-v4"; rm -f "$MRK"
RC="$(rodar bypass-ausente "$MRK")"
chk "exit code 2 (nao mais 0 - o PASS fabricado)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
# ROTULO UNICO na suite inteira (wave5): antes desta correcao, este texto tambem aparecia em
# V19 (a2-coercao) - o arnes de mutacao credita kill por ROTULO, e um rotulo repetido entre
# casos permite que um mutante seja "morto" pelo caso ERRADO sem que ninguem perceba.
chk "  motivo cita 'bypass_actors' ausente (ruleset unico)" "$(grep -q "'bypass_actors' ausente" "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO afirma 'bypass_actors=[]' sem ter medido" \
    "$(grep -q 'bypass_actors=\[\]' "$T/out" && echo afirmou || echo nao-afirmou)" "nao-afirmou"

echo "== V5. 'bypass_actors' NAO vazio -> FAIL (ha ator que pode burlar a regra) =="
MRK="$T/chamou-ruleset-v5"; rm -f "$MRK"
RC="$(rodar bypass-nao-vazio "$MRK")"
chk "exit code 1" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
# ROTULO UNICO (wave5): o mesmo texto tambem aparecia em V12 e V13 - ver a nota em V4/V19.
chk "  motivo cita 'bypass_actors nao vazio' (ruleset unico)" \
    "$(grep -q 'bypass_actors nao vazio' "$T/out" && echo sim || echo nao)" "sim"

echo "== V6. 'current_user_can_bypass' AUSENTE da resposta -> NOT_VERIFIED (mesma doutrina) =="
MRK="$T/chamou-ruleset-v6"; rm -f "$MRK"
RC="$(rodar cucb-ausente "$MRK")"
chk "exit code 2" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'current_user_can_bypass' ausente" \
    "$(grep -q "'current_user_can_bypass' ausente" "$T/out" && echo sim || echo nao)" "sim"

echo "== V7. strict_required_status_checks_policy: false -> FAIL (pode mergear desatualizado) =="
MRK="$T/chamou-ruleset-v7"; rm -f "$MRK"
RC="$(rodar strict-false "$MRK")"
chk "exit code 1" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita strict_required_status_checks_policy" \
    "$(grep -q 'strict_required_status_checks_policy' "$T/out" && echo sim || echo nao)" "sim"

echo "== V8. contexto exigido FORA do conjunto produzido -> FAIL, sem chamar rulesets/{id} =="
MRK="$T/chamou-ruleset-v8"; rm -f "$MRK"
RC="$(rodar contexto-fora "$MRK")"
chk "exit code 1" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo e Required(P) = False" "$(grep -q 'Required(P) = False' "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO chama o endpoint de ruleset (contexto ja reprova Required(P))" \
    "$([ -f "$MRK" ] && echo chamou || echo nao-chamou)" "nao-chamou"

echo "== V9. resposta de rulesets/{id} que NAO e um objeto -> NOT_VERIFIED (oraculo malformado) =="
# Antes da correcao, 'detalhe.get(...)' sobre uma lista estourava AttributeError: o processo
# saia com traceback nao tratado - exit 1 por acidente do interprete, nunca a lacuna de oraculo
# que de fato ocorreu.
MRK="$T/chamou-ruleset-v9"; rm -f "$MRK"
RC="$(rodar resposta-nao-dict "$MRK")"
chk "exit code 2 (nao 1 por AttributeError nao tratado)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
# ROTULO UNICO (wave5): MV3 mata especificamente AQUI - o mesmo texto tambem aparecia em
# V11/V17/V18, o que permitia um mutante ser creditado ao caso errado.
chk "  nao ha traceback do Python em stderr (resposta-nao-dict)" \
    "$(grep -q 'Traceback (most recent call last)' "$T/err" && echo vazou || echo contido)" "contido"

echo "== V10. 'bypass_actors' e NULL na resposta -> NOT_VERIFIED (valor nulo != chave ausente) =="
# SEGUNDO achado CRITICO (2026-08-11): a onda anterior fechou a CHAVE ausente (V4) e deixou a
# CLASSE aberta - um valor `null` EXPLICITO ainda colapsava em "medido: []" pela mesma linha
# `or []`, e o probe saia PASS fabricado.
MRK="$T/chamou-ruleset-v10"; rm -f "$MRK"
RC="$(rodar bypass-null "$MRK")"
chk "exit code 2 (nao mais 0 - o PASS fabricado sobre valor nulo)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'bypass_actors' e null" "$(grep -q "'bypass_actors' e null" "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO afirma 'bypass_actors=[]' sem ter medido" \
    "$(grep -q 'bypass_actors=\[\]' "$T/out" && echo afirmou || echo nao-afirmou)" "nao-afirmou"

echo "== V11. 'bypass_actors' tem tipo inesperado (string) -> NOT_VERIFIED, nunca traceback =="
# Sem o guard de tipo, '**a' sobre os caracteres da string produzia TypeError NAO tratado - a
# mesma classe de falha que V9 ja fechou para o OBJETO 'detalhe', agora sobre este CAMPO dele.
MRK="$T/chamou-ruleset-v11"; rm -f "$MRK"
RC="$(rodar bypass-tipo-errado "$MRK")"
chk "exit code 2 (nao 1 por TypeError nao tratado)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'bypass_actors' tipo inesperado" \
    "$(grep -q "'bypass_actors' tem tipo inesperado" "$T/out" && echo sim || echo nao)" "sim"
chk "  nao ha traceback do Python em stderr (bypass-tipo-errado)" \
    "$(grep -q 'Traceback (most recent call last)' "$T/err" && echo vazou || echo contido)" "contido"

echo "== V12. violacao PROVADA num ruleset + outro ruleset ILEGIVEL (rede) -> FAIL, nunca NOT_VERIFIED =="
# TERCEIRO achado CRITICO (2026-08-11): a precedencia declarada (FAIL vence NOT_VERIFIED) nao
# estava implementada. Antes da correcao, o 'return NOT_VERIFIED' dentro do laco descartava o
# FAIL ja acumulado do primeiro ruleset assim que o segundo falhava - a lacuna de medicao
# MASCARAVA a violacao provada.
MRK="$T/chamou-ruleset-v12"; rm -f "$MRK"
RC="$(rodar duplo-inacessivel "$MRK")"
chk "exit code 1 (nao 2 - a violacao provada NAO pode ser mascarada por outro ruleset ilegivel)" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
# ROTULO UNICO (wave5): MV5 mata especificamente AQUI - o rotulo nao pode coincidir com V5/V13.
chk "  motivo cita 'bypass_actors nao vazio' (duplo-inacessivel)" \
    "$(grep -q 'bypass_actors nao vazio' "$T/out" && echo sim || echo nao)" "sim"

echo "== V13. violacao PROVADA num ruleset + outro ruleset NAO-OBJETO -> FAIL, nunca NOT_VERIFIED =="
# Mesma forma de V12, mas o SEGUNDO ponto do laco que retornava cedo (o guard de tipo de
# 'detalhe', nao o de rede).
MRK="$T/chamou-ruleset-v13"; rm -f "$MRK"
RC="$(rodar duplo-nao-dict "$MRK")"
chk "exit code 1" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
# ROTULO UNICO (wave5): MV6 mata especificamente AQUI - o rotulo nao pode coincidir com V5/V12.
chk "  motivo cita 'bypass_actors nao vazio' (duplo-nao-dict)" \
    "$(grep -q 'bypass_actors nao vazio' "$T/out" && echo sim || echo nao)" "sim"

echo "== V14. strict=false (FAIL ja em maos) + o UNICO ruleset aplicavel FALHA -> FAIL =="
# strict_required_status_checks_policy e medido FORA do laco que resolve bypass; a falha ao LER
# o unico ruleset aplicavel nao pode apagar essa violacao ja provada em outro termo.
MRK="$T/chamou-ruleset-v14"; rm -f "$MRK"
RC="$(rodar strict-false-inacessivel "$MRK")"
chk "exit code 1 (nao 2)" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita strict_required_status_checks_policy" \
    "$(grep -q 'strict_required_status_checks_policy' "$T/out" && echo sim || echo nao)" "sim"

echo "== V15. strict=false (medido, reprova) + bypass_actors AUSENTE (nao medido) -> FAIL =="
# (A2): prova que a precedencia declarada e ALCANCAVEL sem nenhum 'return' cedo envolvido - basta
# uma violacao ja medida (strict) coexistir com um campo nao divulgado no MESMO ruleset. Kill
# desta suposicao exige mutante proprio (MV7): sem ele, inverter a ORDEM dos dois 'if' finais
# sobrevive em silencio.
MRK="$T/chamou-ruleset-v15"; rm -f "$MRK"
RC="$(rodar strict-false-bypass-ausente "$MRK")"
chk "exit code 1 (nao 2 - o campo nao medido nao pode rebaixar uma violacao ja provada)" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita strict_required_status_checks_policy" \
    "$(grep -q 'strict_required_status_checks_policy' "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO relata NOT_VERIFIED (a lacuna de bypass_actors nao decide aqui)" \
    "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo vazou || echo contido)" "contido"

# V16-V20 fecham a QUARTA onda de correcao (2026-08-11) - nao mais um guard por campo, e sim
# validacao de schema na fronteira (`valida_campo`, evidence/probes/github-ruleset.py). Os
# quatro primeiros reproduzem C1/C2/A1/A2 tal como a revisao independente mediu; o quinto e a
# forma inesperada que o proprio schema recusa, distinta das quatro (`required_status_checks[i]`
# nao-objeto, nao `bypass_actors`/`parameters`/`ruleset_id`/`enforcement`).
echo "== V16. (C1) 'ruleset_id' ausente em PARTE das regras aplicaveis -> NOT_VERIFIED, nunca PASS =="
# Antes da correcao: a segunda regra (sem 'ruleset_id') desaparecia do conjunto sem deixar
# rastro em nao_medidos, e o portao emitia PASS com a afirmacao UNIVERSAL "bypass_actors=[] em
# todos os rulesets de origem" sem ter resolvido bypass daquela regra. Medido nesta sessao:
# `estado: PASS  exit=0` antes da correcao, com as DUAS regras aplicaveis e so a primeira lida.
MRK="$T/chamou-ruleset-v16"; rm -f "$MRK"
RC="$(rodar c1-parcial "$MRK")"
chk "exit code 2 (nao mais 0 - o PASS fabricado sobre ruleset_id parcial)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'ruleset_id' ausente" "$(grep -q "'ruleset_id' ausente" "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO afirma 'bypass_actors=[] em todos os rulesets de origem' sem ter medido todos" \
    "$(grep -q 'bypass_actors=\[\] em todos os rulesets de origem' "$T/out" && echo afirmou || echo nao-afirmou)" "nao-afirmou"

echo "== V17. (C2) elemento de 'bypass_actors' nao mapeavel (lista de strings) -> NOT_VERIFIED, nunca crash =="
# Antes da correcao: `isinstance(bypass_actors, list)` cobria o CONTAINER, nao o ELEMENTO -
# `["OrganizationAdmin"]` passava o guard e `{"ruleset_id": rid, **a}` estourava TypeError,
# exit 1 (FAIL) por acidente do interprete, nunca a lacuna de oraculo que de fato ocorreu.
MRK="$T/chamou-ruleset-v17"; rm -f "$MRK"
RC="$(rodar c2-elemento "$MRK")"
chk "exit code 2 (nao 1 por TypeError nao tratado)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'bypass_actors[0]' tipo inesperado" \
    "$(grep -q "'bypass_actors\[0\]' tem tipo inesperado" "$T/out" && echo sim || echo nao)" "sim"
# ROTULO UNICO (wave5): MV9 mata especificamente AQUI.
chk "  nao ha traceback do Python em stderr (c2-elemento)" \
    "$(grep -q 'Traceback (most recent call last)' "$T/err" && echo vazou || echo contido)" "contido"

echo "== V18. (A1) 'parameters' de tipo errado (string) -> NOT_VERIFIED, nunca crash =="
# Antes da correcao: `r.get("parameters") or {}` deixava passar qualquer valor truthy, e o
# primeiro `.get()` seguinte (`params.get("strict_required_status_checks_policy")`) estourava
# AttributeError - unico dos quatro campos lidos no laco de 'rsc' sem guard nenhum.
MRK="$T/chamou-ruleset-v18"; rm -f "$MRK"
RC="$(rodar a1-parametros "$MRK")"
chk "exit code 2 (nao 1 por AttributeError nao tratado)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'parameters' tipo inesperado" \
    "$(grep -q "'parameters' tem tipo inesperado" "$T/out" && echo sim || echo nao)" "sim"
chk "  nao ha traceback do Python em stderr (a1-parametros)" \
    "$(grep -q 'Traceback (most recent call last)' "$T/err" && echo vazou || echo contido)" "contido"
chk "  NAO chama o endpoint de ruleset (Required(P) ja nao pode ser confirmado)" \
    "$([ -f "$MRK" ] && echo chamou || echo nao-chamou)" "nao-chamou"

echo "== V19. (A2) 'enforcement' E 'bypass_actors' AUSENTES -> NOT_VERIFIED, nunca FAIL fabricado =="
# Antes da correcao: `detalhe.get("enforcement")` coagia a ausencia em `None`, e
# `enforcement != "active"` fabricava a violacao "enforcement='None'" - FAIL, exit 1 - com a
# lacuna real (bypass_actors tambem ausente) nem sequer mencionada, porque o `return FAIL`
# acontecia antes do bloco que le `nao_medidos`. Medido nesta sessao: exatamente essa saida.
MRK="$T/chamou-ruleset-v19"; rm -f "$MRK"
RC="$(rodar a2-coercao "$MRK")"
chk "exit code 2 (nao 1 - a ausencia nao e mais coagida em violacao)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'enforcement' ausente" "$(grep -q "'enforcement' ausente" "$T/out" && echo sim || echo nao)" "sim"
# ROTULO UNICO (wave5): ver a nota identica em V4 - o mesmo texto NAO pode aparecer nos dois
# casos, senao um mutante que so quebra V4 (ou so V19) e creditado ao caso errado.
chk "  motivo cita 'bypass_actors' ausente (junto de enforcement, a2-coercao)" "$(grep -q "'bypass_actors' ausente" "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO afirma \"enforcement='None'\" (nao fabrica violacao sobre campo nao medido)" \
    "$(grep -qF "enforcement='None'" "$T/out" && echo afirmou || echo nao-afirmou)" "nao-afirmou"

echo "== V20. (schema) 'required_status_checks[i]' nao e objeto -> NOT_VERIFIED, nunca FAIL fabricado =="
# 5o caso: forma inesperada que o SCHEMA recusa, distinta das quatro acima - o mesmo mecanismo
# (`valida_campo` com `tipo_item=dict`) cobre um campo aninhado NOVO sem precisar de guard
# escrito a mao. Sem esta correcao, o item invalido era silenciosamente ignorado (nenhum
# contexto extraido), 'Required(P) = False' virava FAIL fabricado por omissao - o mesmo defeito
# de A2, agora sobre Required(P) em vez de bypass/enforcement.
MRK="$T/chamou-ruleset-v20"; rm -f "$MRK"
RC="$(rodar schema-item-invalido "$MRK")"
chk "exit code 2 (nao 1 - Required(P) nao pode ser concluido False por omissao)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'required_status_checks[0]' tipo inesperado" \
    "$(grep -q "'required_status_checks\[0\]' tem tipo inesperado" "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO afirma 'Required(P) = False' (nao fabrica FAIL a partir de item malformado)" \
    "$(grep -qF 'Required(P) = False' "$T/out" && echo afirmou || echo nao-afirmou)" "nao-afirmou"
chk "  NAO chama o endpoint de ruleset (Required(P) ja nao pode ser confirmado)" \
    "$([ -f "$MRK" ] && echo chamou || echo nao-chamou)" "nao-chamou"

# V21-V31 fecham a QUINTA onda (2026-08-11, o QUINTO DEGRAU e RAMOS DE DECISAO SEM CASO - ver o
# docstring de evidence/probes/github-ruleset.py, secao "O SEXTO CAMPO, ANTES DO SCHEMA"). D1/D2
# sao o filtro que alimenta `rsc` e a linha seguinte (silencio + crash); D3/D4 nao eram defeito de
# CODIGO - eram GARANTIA SEM TESTE: um ramo de decisao existente podia ser deletado sem que a
# suite notasse; D5 e a mesma classe de coercao de ausencia, um passo antes de `valida_campo`.
echo "== V21. (D4a) 'enforcement' PRESENTE mas != 'active' -> FAIL (garantia sem teste ate aqui) =="
# Distinto de V19 (enforcement AUSENTE): aqui o valor FOI medido e e invalido. Antes desta
# correcao, nenhum caso isolava esta forma - trocar 'elif enforcement != "active":' por
# 'elif False:' deixava a suite 78/78 verde.
MRK="$T/chamou-ruleset-v21"; rm -f "$MRK"
RC="$(rodar enforcement-nao-active "$MRK")"
chk "exit code 1" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita enforcement='evaluate'" \
    "$(grep -qF "enforcement='evaluate'" "$T/out" && echo sim || echo nao)" "sim"

echo "== V22. (D4b) 'current_user_can_bypass' PRESENTE mas != 'never' -> FAIL =="
# Distinto de V6 (cucb AUSENTE): aqui o valor FOI medido e e invalido. Trocar
# 'elif cucb != "never":' por 'elif False:' deixava a suite 78/78 verde antes desta correcao.
MRK="$T/chamou-ruleset-v22"; rm -f "$MRK"
RC="$(rodar cucb-nao-never "$MRK")"
chk "exit code 1" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita current_user_can_bypass='always'" \
    "$(grep -qF "current_user_can_bypass='always'" "$T/out" && echo sim || echo nao)" "sim"

echo "== V23. (D3) 'strict_required_status_checks_policy' AUSENTE (nao a variante 'false' explicita) -> NOT_VERIFIED =="
# V7/V14/V15 so cobrem strict:false EXPLICITO. Reintroduzir a ausencia-coagida
# ('strict_medidos.append(bool(params.get(...)))') deixava a suite 78/78 verde: nao havia caso
# isolando strict ausente/nulo/tipo-errado.
MRK="$T/chamou-ruleset-v23"; rm -f "$MRK"
RC="$(rodar strict-ausente "$MRK")"
chk "exit code 2 (nao 1 - ausencia nao e 'strict:false' medido)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'strict_required_status_checks_policy' ausente" \
    "$(grep -q "'strict_required_status_checks_policy' ausente" "$T/out" && echo sim || echo nao)" "sim"

echo "== V24. (D3) 'strict_required_status_checks_policy' e NULL -> NOT_VERIFIED =="
MRK="$T/chamou-ruleset-v24"; rm -f "$MRK"
RC="$(rodar strict-nulo "$MRK")"
chk "exit code 2" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'strict_required_status_checks_policy' e null" \
    "$(grep -qF "'strict_required_status_checks_policy' e null" "$T/out" && echo sim || echo nao)" "sim"

echo "== V25. (D3) 'strict_required_status_checks_policy' de tipo errado (string) -> NOT_VERIFIED =="
MRK="$T/chamou-ruleset-v25"; rm -f "$MRK"
RC="$(rodar strict-tipo-errado "$MRK")"
chk "exit code 2" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'strict_required_status_checks_policy' tipo inesperado" \
    "$(grep -qF "'strict_required_status_checks_policy' tem tipo inesperado" "$T/out" && echo sim || echo nao)" "sim"

echo "== V26. (D5) item de 'required_status_checks' sem 'context' -> NOT_VERIFIED, nunca FAIL fabricado =="
# Antes da correcao: 'chk.get("context")' tratava a chave ausente como "este item nao contribui" -
# Required(P) = False FABRICADO (FAIL, exit 1), nunca medido. Fail-closed na DIRECAO, mas a mesma
# coercao de ausencia em conclusao que A2/C1 ja fecharam em outros pontos.
MRK="$T/chamou-ruleset-v26"; rm -f "$MRK"
RC="$(rodar context-ausente-no-check "$MRK")"
chk "exit code 2 (nao 1 - FAIL fabricado por item sem 'context')" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita 'required_status_checks[0]' sem 'context'" \
    "$(grep -qF "'required_status_checks[0]' sem 'context'" "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO afirma 'Required(P) = False' (nao fabrica FAIL por item sem 'context')" \
    "$(grep -qF 'Required(P) = False' "$T/out" && echo afirmou || echo nao-afirmou)" "nao-afirmou"
chk "  NAO chama o endpoint de ruleset (Required(P) ja nao pode ser confirmado)" \
    "$([ -f "$MRK" ] && echo chamou || echo nao-chamou)" "nao-chamou"

echo "== V27. (D1, O QUINTO DEGRAU) 'type' AUSENTE numa regra, ao lado de outra legivel -> NOT_VERIFIED, nunca PASS =="
# Reproduzido antes desta correcao: com o ruleset da segunda regra (998) trazendo bypass_actors
# NAO VAZIO, 'estado: PASS exit=0' - a regra sem 'type' desaparecia do filtro em silencio, seu
# ruleset_id nunca entrava em ruleset_ids, e nada entrava em nao_medidos. Aqui basta provar que o
# probe NUNCA sai PASS enquanto essa regra permanecer ilegivel.
MRK="$T/chamou-ruleset-v27"; rm -f "$MRK"
RC="$(rodar tipo-ausente-com-regra-valida "$MRK")"
chk "exit code 2 (nao mais 0 - o PASS fabricado sobre 'type' ausente)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita elemento com 'type' ausente" \
    "$(grep -qF "'type' ausente" "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO relata estado PASS" "$(grep -q '^estado: PASS$' "$T/out" && echo vazou || echo contido)" "contido"

echo "== V28. (D1) 'type' presente e NULL numa regra, ao lado de outra legivel -> NOT_VERIFIED =="
MRK="$T/chamou-ruleset-v28"; rm -f "$MRK"
RC="$(rodar tipo-nulo-com-regra-valida "$MRK")"
chk "exit code 2" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita elemento com 'type' null" \
    "$(grep -qF "'type' e null" "$T/out" && echo sim || echo nao)" "sim"

echo "== V29. (D1) elemento de 'rules' que NAO e um objeto, ao lado de outra regra legivel -> NOT_VERIFIED, nunca crash =="
MRK="$T/chamou-ruleset-v29"; rm -f "$MRK"
RC="$(rodar elemento-nao-dict-com-regra-valida "$MRK")"
chk "exit code 2 (nao 1 por excecao nao tratada)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita elemento que nao e um objeto" \
    "$(grep -qF "nao e um objeto" "$T/out" && echo sim || echo nao)" "sim"
chk "  nao ha traceback do Python em stderr (elemento-nao-dict)" \
    "$(grep -q 'Traceback (most recent call last)' "$T/err" && echo vazou || echo contido)" "contido"

echo "== V30. (D2) rsc VAZIO com 'type' MISTO (um ausente) -> NOT_VERIFIED, nunca traceback =="
# Antes da correcao: 'sorted({r.get("type") for r in rules if isinstance(r, dict)})' com
# {None, "deletion"} estourava TypeError ('<' not supported between instances of 'str' and
# 'NoneType') - traceback nao tratado, exit 1 por acidente do interprete.
MRK="$T/chamou-ruleset-v30"; rm -f "$MRK"
RC="$(rodar rsc-vazio-tipo-misto "$MRK")"
chk "exit code 2 (nao 1 por TypeError nao tratado)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  nao ha traceback do Python em stderr (rsc-vazio-tipo-misto)" \
    "$(grep -q 'Traceback (most recent call last)' "$T/err" && echo vazou || echo contido)" "contido"
chk "  NAO chama o endpoint de ruleset (rsc vazio, nada a resolver)" \
    "$([ -f "$MRK" ] && echo chamou || echo nao-chamou)" "nao-chamou"

echo "== V31. rsc VAZIO com tipos CONHECIDOS, sem ambiguidade -> FAIL (Required(P) = False MEDIDO) =="
# Sem ambiguidade nenhuma: as duas regras tem 'type' legivel e nenhuma e required_status_checks -
# prova que a refatoracao do filtro preserva o caminho FAIL legitimo (nao substitui toda
# ausencia de required_status_checks por NOT_VERIFIED, so a ilegivel).
MRK="$T/chamou-ruleset-v31"; rm -f "$MRK"
RC="$(rodar rsc-vazio-tipos-conhecidos "$MRK")"
chk "exit code 1" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo e Required(P) = False (medido, nao suposto)" \
    "$(grep -qF 'Required(P) = False' "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO chama o endpoint de ruleset (rsc vazio, nada a resolver)" \
    "$([ -f "$MRK" ] && echo chamou || echo nao-chamou)" "nao-chamou"

echo "== V32. (wave6) 'ruleset_id' AUSENTE + strict=false JA MEDIDO NA MESMA regra -> FAIL, nunca NOT_VERIFIED =="
# DEFEITO VIVO reproduzido nesta sessao: 'if not ruleset_ids: return NOT_VERIFIED' rodava ANTES
# da agregacao de 'strict_medidos' em 'problemas' - uma violacao JA MEDIDA (strict=false) era
# descartada e rebaixada a NOT_VERIFIED so porque nenhuma regra aplicavel tinha 'ruleset_id'
# resolvivel. `estado: NOT_VERIFIED exit=2` antes da correcao; `estado: FAIL exit=1` depois.
MRK="$T/chamou-ruleset-v32"; rm -f "$MRK"
RC="$(rodar strict-false-ruleset-id-ausente "$MRK")"
chk "exit code 1 (nao 2 - violacao ja medida nao pode ser descartada por ruleset_id ausente)" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita strict_required_status_checks_policy (v32)" \
    "$(grep -q 'strict_required_status_checks_policy' "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO relata NOT_VERIFIED (ruleset_id ausente nao rebaixa violacao ja provada)" \
    "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo vazou || echo contido)" "contido"
chk "  NAO chama o endpoint de ruleset (ruleset_id nunca foi resolvido)" \
    "$([ -f "$MRK" ] && echo chamou || echo nao-chamou)" "nao-chamou"

echo "== V33. (wave6) Required(P) indeterminado (regra ilegivel) + strict=false JA MEDIDO -> FAIL =="
# MESMA violacao de strict, descartada pelo OUTRO 'return' precoce: 'if context not in contextos:
# if nao_medidos: return NOT_VERIFIED' tambem rodava ANTES da agregacao de 'strict_medidos'. As
# duas hipoteses sobre a regra ilegivel (exigia o contexto pedido ou nao) levam ao mesmo FAIL.
MRK="$T/chamou-ruleset-v33"; rm -f "$MRK"
RC="$(rodar strict-false-required-indeterminado "$MRK")"
chk "exit code 1 (nao 2 - violacao ja medida nao pode ser descartada por Required(P) indeterminado)" "$RC" 1
chk "relata estado FAIL" "$(grep -q '^estado: FAIL$' "$T/out" && echo sim || echo nao)" "sim"
chk "  motivo cita strict_required_status_checks_policy (v33)" \
    "$(grep -q 'strict_required_status_checks_policy' "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO relata NOT_VERIFIED (regra ilegivel nao rebaixa violacao ja provada)" \
    "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo vazou || echo contido)" "contido"
chk "  NAO chama o endpoint de ruleset (retorno antes do laco que resolve bypass)" \
    "$([ -f "$MRK" ] && echo chamou || echo nao-chamou)" "nao-chamou"

echo "== V34. (wave6, NAO-REGRESSAO) 'ruleset_id' AUSENTE, SEM violacao (strict=true) -> continua NOT_VERIFIED =="
# Prova que o guard 'if problemas' introduzido por V32 REALMENTE gateia no valor de 'problemas' -
# nao apenas inverteu o defeito antigo (NOT_VERIFIED fabricado) para o oposto (FAIL fabricado sem
# nenhuma violacao medida). Achado ao validar por mutacao: um mutante que forca este bloco a
# retornar FAIL incondicionalmente sobrevivia aos 127 casos V1-V33 ate este caso ser adicionado.
MRK="$T/chamou-ruleset-v34"; rm -f "$MRK"
RC="$(rodar ruleset-id-ausente-sem-violacao "$MRK")"
chk "exit code 2 (sem violacao medida, ausencia de ruleset_id continua NOT_VERIFIED)" "$RC" 2
chk "relata estado NOT_VERIFIED" "$(grep -q '^estado: NOT_VERIFIED$' "$T/out" && echo sim || echo nao)" "sim"
chk "  NAO relata estado FAIL (sem violacao medida, nao pode fabricar FAIL)" \
    "$(grep -q '^estado: FAIL$' "$T/out" && echo vazou || echo contido)" "contido"
chk "  motivo cita 'ruleset_id' valido ausente" \
    "$(grep -q "'ruleset_id' valido" "$T/out" && echo sim || echo nao)" "sim"

echo
printf '================ PASS=%s  FAIL=%s ================\n' "$P" "$F"
# CONTAGEM INVARIANTE: um caso que parasse de rodar aqui sumiria em silencio, e V2/V4/V5/V6/V7/V8/
# V10-V34 - os casos negativos desta suite - sao precisamente o que nao pode desaparecer sem sinal.
EXPECTED=131
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "fronteira viva verde ($P/$EXPECTED)" || echo "fronteira viva VERMELHA ($F falhas)"
exit "$F"
