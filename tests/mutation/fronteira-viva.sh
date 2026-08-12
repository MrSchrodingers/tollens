#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - evidence/probes/github-ruleset.py, o termo ¬Bypass(a,P).
#
# Por que existe: o achado CRITICO da revisao independente de 2026-08-10 - o probe afirmava
# `bypass_actors=[]` sobre um campo que a API NAO devolveu, e saia PASS/exit 0 - e uma garantia
# de SEGURANCA (a regra de metodo 2, docs/adr/0020, exige mutacao para toda garantia de
# seguranca: remova-a e o teste tem de REPROVAR). `tests/unit/fronteira-viva.sh` ganhou os casos
# V4/V6/V9 para medir o comportamento CORRIGIDO; esta suite prova que, sem a correcao, esses
# casos voltam a passar (ou a quebrar de outra forma) - isto e, que o guard REALMENTE decide o
# veredito, e nao e so prosa ao lado do codigo que continua fazendo o de sempre.
#
# O MUTANTE CENTRAL (MV1) e a reproducao LITERAL do defeito: reverter o campo ausente para
# `detalhe.get("bypass_actors") or []` - a mesma linha que estava em producao. MV2/MV3/MV4 isolam
# cada guard individualmente, para que a suite nao dependa de um unico ponto de falha coincidir
# com um unico ponto de teste.
#
# MV5/MV6/MV7 fecham um SEGUNDO achado CRITICO (2026-08-11): a precedencia declarada (FAIL vence
# NOT_VERIFIED) nao estava implementada onde a medicao acontece em laco. MV5 e MV6 revertem cada
# um dos DOIS `return NOT_VERIFIED` que existiam dentro do laco de rulesets - um para o erro de
# rede/permissao ao ler um ruleset, outro para a resposta que nao e um objeto - e que descartavam
# `problemas` ja acumulado. MV7 inverte a ORDEM dos dois `if` do portao final, provando que a
# precedencia depende dessa ordem e nao so da ausencia de `return` cedo no laco.
#
# MV8-MV11 fecham a QUARTA onda (2026-08-11, C1/C2/A1/A2 - ver o docstring de
# evidence/probes/github-ruleset.py, secao "SCHEMA NA FRONTEIRA"): a substituicao de guards
# ad hoc por `valida_campo` nao teria valor se pudesse ser revertida em silencio. MV8 reproduz
# (C1) ('ruleset_id' ausente em parte das regras aplicaveis volta a sumir sem nao_medido); MV9
# reproduz C2 (guard do ELEMENTO de bypass_actors removido, container continua validado); MV10
# reproduz A1 ('parameters' sem guard, `or {}`); MV11 reproduz A2 ('enforcement' ausente coagido
# em violacao fabricada).
#
# MV12-MV16 fecham a QUINTA onda (2026-08-11, O QUINTO DEGRAU e RAMOS DE DECISAO SEM CASO - ver o
# docstring de evidence/probes/github-ruleset.py, secao "O SEXTO CAMPO, ANTES DO SCHEMA"). MV12 e
# MV13 provam que a deteccao de `enforcement`/`current_user_can_bypass` PRESENTES mas invalidos
# (nao a ausencia, ja coberta por MV11) e codigo REALMENTE testado, nao so escrito - antes desta
# onda nenhum caso de regressao isolava esses dois ramos, e trocar cada `elif` por `elif False:`
# deixava a suite inteira verde. MV14 prova o mesmo para `strict_required_status_checks_policy`
# ausente/nulo/tipo-errado (so a variante `false` EXPLICITA tinha caso). MV15 fecha a MESMA classe
# de coercao de ausencia um passo antes de `valida_campo` ser sequer chamado: o campo `context` de
# cada item de `required_status_checks`. MV16 e O QUINTO DEGRAU propriamente dito: reverte o laco
# que valida `type` de cada elemento de `rules/branches/{branch}` - a fronteira de entrada que
# alimenta TODO o resto do schema - para o filtro original de uma linha, que descartava em
# silencio qualquer elemento com `type` ausente/nulo/tipo errado, e para a linha seguinte, que
# crashava com `TypeError` quando `type` ausente coexistia com um `type` presente no mesmo laco.
#
# MV17-MV18 fecham a SEXTA onda (2026-08-11, defeito achado pelo portao final da onda 5): um
# `return NOT_VERIFIED`/`FAIL` DENTRO da propria funcao `probe`, mas ANTES da agregacao de
# `strict_medidos` em `problemas`, descartava uma violacao de `strict_required_status_checks_policy`
# JA MEDIDA - a mesma classe de defeito que MV5/MV6 fecharam para o laco de rulesets, agora um
# passo mais cedo. MV17 reverte o bloco `if not ruleset_ids:` para a forma sem o `if problemas`
# (o `return NOT_VERIFIED` volta a rodar incondicionalmente). MV18 reverte o bloco `if context not
# in contextos: if nao_medidos:` da mesma forma. Kill em V32/V33, respectivamente - pontos de
# codigo DIFERENTES, exigem mutantes proprios pela mesma razao que MV5/MV6 exigiram.
#
# MV19 fecha o DEFEITO OPOSTO no mesmo bloco de MV17, achado ao validar por mutacao NESTA sessao:
# o guard `if problemas` precisa GATEAR de fato no valor de `problemas`, nao so ter sido inserido
# em algum lugar do bloco. Um mutante que forca `if not ruleset_ids:` a retornar FAIL
# incondicionalmente (`if True:` no lugar de `if problemas:`) sobrevivia aos 127 casos V1-V33 -
# nenhum deles alcanca este bloco com `ruleset_ids` vazio E `problemas` genuinamente vazio (sem
# violacao medida). V34 fecha essa lacuna; kill designado aqui.
#
# MV20 fecha D6 (achado de uma revisao independente SEGUINTE, 2026-08-11, wave6b): a metade
# ESPELHADA de D5 (MV15). D5/MV15 fecharam o CAMPO 'context' de cada ITEM de
# 'required_status_checks'; o proprio CONTAINER - a lista inteira dentro de 'parameters' - nunca
# tinha guard. `valida_campo` ja distinguia os quatro estados do container, mas o chamador so
# ramificava em ITEM_INVALIDO: FALTANTE/NULO/TIPO_INVALIDO caiam num comentario que tratava a
# forma ilegivel como equivalente a uma lista vazia - falso para os tres, verdadeiro so para a
# lista vazia genuina. MV20 reverte para esse comentario original. Kill em V35.
#
# TROCA POR ARQUIVO, NAO POR ARGUMENTO DE SHELL. Os trechos mutados tem aspas simples e duplas
# aninhadas (`f"ruleset {rid}: '{cucb}'"`); escrever isso como argumento de shell (single ou
# double-quoted) obrigaria a escapar aspas dentro de aspas - fragil e ilegivel, e exatamente a
# razao que `tests/mutation/run.sh` deu para preferir substituicao literal a `sed`. Aqui o
# trecho vai para um ARQUIVO via heredoc de delimitador citado ('EOF'): sem qualquer expansao ou
# necessidade de escape, porque o heredoc citado e sempre texto literal.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
ORIG="evidence/probes/github-ruleset.py"
REG="tests/unit/fronteira-viva.sh"
# ORDEM DO TRAP: RESTAURAR ANTES DE REMOVER (tests/unit/arnes-de-mutacao.sh AM1/AM2 exigem
# exatamente este idioma - ver docs/adr/0020 e o incidente que o motivou em tests/mutation/run.sh).
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.py" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.py"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=29

command -v python3 >/dev/null 2>&1 || { echo "NAO VERIFICADO: python3 ausente - a mutacao nao pode ser avaliada." >&2; exit 2; }

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

# `troca` opera sobre ARQUIVOS (de/para), e exige a ancora presente EXATAMENTE uma vez: um padrao
# que casasse mais de uma vez mutaria em local errado sem avisar, e um padrao que nao casasse
# nenhuma vez produziria um mutante "aplicado" por acidente sobre outro trecho - as duas formas
# sao teste invalido, nao mutante morto nem sobrevivente.
troca(){ # $1=arquivo com o trecho original  $2=arquivo com o substituto
  python3 - "$ORIG" "$1" "$2" <<'PYT'
import sys
alvo, velho_f, novo_f = sys.argv[1:4]
s = open(alvo, encoding="utf-8").read()
with open(velho_f, encoding="utf-8") as fh:
    velho = fh.read()
with open(novo_f, encoding="utf-8") as fh:
    novo = fh.read()
n = s.count(velho)
if n != 1:
    sys.exit("ANCORA NAO CASOU UMA UNICA VEZ (%d ocorrencias)" % n)
open(alvo, "w", encoding="utf-8").write(s.replace(velho, novo))
PYT
}

mutante(){ # $1=nome $2=descricao $3=caso-alvo que DEVE reprovar $4=arq-de $5=arq-para
  local nome="$1" desc="$2" alvo="$3" de="$4" para="$5"
  cp -f "$TMP/orig.py" "$ORIG"
  troca "$de" "$para"
  if cmp -s "$TMP/orig.py" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - a ancora nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); cp -f "$TMP/orig.py" "$ORIG"; return
  fi
  if ! python3 -m py_compile "$ORIG" 2>/dev/null; then
    echo "  FAIL  $nome nao compila apos a mutacao"; F=$((F+1)); cp -f "$TMP/orig.py" "$ORIG"; return
  fi
  local out rc
  out="$(bash "$REG" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    echo "  FAIL  $nome SOBREVIVEU - a suite passa sem a garantia: $desc"; F=$((F+1))
  elif printf '%s' "$out" | grep -qF "FAIL  $alvo"; then
    echo "  PASS  $nome morto pelo caso certo ($alvo)"; P=$((P+1))
  else
    echo "  FAIL  $nome: suite reprovou, mas NAO em '$alvo' - kill nao atribuivel"; F=$((F+1))
    printf '%s\n' "$out" | grep FAIL | sed 's/^/        /'
  fi
  cp -f "$TMP/orig.py" "$ORIG"
}

echo "== mutacao: cada guard do bloco ¬Bypass(a,P) removido DEVE reprovar =="

# MV1 - O MUTANTE CENTRAL. Reverte o bloco `valida_campo(detalhe, "bypass_actors", ...)` para a
# linha EXATA do defeito em producao: `detalhe.get("bypass_actors") or []`. Isto colapsa "campo
# nao devolvido" (falta de acesso de escrita ao ruleset) em "medido: []" - o PASS fabricado que
# a revisao independente encontrou contra github/docs. Reancorado na onda 4 (wave4/y1-schema):
# o corpo do guard mudou de um `if/elif` manual sobre `detalhe["bypass_actors"]` para o schema
# declarativo `valida_campo`, que tambem fecha C2 (elemento nao mapeavel dentro da lista).
cat > "$TMP/mv1-de.txt" <<'EOF'
        bp_status, bp_valor = valida_campo(detalhe, "bypass_actors", list, tipo_item=dict)
        if bp_status == FALTANTE:
            # (wave8, O OITAVO DEGRAU) `current_user_can_bypass` e o campo que o SERVIDOR calcula
            # e devolve PARA O ATOR AUTENTICADO, sem exigir acesso de escrita ao ruleset (ao
            # contrario de `bypass_actors`, a LISTA completa - ver o docstring desta funcao).
            # Segunda leitura, PURA, do mesmo `valida_campo` ja chamado abaixo na posicao normal
            # (sem efeito colateral - so verifica, nao substitui a validacao de baixo): se o
            # servidor ja confirma 'never' PARA ESTE ator, not Bypass(a,P) foi MEDIDO POR
            # COMPLETO para ele - MEDICAO PARCIAL DECLARADA, nao lacuna geral (a lacuna que sobra,
            # bypass concedido a OUTRO ator/role, e nomeada explicitamente, nunca escondida).
            cucb_pre_status, cucb_pre = valida_campo(detalhe, "current_user_can_bypass", str)
            if cucb_pre_status is None and cucb_pre == "never":
                msg = (
                    f"ruleset {rid}: 'bypass_actors' ausente da resposta (a API so devolve este "
                    f"campo a quem tem acesso de escrita ao ruleset), mas "
                    f"'current_user_can_bypass'='never' foi medido para o ator autenticado - "
                    f"MEDICAO PARCIAL DECLARADA de not Bypass(a,P), nao lacuna geral: bypass "
                    f"concedido a OUTRO ator/role nao pode ser descartado por este probe sob "
                    f"este token.")
                nao_medidos.append(msg)
                medicao_parcial.append(msg)
            else:
                nao_medidos.append(
                    f"ruleset {rid}: 'bypass_actors' ausente da resposta - not Bypass(a,P) NAO "
                    f"foi medido. A API so devolve este campo a quem tem acesso de escrita ao "
                    f"ruleset.")
        elif bp_status == NULO:
            # Mesma doutrina da chave ausente, um passo adiante: um valor `null` EXPLICITO
            # tambem nao e "medido: []". `atores = detalhe["bypass_actors"] or []` colapsava os
            # dois casos no mesmo PASS fabricado que a correcao anterior fechou so para a chave
            # ausente - a INSTANCIA foi corrigida, a CLASSE (valor nulo) continuava aberta.
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' e null na resposta - not Bypass(a,P) NAO foi "
                f"medido (mesma doutrina de campo ausente).")
        elif bp_status == TIPO_INVALIDO:
            # Tipo inesperado (ex.: string, numero): sem este guard, `**a` sobre um elemento que
            # nao e mapeamento (ou a propria iteracao sobre uma string) produz TypeError nao
            # tratado - a mesma promessa de "nunca traceback" que ja valia para o OBJETO
            # `detalhe`, agora tambem para este CAMPO dele.
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' tem tipo inesperado "
                f"({type(bp_valor).__name__}, esperava lista) - oraculo "
                f"malformado, not Bypass(a,P) NAO foi medido.")
        elif bp_status == ITEM_INVALIDO:
            # (C2) o guard acima cobria o CONTAINER (`isinstance(..., list)`), nao o ELEMENTO -
            # uma lista de nao-mapeamentos (`["OrganizationAdmin"]`) passava por ele e estourava
            # TypeError em `{"ruleset_id": rid, **a}`. `valida_campo` fecha a mesma classe de
            # defeito no ELEMENTO que ja fechava no container.
            idx, item = bp_valor
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors[{idx}]' tem tipo inesperado "
                f"({type(item).__name__}, esperava objeto) - elemento nao mapeavel, "
                f"not Bypass(a,P) NAO foi medido por completo.")
        else:
            if bp_valor:
                bypass_total.extend({"ruleset_id": rid, **a} for a in bp_valor)
EOF
cat > "$TMP/mv1-para.txt" <<'EOF'
        atores = detalhe.get("bypass_actors") or []
        if atores:
            bypass_total.extend({"ruleset_id": rid, **a} for a in atores)
EOF
mutante MV1 "campo ausente vira PASS fabricado outra vez ('or []' sobre bypass_actors)" \
  "  motivo cita 'bypass_actors' ausente (ruleset unico)" "$TMP/mv1-de.txt" "$TMP/mv1-para.txt"

# MV2 - mesma doutrina, segundo campo: current_user_can_bypass ausente volta a ser aceito como
# "never" por omissao (`cucb not in (None, "never")`), em vez de NOT_VERIFIED. Reancorado na
# onda 4: o corpo passou a usar `valida_campo`.
cat > "$TMP/mv2-de.txt" <<'EOF'
        cucb_status, cucb = valida_campo(detalhe, "current_user_can_bypass", str)
        if cucb_status == FALTANTE:
            nao_medidos.append(
                f"ruleset {rid}: 'current_user_can_bypass' ausente da resposta - not Bypass(a,P) "
                f"NAO foi medido para o ator autenticado (mesma doutrina de 'bypass_actors': "
                f"ausencia nao e 'never').")
        elif cucb_status == NULO:
            nao_medidos.append(
                f"ruleset {rid}: 'current_user_can_bypass' e null na resposta - mesma doutrina de campo ausente.")
        elif cucb_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"ruleset {rid}: 'current_user_can_bypass' tem tipo inesperado "
                f"({type(cucb).__name__}, esperava string) - nao medido.")
        elif cucb != "never":
            problemas.append(
                f"ruleset {rid}: current_user_can_bypass='{cucb}' (esperado 'never')")
EOF
cat > "$TMP/mv2-para.txt" <<'EOF'
        cucb = detalhe.get("current_user_can_bypass")
        if cucb not in (None, "never"):
            problemas.append(
                f"ruleset {rid}: current_user_can_bypass='{cucb}' (esperado 'never')")
EOF
mutante MV2 "current_user_can_bypass ausente volta a contar como 'never'" \
  "  motivo cita 'current_user_can_bypass' ausente" "$TMP/mv2-de.txt" "$TMP/mv2-para.txt"

# MV3 - o type-guard sobre a resposta de rulesets/{id} some. Sem ele, `valida_campo` roda sobre
# um `detalhe` que nao e dict; para um ESCALAR (int/bool/null) isso estoura TypeError nao tratado
# em `nome not in objeto` - o processo sai com traceback e exit 1 (FAIL) em vez de exit 2
# (NOT_VERIFIED). V9 usa um escalar (`42`) exatamente por isto: uma LISTA ou string nao expoe
# este mutante, porque `in` sobre lista/string testa pertencimento sem crashar - so um valor
# nao iteravel reproduz o defeito que este guard existe para evitar.
cat > "$TMP/mv3-de.txt" <<'EOF'
        if not isinstance(detalhe, dict):
            # Mesma doutrina do type-guard de `rules` acima: uma resposta que nao e objeto nao
            # pode ser lida com `.get(...)` sem AttributeError, e um oraculo malformado e
            # "nao medido" - nunca a excecao nao tratada que sairia 1 (FAIL) por acidente.
            nao_medidos.append(
                f"ruleset {rid}: resposta de rulesets/{rid} nao e um objeto: "
                f"{type(detalhe).__name__} - oraculo malformado, nao ha como resolver "
                f"bypass_actors nem enforcement")
            continue
EOF
: > "$TMP/mv3-para.txt"
mutante MV3 "resposta nao-dict de rulesets/{id} crasha com TypeError, nao NOT_VERIFIED" \
  "  nao ha traceback do Python em stderr (resposta-nao-dict)" "$TMP/mv3-de.txt" "$TMP/mv3-para.txt"

# MV4 - a DETECCAO de campo ausente continua populando `nao_medidos`, mas o portao final que a
# transforma em NOT_VERIFIED some. Ponto de codigo DIFERENTE de MV1/MV2 (o guard por-campo
# continua escrito; o que falta e o efeito): prova que a garantia depende de DOIS pontos, nao so
# do primeiro, e que remover so o segundo tambem quebra o veredito.
cat > "$TMP/mv4-de.txt" <<'EOF'
    if nao_medidos:
        if medicao_parcial and len(nao_medidos) == len(medicao_parcial):
            # (wave8, O OITAVO DEGRAU) TODA entrada de `nao_medidos`, sem excecao, e da forma
            # tolerada (`medicao_parcial` e SUBCONJUNTO de `nao_medidos` por construcao - ver o
            # docstring de `resolve_bypass` - e aqui os dois tem o MESMO tamanho): nenhuma OUTRA
            # lacuna, de nenhuma origem, permanece. not Bypass(a,P) foi MEDIDO POR COMPLETO para o
            # ator autenticado em TODOS os rulesets de origem - a unica coisa que falta e a LISTA
            # de outros atores com bypass concedido, que este token nao tem permissao de ler.
            # PASS_PARCIAL, nao PASS: `estado` fica DISTINTO de PASS puro (verificado literalmente
            # pela suite), e a limitacao fica NOMEADA em `motivo` - nunca um PASS silencioso sobre
            # o residuo que sobra.
            return Resultado(
                PASS_PARCIAL,
                f"Applies(P,r) e Required(P) valem e nenhuma violacao foi encontrada nos campos "
                f"medidos. not Bypass(a,P) foi MEDIDO POR COMPLETO para o ator autenticado "
                f"('current_user_can_bypass'='never' em todos os rulesets de origem "
                f"{sorted(ruleset_ids)}), mas a LISTA completa de atores com bypass concedido "
                f"('bypass_actors') nao foi divulgada pela API (exige acesso de escrita ao "
                f"ruleset) - MEDICAO PARCIAL DECLARADA, nao lacuna geral: "
                + "; ".join(medicao_parcial),
                {"rules": rules, "rulesets": detalhes_rulesets},
            )
        return Resultado(
            NOT_VERIFIED,
            "Applies(P,r) e Required(P) valem e nenhuma violacao foi encontrada nos campos "
            "medidos, mas not Bypass(a,P) NAO foi medido por completo - PASS exigiria medir, "
            "nao supor: " + "; ".join(nao_medidos),
            {"rules": rules, "rulesets": detalhes_rulesets},
        )
EOF
: > "$TMP/mv4-para.txt"
mutante MV4 "deteccao sem efeito: nao_medidos preenchido mas nunca vira NOT_VERIFIED" \
  "  motivo cita 'bypass_actors' ausente (ruleset unico)" "$TMP/mv4-de.txt" "$TMP/mv4-para.txt"

echo "== mutacao: a precedencia (FAIL vence NOT_VERIFIED) removida DEVE reprovar =="

# MV5 - reverte o PRIMEIRO ponto do laco que retornava cedo: falha de rede/permissao ao ler um
# ruleset volta a `return NOT_VERIFIED` imediato, descartando `problemas` ja acumulado (o strict
# medido antes do laco, ou o bypass_actors de um ruleset anterior no MESMO laco).
cat > "$TMP/mv5-de.txt" <<'EOF'
        if err:
            nao_medidos.append(
                f"ruleset {rid}: nao foi possivel ler para resolver bypass: {err}")
            continue
EOF
cat > "$TMP/mv5-para.txt" <<'EOF'
        if err:
            return Resultado(NOT_VERIFIED,
                              f"nao foi possivel ler o ruleset {rid} para resolver bypass: {err}")
EOF
mutante MV5 "erro de rede/permissao em UM ruleset volta a mascarar violacao ja provada em outro" \
  "  motivo cita 'bypass_actors nao vazio' (duplo-inacessivel)" "$TMP/mv5-de.txt" "$TMP/mv5-para.txt"

# MV6 - reverte o SEGUNDO ponto do laco que retornava cedo: resposta de rulesets/{id} que nao e
# um objeto volta a `return NOT_VERIFIED` imediato em vez de registrar e CONTINUAR. Mesma classe
# de mascaramento de MV5, ponto de codigo DIFERENTE - por isso precisa de mutante proprio.
cat > "$TMP/mv6-de.txt" <<'EOF'
        if not isinstance(detalhe, dict):
            # Mesma doutrina do type-guard de `rules` acima: uma resposta que nao e objeto nao
            # pode ser lida com `.get(...)` sem AttributeError, e um oraculo malformado e
            # "nao medido" - nunca a excecao nao tratada que sairia 1 (FAIL) por acidente.
            nao_medidos.append(
                f"ruleset {rid}: resposta de rulesets/{rid} nao e um objeto: "
                f"{type(detalhe).__name__} - oraculo malformado, nao ha como resolver "
                f"bypass_actors nem enforcement")
            continue
EOF
cat > "$TMP/mv6-para.txt" <<'EOF'
        if not isinstance(detalhe, dict):
            # Mesma doutrina do type-guard de `rules` acima: uma resposta que nao e objeto nao
            # pode ser lida com `.get(...)` sem AttributeError, e um oraculo malformado e
            # NOT_VERIFIED - nunca a excecao nao tratada que sairia 1 (FAIL) por acidente.
            return Resultado(
                NOT_VERIFIED,
                f"resposta de rulesets/{rid} nao e um objeto: {type(detalhe).__name__} - "
                f"oraculo malformado, nao ha como resolver bypass_actors nem enforcement")
EOF
mutante MV6 "resposta nao-objeto em UM ruleset volta a mascarar violacao ja provada em outro" \
  "  motivo cita 'bypass_actors nao vazio' (duplo-nao-dict)" "$TMP/mv6-de.txt" "$TMP/mv6-para.txt"

# MV7 - inverte a ORDEM dos dois `if` do portao final: `nao_medidos` passa a ser checado ANTES
# de `problemas`. Sem os dois `return` cedo (MV5/MV6 ja cobrem isso), a precedencia declarada
# ainda depende desta ordem: um caso onde a MESMA execucao acumula os dois (ex.: strict medido
# ANTES do laco + bypass_actors nao divulgado no unico ruleset) so sai FAIL se `problemas` for
# checado primeiro. C-018 declarava explicitamente que esta precedencia nao tinha mutante.
cat > "$TMP/mv7-de.txt" <<'EOF'
    if problemas:
        # FAIL vence sobre "nao medido": uma violacao ja PROVADA (bypass_actors nao vazio,
        # current_user_can_bypass != never, enforcement != active, strict desligado) decide
        # Bypass(a,P) = True de qualquer forma, mesmo que outro ruleset aplicavel nao tenha
        # divulgado o proprio campo. Rebaixar isso a NOT_VERIFIED esconderia um problema real
        # atras de "faltou permissao para medir" - o oposto do fail-closed que este bloco existe
        # para impor.
        return Resultado(
            FAIL,
            "Applies(P,r) e Required(P) valem, mas Bypass(a,P) ou a politica de atualizacao "
            "falham: " + "; ".join(problemas),
            {"rules": rules, "rulesets": detalhes_rulesets},
        )

    if nao_medidos:
        if medicao_parcial and len(nao_medidos) == len(medicao_parcial):
            # (wave8, O OITAVO DEGRAU) TODA entrada de `nao_medidos`, sem excecao, e da forma
            # tolerada (`medicao_parcial` e SUBCONJUNTO de `nao_medidos` por construcao - ver o
            # docstring de `resolve_bypass` - e aqui os dois tem o MESMO tamanho): nenhuma OUTRA
            # lacuna, de nenhuma origem, permanece. not Bypass(a,P) foi MEDIDO POR COMPLETO para o
            # ator autenticado em TODOS os rulesets de origem - a unica coisa que falta e a LISTA
            # de outros atores com bypass concedido, que este token nao tem permissao de ler.
            # PASS_PARCIAL, nao PASS: `estado` fica DISTINTO de PASS puro (verificado literalmente
            # pela suite), e a limitacao fica NOMEADA em `motivo` - nunca um PASS silencioso sobre
            # o residuo que sobra.
            return Resultado(
                PASS_PARCIAL,
                f"Applies(P,r) e Required(P) valem e nenhuma violacao foi encontrada nos campos "
                f"medidos. not Bypass(a,P) foi MEDIDO POR COMPLETO para o ator autenticado "
                f"('current_user_can_bypass'='never' em todos os rulesets de origem "
                f"{sorted(ruleset_ids)}), mas a LISTA completa de atores com bypass concedido "
                f"('bypass_actors') nao foi divulgada pela API (exige acesso de escrita ao "
                f"ruleset) - MEDICAO PARCIAL DECLARADA, nao lacuna geral: "
                + "; ".join(medicao_parcial),
                {"rules": rules, "rulesets": detalhes_rulesets},
            )
        return Resultado(
            NOT_VERIFIED,
            "Applies(P,r) e Required(P) valem e nenhuma violacao foi encontrada nos campos "
            "medidos, mas not Bypass(a,P) NAO foi medido por completo - PASS exigiria medir, "
            "nao supor: " + "; ".join(nao_medidos),
            {"rules": rules, "rulesets": detalhes_rulesets},
        )
EOF
cat > "$TMP/mv7-para.txt" <<'EOF'
    if nao_medidos:
        if medicao_parcial and len(nao_medidos) == len(medicao_parcial):
            # (wave8, O OITAVO DEGRAU) TODA entrada de `nao_medidos`, sem excecao, e da forma
            # tolerada (`medicao_parcial` e SUBCONJUNTO de `nao_medidos` por construcao - ver o
            # docstring de `resolve_bypass` - e aqui os dois tem o MESMO tamanho): nenhuma OUTRA
            # lacuna, de nenhuma origem, permanece. not Bypass(a,P) foi MEDIDO POR COMPLETO para o
            # ator autenticado em TODOS os rulesets de origem - a unica coisa que falta e a LISTA
            # de outros atores com bypass concedido, que este token nao tem permissao de ler.
            # PASS_PARCIAL, nao PASS: `estado` fica DISTINTO de PASS puro (verificado literalmente
            # pela suite), e a limitacao fica NOMEADA em `motivo` - nunca um PASS silencioso sobre
            # o residuo que sobra.
            return Resultado(
                PASS_PARCIAL,
                f"Applies(P,r) e Required(P) valem e nenhuma violacao foi encontrada nos campos "
                f"medidos. not Bypass(a,P) foi MEDIDO POR COMPLETO para o ator autenticado "
                f"('current_user_can_bypass'='never' em todos os rulesets de origem "
                f"{sorted(ruleset_ids)}), mas a LISTA completa de atores com bypass concedido "
                f"('bypass_actors') nao foi divulgada pela API (exige acesso de escrita ao "
                f"ruleset) - MEDICAO PARCIAL DECLARADA, nao lacuna geral: "
                + "; ".join(medicao_parcial),
                {"rules": rules, "rulesets": detalhes_rulesets},
            )
        return Resultado(
            NOT_VERIFIED,
            "Applies(P,r) e Required(P) valem e nenhuma violacao foi encontrada nos campos "
            "medidos, mas not Bypass(a,P) NAO foi medido por completo - PASS exigiria medir, "
            "nao supor: " + "; ".join(nao_medidos),
            {"rules": rules, "rulesets": detalhes_rulesets},
        )

    if problemas:
        # FAIL vence sobre "nao medido": uma violacao ja PROVADA (bypass_actors nao vazio,
        # current_user_can_bypass != never, enforcement != active, strict desligado) decide
        # Bypass(a,P) = True de qualquer forma, mesmo que outro ruleset aplicavel nao tenha
        # divulgado o proprio campo. Rebaixar isso a NOT_VERIFIED esconderia um problema real
        # atras de "faltou permissao para medir" - o oposto do fail-closed que este bloco existe
        # para impor.
        return Resultado(
            FAIL,
            "Applies(P,r) e Required(P) valem, mas Bypass(a,P) ou a politica de atualizacao "
            "falham: " + "; ".join(problemas),
            {"rules": rules, "rulesets": detalhes_rulesets},
        )
EOF
# REANCORADO (wave8): o bloco `if nao_medidos:` ganhou o ramo PASS_PARCIAL (ver O OITAVO DEGRAU).
# Kill originalmente em "NAO relata NOT_VERIFIED" (V15) parou de ser garantia: apos o swap, V15
# ('strict-false-bypass-ausente' - strict=false JA MEDIDO + bypass_actors ausente COM
# current_user_can_bypass='never', a mesma forma que agora e MEDICAO PARCIAL) cai no ramo
# nao_medidos PRIMEIRO e sai PASS_PARCIAL, nao NOT_VERIFIED - o sintoma mudou de forma (o
# `estado: NOT_VERIFIED` nunca aparece, mas tambem nao deveria), so a asercao de EXIT CODE de V15
# (que reprova para QUALQUER veredito != FAIL) continua correta sob as duas formas do sintoma;
# verificado empiricamente (aplicar so este `troca` e rodar a suite) antes de fixar o alvo.
mutante MV7 "ordem do portao final invertida: nao_medidos passa a vencer problemas" \
  "exit code 1 (nao 2 - o campo nao medido nao pode rebaixar uma violacao ja provada)" \
  "$TMP/mv7-de.txt" "$TMP/mv7-para.txt"

echo "== mutacao: schema na fronteira (onda 4, 2026-08-11) - C1/C2/A1/A2 =="

# MV8 - C1: reverte a resolucao de 'ruleset_id' para o defeito exato - uma regra sem
# 'ruleset_id' (ou de tipo/valor invalido) simplesmente NAO entra em `ruleset_ids`, sem deixar
# rastro em `nao_medidos`. `rotulo` continua calculado (usado pelos guards de 'parameters'
# logo abaixo, que este mutante nao toca) - so o EFEITO do guard de ruleset_id desaparece.
cat > "$TMP/mv8-de.txt" <<'EOF'
        if rid_status == FALTANTE:
            # (C1) a regra some do conjunto sem isto - o bypass dela nunca seria resolvido, e
            # antes desta correcao nada entrava em `nao_medidos` para dizer que isso aconteceu.
            nao_medidos.append(
                f"{rotulo}: 'ruleset_id' ausente da regra - not Bypass(a,P) e enforcement NAO "
                f"podem ser resolvidos para esta regra especifica (as demais regras aplicaveis, "
                f"se legiveis, continuam sendo medidas).")
        elif rid_status == NULO:
            nao_medidos.append(f"{rotulo}: 'ruleset_id' e null na regra - mesma doutrina de campo ausente.")
        elif rid_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"{rotulo}: 'ruleset_id' tem tipo inesperado ({type(rid).__name__}, esperava "
                f"inteiro) - oraculo malformado, nao e possivel resolver bypass_actors nem "
                f"enforcement para esta regra.")
        else:
            ruleset_ids.add(rid)
EOF
cat > "$TMP/mv8-para.txt" <<'EOF'
        if rid is not None:
            ruleset_ids.add(rid)
EOF
mutante MV8 "regra sem ruleset_id some do conjunto sem nao_medido - PASS fabricado outra vez" \
  "  motivo cita 'ruleset_id' ausente" "$TMP/mv8-de.txt" "$TMP/mv8-para.txt"

# MV9 - C2: remove `tipo_item=dict` da validacao de 'bypass_actors'. O CONTAINER continua
# validado (lista), mas o ELEMENTO nao - uma lista de strings volta a passar, e `**a` sobre um
# elemento nao mapeavel estoura TypeError nao tratado, exit 1 (FAIL) por acidente.
cat > "$TMP/mv9-de.txt" <<'EOF'
        bp_status, bp_valor = valida_campo(detalhe, "bypass_actors", list, tipo_item=dict)
EOF
cat > "$TMP/mv9-para.txt" <<'EOF'
        bp_status, bp_valor = valida_campo(detalhe, "bypass_actors", list)
EOF
mutante MV9 "guard do ELEMENTO de bypass_actors removido - TypeError nao tratado outra vez" \
  "  nao ha traceback do Python em stderr (c2-elemento)" "$TMP/mv9-de.txt" "$TMP/mv9-para.txt"

# MV10 - A1: reverte a validacao de 'parameters' para a linha exata do defeito em producao -
# `r.get("parameters") or {}`, sem guard nenhum. Um valor truthy nao-dict (string) passa direto;
# o proximo campo lido de `params` (strict_required_status_checks_policy) reporta "ausente" em
# vez de "'parameters' tem tipo inesperado" - a mensagem que nomeia a causa raiz desaparece.
cat > "$TMP/mv10-de.txt" <<'EOF'
        params_status, params = valida_campo(r, "parameters", dict)
        if params_status == FALTANTE:
            # (A1) sem guard, `r.get("parameters") or {}` deixava passar qualquer coisa truthy
            # (uma string, por exemplo) e o primeiro `.get()` seguinte estourava AttributeError.
            nao_medidos.append(
                f"{rotulo}: 'parameters' ausente da regra - strict_required_status_checks_policy "
                f"e o contexto exigido NAO puderam ser lidos desta regra.")
            continue
        if params_status == NULO:
            nao_medidos.append(f"{rotulo}: 'parameters' e null na regra - mesma doutrina de campo ausente.")
            continue
        if params_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"{rotulo}: 'parameters' tem tipo inesperado ({type(params).__name__}, esperava "
                f"objeto) - oraculo malformado, strict_required_status_checks_policy e o "
                f"contexto exigido NAO puderam ser lidos desta regra.")
            continue
EOF
cat > "$TMP/mv10-para.txt" <<'EOF'
        params = r.get("parameters") or {}
EOF
mutante MV10 "'parameters' sem guard - a causa raiz para de ser nomeada" \
  "  motivo cita 'parameters' tipo inesperado" "$TMP/mv10-de.txt" "$TMP/mv10-para.txt"

# MV11 - A2: reverte 'enforcement' para `detalhe.get("enforcement")`, que coage AUSENCIA em
# `None` e fabrica a violacao "enforcement='None'" - o retorno FAIL imediato descarta
# `nao_medidos` (a lacuna real de bypass_actors nem e mencionada), o inverso exato da doutrina.
cat > "$TMP/mv11-de.txt" <<'EOF'
        enf_status, enforcement = valida_campo(detalhe, "enforcement", str)
        if enf_status == FALTANTE:
            # (A2, metade 2) `detalhe.get("enforcement")` coagia a AUSENCIA em `None`, e
            # `enforcement != "active"` fabricava uma violacao ("enforcement='None'") sobre um
            # campo que nao foi medido. Ausencia agora e "nao medido", nunca "medido: inativo".
            nao_medidos.append(
                f"ruleset {rid}: 'enforcement' ausente da resposta - enforcement NAO foi medido "
                f"para este ruleset.")
        elif enf_status == NULO:
            nao_medidos.append(f"ruleset {rid}: 'enforcement' e null na resposta - mesma doutrina de campo ausente.")
        elif enf_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"ruleset {rid}: 'enforcement' tem tipo inesperado ({type(enforcement).__name__}, "
                f"esperava string) - nao medido.")
        elif enforcement != "active":
            # Defesa em profundidade: rules/branches/{branch} ja deveria filtrar por regra
            # ativa. Se um dia esse filtro mudar de comportamento, este probe nao herda a
            # suposicao em silencio.
            problemas.append(f"ruleset {rid} enforcement='{enforcement}' (esperado 'active')")
EOF
cat > "$TMP/mv11-para.txt" <<'EOF'
        enforcement = detalhe.get("enforcement")
        if enforcement != "active":
            problemas.append(f"ruleset {rid} enforcement='{enforcement}' (esperado 'active')")
EOF
mutante MV11 "'enforcement' ausente coagido em violacao fabricada outra vez" \
  "  NAO afirma \"enforcement='None'\" (nao fabrica violacao sobre campo nao medido)" \
  "$TMP/mv11-de.txt" "$TMP/mv11-para.txt"

echo "== mutacao: o QUINTO DEGRAU (wave5, 2026-08-11) - o filtro que alimenta o schema, e ramos de =="
echo "== decisao que existiam SEM caso ate aqui (D3/D4 nao sao defeito de codigo - sao garantia sem teste) =="

# MV12 - (D4a) a deteccao de `enforcement` PRESENTE mas != "active" vira `elif False:`. O codigo
# ja estava correto; nenhum caso isolava esta forma ate V21 (so a AUSENCIA, via A2/V19, tinha
# caso). Kill em V21, nao em V19: sao ramos DIFERENTES do mesmo campo.
cat > "$TMP/mv12-de.txt" <<'EOF'
        elif enforcement != "active":
            # Defesa em profundidade: rules/branches/{branch} ja deveria filtrar por regra
            # ativa. Se um dia esse filtro mudar de comportamento, este probe nao herda a
            # suposicao em silencio.
            problemas.append(f"ruleset {rid} enforcement='{enforcement}' (esperado 'active')")
EOF
cat > "$TMP/mv12-para.txt" <<'EOF'
        elif False:  # MUTANTE (D4a): deteccao de enforcement != active removida
            problemas.append(f"ruleset {rid} enforcement='{enforcement}' (esperado 'active')")
EOF
mutante MV12 "enforcement != active PRESENTE e medido deixa de ser deteccao de violacao" \
  "  motivo cita enforcement='evaluate'" "$TMP/mv12-de.txt" "$TMP/mv12-para.txt"

# MV13 - (D4b) mesma forma para `current_user_can_bypass` PRESENTE mas != "never". Kill em V22.
cat > "$TMP/mv13-de.txt" <<'EOF'
        elif cucb != "never":
            problemas.append(
                f"ruleset {rid}: current_user_can_bypass='{cucb}' (esperado 'never')")
EOF
cat > "$TMP/mv13-para.txt" <<'EOF'
        elif False:  # MUTANTE (D4b): deteccao de current_user_can_bypass != never removida
            problemas.append(
                f"ruleset {rid}: current_user_can_bypass='{cucb}' (esperado 'never')")
EOF
mutante MV13 "current_user_can_bypass != never PRESENTE e medido deixa de ser deteccao de violacao" \
  "  motivo cita current_user_can_bypass='always'" "$TMP/mv13-de.txt" "$TMP/mv13-para.txt"

# MV14 - (D3) reverte a resolucao de 'strict_required_status_checks_policy' para a linha exata do
# defeito de A2 - `bool(params.get(...))`, que coage a AUSENCIA da chave em `False` (uma violacao
# FABRICADA). O codigo ja usava `valida_campo` corretamente; nenhum caso isolava strict ausente/
# nulo/tipo-errado (so `strict:false` EXPLICITO, via V7/V14/V15). Kill em V23.
cat > "$TMP/mv14-de.txt" <<'EOF'
        strict_status, strict_val = valida_campo(params, "strict_required_status_checks_policy", bool)
        if strict_status == FALTANTE:
            # A2 (metade 1): `bool(params.get(...))` coagia a AUSENCIA da chave em `False` - uma
            # violacao FABRICADA, nao medida. Ausencia agora e "nao medido", nunca "medido: false".
            nao_medidos.append(
                f"{rotulo}: 'strict_required_status_checks_policy' ausente de 'parameters' - "
                f"strict NAO foi medido para esta regra.")
        elif strict_status == NULO:
            nao_medidos.append(
                f"{rotulo}: 'strict_required_status_checks_policy' e null - mesma doutrina de campo ausente.")
        elif strict_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"{rotulo}: 'strict_required_status_checks_policy' tem tipo inesperado "
                f"({type(strict_val).__name__}, esperava booleano) - nao medido.")
        else:
            strict_medidos.append(strict_val)
EOF
cat > "$TMP/mv14-para.txt" <<'EOF'
        strict_medidos.append(bool(params.get("strict_required_status_checks_policy")))
EOF
mutante MV14 "strict ausente/nulo/tipo-errado volta a ser coagido em False (violacao fabricada)" \
  "  motivo cita 'strict_required_status_checks_policy' ausente" "$TMP/mv14-de.txt" "$TMP/mv14-para.txt"

# MV15 - (D5) reverte a extracao de 'context' de cada item de 'required_status_checks' para
# `chk.get("context")` - a AUSENCIA da chave (ou um valor null/tipo errado) volta a significar
# silenciosamente "este item nao contribui contexto", sem entrar em `nao_medidos`. Fail-closed na
# DIRECAO (o efeito e um FAIL fabricado, nao um PASS), mas a mesma violacao doutrinaria. Kill em
# V26.
cat > "$TMP/mv15-de.txt" <<'EOF'
        if checks_status is None and checks is not None:
            for j, chk in enumerate(checks):
                # (D5, wave5) `chk.get("context")` tratava a AUSENCIA da chave, o valor `null`
                # explicito e um tipo errado como a MESMA coisa - "este item nao contribui
                # contexto algum" - a mesma coercao de ausencia em conclusao que A2 ja fechou para
                # enforcement/strict, agora sobre o elemento de `required_status_checks`. Fail-
                # closed na DIRECAO (nunca produzia PASS por omissao), mas era a mesma violacao
                # doutrinaria: ausencia nao e medicao, mesmo quando o resultado por omissao e um
                # FAIL fabricado em vez de um PASS fabricado.
                ctx_status, ctx_val = valida_campo(chk, "context", str)
                if ctx_status == FALTANTE:
                    nao_medidos.append(
                        f"{rotulo}: 'required_status_checks[{j}]' sem 'context' - esta regra NAO "
                        f"pode ser confirmada nem descartada como fonte do contexto exigido.")
                elif ctx_status == NULO:
                    nao_medidos.append(
                        f"{rotulo}: 'required_status_checks[{j}].context' e null - mesma doutrina "
                        f"de campo ausente.")
                elif ctx_status == TIPO_INVALIDO:
                    nao_medidos.append(
                        f"{rotulo}: 'required_status_checks[{j}].context' tem tipo inesperado "
                        f"({type(ctx_val).__name__}, esperava string) - nao medido.")
                else:
                    contextos.add(ctx_val)
EOF
cat > "$TMP/mv15-para.txt" <<'EOF'
        if checks_status is None and checks is not None:
            for chk in checks:
                if chk.get("context"):
                    contextos.add(str(chk["context"]))
EOF
mutante MV15 "'context' ausente/nulo/tipo-errado de um item volta a ser silenciosamente ignorado" \
  "  motivo cita 'required_status_checks[0]' sem 'context'" "$TMP/mv15-de.txt" "$TMP/mv15-para.txt"

# MV16 - (D1+D2, O QUINTO DEGRAU) reverte o laco que valida `type` de CADA elemento de `rules`
# (ANTES de decidir se ele entra em `rsc`) para o filtro original de uma linha - que descartava em
# SILENCIO qualquer elemento com `type` ausente/nulo/tipo errado ou nao-dict, sem nunca entrar em
# `nao_medidos` - e para a linha seguinte, que recomputava `tipos` com um list/set comprehension
# sem guard e estourava `TypeError` quando `type` ausente coexistia com um `type` presente.
# Kill designado em V30 (o sinal mais distintivo: ausencia de traceback), mas o mesmo mutante
# tambem quebra V27/V28/V29 (o PASS fabricado sobre 'type' ilegivel volta a acontecer) - a mesma
# forma de MV1 tambem quebrar V19 alem de V4: um mutante pode manifestar em mais de um caso, o que
# importa e que o ALVO designado tenha ROTULO UNICO na suite inteira.
cat > "$TMP/mv16-de.txt" <<'EOF'
    nao_medidos = []
    rsc = []
    tipos_legiveis = []
    for i, r in enumerate(rules):
        if not isinstance(r, dict):
            nao_medidos.append(
                f"elemento #{i + 1} de rules/branches/{branch}: nao e um objeto "
                f"({type(r).__name__}) - nao e possivel determinar se e uma regra "
                f"required_status_checks aplicavel.")
            continue
        tipo_status, tipo_val = valida_campo(r, "type", str)
        if tipo_status == FALTANTE:
            nao_medidos.append(
                f"elemento #{i + 1} de rules/branches/{branch}: 'type' ausente - nao e possivel "
                f"determinar se e uma regra required_status_checks aplicavel (os demais elementos "
                f"legiveis, se aplicavel, continuam sendo medidos).")
            continue
        elif tipo_status == NULO:
            nao_medidos.append(
                f"elemento #{i + 1} de rules/branches/{branch}: 'type' e null - mesma doutrina de "
                f"campo ausente.")
            continue
        elif tipo_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"elemento #{i + 1} de rules/branches/{branch}: 'type' tem tipo inesperado "
                f"({type(tipo_val).__name__}, esperava string) - nao medido.")
            continue
        tipos_legiveis.append(tipo_val)
        if tipo_val == "required_status_checks":
            rsc.append(r)

    if not rsc:
        if nao_medidos:
            # Sem isto, um elemento de `rules` cujo `type` nao pode ser lido faria este ramo
            # concluir `Required(P) = False` (o mesmo FAIL fabricado que A2 ja fechou para
            # enforcement/strict) sem nunca saber se o elemento ilegivel era, ele mesmo, uma regra
            # required_status_checks com bypass aberto - reproduzido: duas regras, a segunda sem
            # `type`, cujo ruleset tinha bypass_actors NAO VAZIO, saiam `PASS exit=0` antes desta
            # correcao porque a regra ilegivel nunca chegava a `rsc`.
            return Resultado(
                NOT_VERIFIED,
                f"Required(P) para '{context}' nao pode ser determinado: nenhum elemento legivel "
                f"de rules/branches/{branch} e 'required_status_checks' (tipos legiveis: "
                f"{sorted(set(tipos_legiveis)) or '(nenhum)'}), mas ao menos um elemento nao pode "
                f"ser classificado e poderia te-lo sido: " + "; ".join(nao_medidos),
                {"rules": rules},
            )
        return Resultado(
            FAIL,
            f"Applies(P,r) = True (regras aplicaveis: {sorted(set(tipos_legiveis))}), mas nenhuma "
            f"e 'required_status_checks' - Required(P) = False para '{branch}'.",
            {"rules": rules},
        )

    # `problemas` nasce AQUI, antes do laco sobre `rsc` - nao apos ele como nas ondas anteriores.
    # `nao_medidos` ja nasceu ACIMA, antes do filtro que produziu `rsc`, e persiste por todo o
    # resto da funcao. C1 e A1 (ruleset_id/parameters ausentes ou malformados em PARTE das regras
    # aplicaveis) sao lacunas de medicao que acontecem DENTRO deste laco, e precisam do MESMO
    # acumulador que o resto do arquivo usa: uma entrada aqui nunca faz este laco `return` cedo,
    # pela mesma razao ja documentada para o laco de rulesets abaixo - um `return` descartaria uma
    # violacao de `strict` ja medida numa regra ANTERIOR do mesmo laco.
    problemas = []
    # (wave8) SUBCONJUNTO de `nao_medidos` - ver o docstring de `resolve_bypass`. Nasce aqui, no
    # mesmo ponto que `problemas`, porque os dois pontos de chamada de `resolve_bypass` abaixo
    # (C-1 e o normal) precisam do MESMO acumulador.
    medicao_parcial = []
    contextos = set()
    strict_medidos = []
    ruleset_ids = set()
EOF
cat > "$TMP/mv16-para.txt" <<'EOF'
    rsc = [r for r in rules if isinstance(r, dict) and r.get("type") == "required_status_checks"]
    if not rsc:
        tipos = sorted({r.get("type") for r in rules if isinstance(r, dict)})
        return Resultado(
            FAIL,
            f"Applies(P,r) = True (regras aplicaveis: {tipos}), mas nenhuma e "
            f"'required_status_checks' - Required(P) = False para '{branch}'.",
            {"rules": rules},
        )

    problemas = []
    nao_medidos = []
    medicao_parcial = []
    contextos = set()
    strict_medidos = []
    ruleset_ids = set()
EOF
mutante MV16 "'type' ausente/nulo/nao-dict volta a ser descartado em silencio; type misto crasha" \
  "  nao ha traceback do Python em stderr (rsc-vazio-tipo-misto)" "$TMP/mv16-de.txt" "$TMP/mv16-para.txt"

echo "== mutacao: a SEXTA onda (2026-08-11) - precedencia mascarada ANTES do laco de rulesets =="

# MV17 - reverte o bloco `if not ruleset_ids:` para a forma SEM o `if problemas` que a onda 6
# introduziu: o `return NOT_VERIFIED` volta a rodar incondicionalmente, descartando uma violacao
# de `strict_required_status_checks_policy` ja medida no laco sobre `rsc`, ANTES deste ponto - o
# DEFEITO VIVO exato que a onda 6 corrige. Kill em V32.
cat > "$TMP/mv17-de.txt" <<'EOF'
    if not ruleset_ids:
        if problemas:
            # Mesma precedencia: nenhuma regra aplicavel declarou 'ruleset_id' valido, logo
            # bypass_actors/enforcement nunca poderiam ser resolvidos - mas isso e irrelevante
            # quando `problemas` ja prova uma violacao por outro caminho. Neste ponto do laco,
            # SO `strict_required_status_checks_policy` pode estar em `problemas`: not Bypass(a,P)
            # (bypass_actors, current_user_can_bypass) e enforcement dependem do laco de rulesets
            # logo abaixo, que ainda nao rodou - nomear "Bypass(a,P)" aqui seria afirmar uma
            # medicao que nao aconteceu. `strict` e uma condicao de FAIL DISTINTA de not Bypass(a,P)
            # (ver docstring), mas ja basta para Gate(P,a,r) = False. O DEFEITO desta rodada era
            # exatamente este `return NOT_VERIFIED` rodando ANTES da agregacao de `strict_medidos`
            # (ver comentario acima); com a agregacao movida para antes deste ponto, o `if
            # problemas` decide primeiro, como em qualquer outro lugar deste arquivo em que FAIL
            # vence NOT_VERIFIED. (A3) Este `return` tambem preserva `nao_medidos` na mensagem -
            # antes, so `problemas` era relatado, e a razao pela qual `ruleset_ids` ficou vazio
            # (a propria entrada de 'ruleset_id' ausente/nulo/invalido) desaparecia do relatorio.
            return Resultado(
                FAIL,
                "Applies(P,r) e Required(P) valem, e a politica de atualizacao "
                "(strict_required_status_checks_policy) ja medida decide Gate(P,a,r) = False, "
                "independente de nenhuma regra aplicavel ter declarado 'ruleset_id' valido para "
                "resolver bypass_actors/enforcement: " + "; ".join(problemas)
                + ("; " + "; ".join(nao_medidos) if nao_medidos else ""),
                {"rules": rules},
            )
        return Resultado(
EOF
cat > "$TMP/mv17-para.txt" <<'EOF'
    if not ruleset_ids:
        return Resultado(
EOF
mutante MV17 "'ruleset_id' irresolvivel volta a mascarar strict ja medido - NOT_VERIFIED fabricado" \
  "  NAO relata NOT_VERIFIED (ruleset_id ausente nao rebaixa violacao ja provada)" \
  "$TMP/mv17-de.txt" "$TMP/mv17-para.txt"

# MV18 - mesma forma, PONTO DE CODIGO DIFERENTE: reverte o bloco `if context not in contextos: if
# nao_medidos:` para SEM o `if problemas`, descartando a mesma classe de violacao ja medida quando
# Required(P) fica indeterminado por uma regra ilegivel, em vez de ruleset_id irresolvivel. Kill
# em V33 - precisa de mutante proprio pela mesma razao que MV5/MV6 precisaram: um unico mutante em
# um dos dois pontos nao prova que o OUTRO tambem foi corrigido.
#
# REANCORADO (wave7, C-1): o `troca` original terminava em "# Sem isto, uma regra aplicavel
# ILEGIVEL..." - texto que agora fica ATRAS do bloco novo `if ruleset_ids: resolve_bypass(...)`
# (C-1). O ANCORA foi encurtado para nao incluir esse texto (evita reescrever o bloco C-1 dentro
# do proprio mutante); o EFEITO do mutante MUDOU e foi RECONFERIDO, nao presumido: sem este guard,
# V33 (dois `ruleset_id` validos, 501/502) cai no bloco `if ruleset_ids:` novo em vez de retornar
# direto - ainda chega a FAIL (a violacao de strict sobrevive DENTRO de `problemas`, que o bloco
# novo tambem consulta), mas so DEPOIS de consultar rulesets/501 e rulesets/502 sem necessidade -
# a MESMA garantia (strict ja medido nao pode ser descartado) agora se manifesta como uma chamada
# de rede EVITAVEL, nao mais como NOT_VERIFIED fabricado.
#
# REANCORADO OUTRA VEZ (wave8): o kill em "NAO chama o endpoint de ruleset" (V33) media um EFEITO
# COLATERAL (a chamada de rede evitavel), nao a SEVERIDADE. Medido pelo portao final: V33 usa DOIS
# `ruleset_id` validos (501/502) - apos esta mutacao, o codigo cai no bloco `if ruleset_ids:` (C-1)
# e a violacao de strict sobrevive DENTRO de `problemas`, resgatada pelo `if problemas:` que roda
# DEPOIS de `resolve_bypass` (linha alguns blocos abaixo) - V33 ainda sai `estado: FAIL exit=1`,
# so com uma chamada de rede a mais e a REDACAO da mensagem trocada (agora cita "Bypass(a,P) ou a
# politica de atualizacao", a prosa do OUTRO bloco). NENHUM caso da suite ate wave8 isola o
# sub-caso em que a SEVERIDADE de fato degrada: uma UNICA regra aplicavel, 'ruleset_id' AUSENTE
# (logo `ruleset_ids` VAZIO - nao ha um segundo ruleset_id valido que resgate via o bloco C-1) +
# strict=false JA MEDIDO + contexto DIVERGENTE. Sem este guard, o bloco `if ruleset_ids:` (vazio)
# nunca executa, e o codigo cai direto no `return NOT_VERIFIED` seguinte - a violacao de strict,
# achada em `problemas`, e SILENCIOSAMENTE descartada: `estado: FAIL exit=1` (probe original) vira
# `estado: NOT_VERIFIED exit=2` (mutado) - o DEFEITO VIVO exato que esta onda fecha, reproduzido
# em V43. Kill mudado do efeito colateral (rede) para a SEVERIDADE (exit code); verificado
# empiricamente (aplicar so este `troca` e rodar a suite) antes de fixar o alvo, nao presumido.
cat > "$TMP/mv18-de.txt" <<'EOF'
            if problemas:
                # Mesma precedencia do portao final (`if problemas` mais abaixo, apos o laco de
                # rulesets): uma violacao ja PROVADA decide Gate(P,a,r) = False sem depender de
                # Required(P) ficar determinado. Neste ponto do laco, SO
                # `strict_required_status_checks_policy` pode estar em `problemas` - bypass_actors/
                # enforcement/current_user_can_bypass dependem do laco de rulesets, que ainda nao
                # rodou; nomear "Bypass(a,P)" aqui afirmaria uma medicao que nao aconteceu. As duas
                # hipoteses para a regra ilegivel levam ao mesmo resultado: se ela NAO exigia
                # `context`, Required(P) = False ja decide FAIL sozinho; se ela EXIGIA `context`,
                # Required(P) = True e o strict ja violado decide Gate(P,a,r) = False por si so
                # (uma condicao de FAIL DISTINTA de not Bypass(a,P), ver docstring), FAIL de novo.
                # NOT_VERIFIED aqui descreveria uma incerteza que nao existe.
                return Resultado(
                    FAIL,
                    f"Applies(P,r) vale e a politica de atualizacao "
                    f"(strict_required_status_checks_policy) ja medida decide Gate(P,a,r) = False, "
                    f"independente de Required(P) para '{context}' ficar "
                    f"indeterminado (regra required_status_checks aplicavel ilegivel: "
                    + "; ".join(nao_medidos) + "): " + "; ".join(problemas),
                    {"rules": rules},
                )
EOF
: > "$TMP/mv18-para.txt"
mutante MV18 "Required(P) indeterminado volta a exigir consulta evitavel ao ruleset - strict ja medido nao decide mais sozinho" \
  "exit code 1 (severidade: violacao ja medida nao pode virar NOT_VERIFIED, v43)" \
  "$TMP/mv18-de.txt" "$TMP/mv18-para.txt"

# MV19 - o DEFEITO OPOSTO de MV17, no MESMO bloco: o guard `if problemas` vira `if True:` - o
# bloco `if not ruleset_ids:` passa a retornar FAIL SEMPRE, mesmo sem nenhuma violacao medida.
# Achado ao validar por mutacao NESTA sessao: sobrevivia aos 127 casos V1-V33 ate V34 ser
# adicionado. Kill em V34.
cat > "$TMP/mv19-de.txt" <<'EOF'
    if not ruleset_ids:
        if problemas:
EOF
cat > "$TMP/mv19-para.txt" <<'EOF'
    if not ruleset_ids:
        if True:  # MUTANTE: 'ruleset_id' irresolvivel vira FAIL fabricado mesmo sem violacao
EOF
mutante MV19 "'ruleset_id' irresolvivel vira FAIL fabricado mesmo SEM violacao medida" \
  "  NAO relata estado FAIL (sem violacao medida, nao pode fabricar FAIL)" \
  "$TMP/mv19-de.txt" "$TMP/mv19-para.txt"

echo "== mutacao: D6 (wave6b) - a metade ESPELHADA de D5 removida do container 'required_status_checks' =="

# MV20 - reverte os ramos FALTANTE/NULO/TIPO_INVALIDO do CONTAINER 'required_status_checks' (a
# lista inteira dentro de 'parameters', nao o elemento) para o comentario original: "apenas
# significa que esta regra nao contribui contexto algum - a mesma consequencia de uma lista
# vazia". Container ausente/nulo/tipo errado volta a cair em silencio, sem entrar em
# `nao_medidos` - o mesmo `Required(P) = False` FABRICADO que D6 fecha. Kill em V35.
cat > "$TMP/mv20-de.txt" <<'EOF'
        elif checks_status == ITEM_INVALIDO:
            idx, item = checks
            nao_medidos.append(
                f"{rotulo}: 'required_status_checks[{idx}]' tem tipo inesperado "
                f"({type(item).__name__}, esperava objeto) - o contexto desta regra NAO pode "
                f"ser lido por completo.")
        elif checks_status == FALTANTE:
            # (D6, achado C1 da revisao independente, wave6b) a metade ESPELHADA de D5: D5 fechou
            # o CAMPO 'context' de cada ITEM da lista; o proprio CONTAINER 'required_status_checks'
            # (a lista em si) nunca tinha guard - ausente/nulo/tipo errado eram tratados como "esta
            # regra nao contribui contexto algum", a MESMA consequencia de uma lista vazia. Uma
            # lista vazia E medicao (a regra foi lida por completo e nao exige nada); um container
            # ausente/nulo/de outro tipo NAO mede nada - a regra PODERIA ter exigido o contexto e
            # nao foi possivel confirmar nem descartar isso.
            nao_medidos.append(
                f"{rotulo}: 'required_status_checks' ausente de 'parameters' - esta regra NAO "
                f"pode ser confirmada nem descartada como fonte do contexto exigido.")
        elif checks_status == NULO:
            nao_medidos.append(
                f"{rotulo}: 'required_status_checks' e null em 'parameters' - mesma doutrina de "
                f"campo ausente.")
        elif checks_status == TIPO_INVALIDO:
            nao_medidos.append(
                f"{rotulo}: 'required_status_checks' tem tipo inesperado "
                f"({type(checks).__name__}, esperava lista) - esta regra NAO pode ser confirmada "
                f"nem descartada como fonte do contexto exigido.")
        # Uma LISTA VAZIA (checks_status is None, checks == []) e a UNICA forma que ainda significa
        # "esta regra nao contribui contexto algum": o `for` acima simplesmente nao itera, e isso E
        # medicao - a lista existe, e do tipo certo, e nao tem elemento nenhum. O CAMPO 'context' de
        # cada item da lista passa pela mesma validacao de schema que qualquer outro campo decisivo
        # (ver acima).
EOF
cat > "$TMP/mv20-para.txt" <<'EOF'
        elif checks_status == ITEM_INVALIDO:
            idx, item = checks
            nao_medidos.append(
                f"{rotulo}: 'required_status_checks[{idx}]' tem tipo inesperado "
                f"({type(item).__name__}, esperava objeto) - o contexto desta regra NAO pode "
                f"ser lido por completo.")
        # FALTANTE/NULO/TIPO_INVALIDO de 'required_status_checks' (a LISTA em si) apenas significa
        # que esta regra nao contribui contexto algum - a mesma consequencia de uma lista vazia,
        # que ja nao era um defeito antes desta correcao. O CAMPO 'context' de cada item da lista
        # passa pela mesma validacao de schema que qualquer outro campo decisivo (ver acima).
EOF
mutante MV20 "container 'required_status_checks' ilegivel volta a cair em silencio - FAIL fabricado" \
  "  motivo cita 'required_status_checks' ausente de 'parameters'" \
  "$TMP/mv20-de.txt" "$TMP/mv20-para.txt"

echo "== mutacao: A-1 (achado da revisao independente, wave7) - dois mutantes ausentes SOBREVIVIAM =="
echo "== a suite discriminava so o PAYLOAD ('; '.join(problemas)), nunca a PROSA nem a itemizacao =="

# MV21 - MUT-A1a: reverte a PROSA do bloco `if not ruleset_ids: if problemas:` para a forma
# GENERICA "Bypass(a,P) ou a politica de atualizacao" - a mesma frase que so e verdadeira DEPOIS
# que `resolve_bypass` roda. Neste ponto do codigo, `resolve_bypass` NUNCA rodou (ruleset_id nunca
# foi resolvido) - nomear Bypass(a,P) aqui afirma uma medicao que nao aconteceu. Achado da revisao
# independente: V32 ja cobria o PAYLOAD (grep por 'strict_required_status_checks_policy', emitido
# por `problemas` independente da prosa), nunca a prosa - este mutante sobrevivia aos 155 casos
# anteriores. Kill na asercao NEGATIVA nova de V32.
cat > "$TMP/mv21-de.txt" <<'EOF'
                "Applies(P,r) e Required(P) valem, e a politica de atualizacao "
                "(strict_required_status_checks_policy) ja medida decide Gate(P,a,r) = False, "
EOF
cat > "$TMP/mv21-para.txt" <<'EOF'
                "Applies(P,r) e Required(P) valem, e uma violacao ja medida (Bypass(a,P) ou a "
                "politica de atualizacao) decide Gate(P,a,r) = False, "
EOF
mutante MV21 "prosa do bloco 'ruleset_id irresolvivel' volta a nomear Bypass(a,P) sem te-lo medido" \
  "  motivo NAO cita 'Bypass(a,P) ou a politica de atualizacao' (nao foi medido neste ponto, v32)" \
  "$TMP/mv21-de.txt" "$TMP/mv21-para.txt"

# MV22 - MUT-A1b: mesma forma, PONTO DE CODIGO DIFERENTE - o bloco `if context not in contextos:
# if nao_medidos: if problemas:`. Kill em V33, pela mesma razao que MV17/MV18 (e MV5/MV6) precisam
# de mutante proprio por ponto de codigo: um unico mutante num dos dois blocos nao prova que o
# OUTRO tambem nomeia o termo certo.
cat > "$TMP/mv22-de.txt" <<'EOF'
                    f"Applies(P,r) vale e a politica de atualizacao "
                    f"(strict_required_status_checks_policy) ja medida decide Gate(P,a,r) = False, "
EOF
cat > "$TMP/mv22-para.txt" <<'EOF'
                    f"Applies(P,r) vale e uma violacao ja medida (Bypass(a,P) ou a politica de "
                    f"atualizacao) decide Gate(P,a,r) = False, "
EOF
mutante MV22 "prosa do bloco 'Required(P) indeterminado' volta a nomear Bypass(a,P) sem te-lo medido" \
  "  motivo NAO cita 'Bypass(a,P) ou a politica de atualizacao' (nao foi medido neste ponto, v33)" \
  "$TMP/mv22-de.txt" "$TMP/mv22-para.txt"

# MV23 - MUT-A3: remove a itemizacao de `nao_medidos` do bloco `if not ruleset_ids: if problemas:`
# - a razao pela qual 'ruleset_id' ficou vazio desaparece do relatorio, so `problemas` (o strict)
# fica visivel. Achado da revisao independente: nenhum caso verificava esta itemizacao ate aqui.
cat > "$TMP/mv23-de.txt" <<'EOF'
                "resolver bypass_actors/enforcement: " + "; ".join(problemas)
                + ("; " + "; ".join(nao_medidos) if nao_medidos else ""),
EOF
cat > "$TMP/mv23-para.txt" <<'EOF'
                "resolver bypass_actors/enforcement: " + "; ".join(problemas),
EOF
mutante MV23 "itemizacao de nao_medidos desaparece do FAIL - razao do ruleset_id vazio some do relatorio" \
  "  motivo cita 'ruleset_id' ausente (A3: nao_medidos preservado no FAIL)" \
  "$TMP/mv23-de.txt" "$TMP/mv23-para.txt"

echo "== mutacao: C-1 (O SETIMO DEGRAU, wave7) - Bypass(a,P) deixa de ser resolvido quando =="
echo "== Required(P) fica indeterminado, mesmo com ruleset_id resolvivel =="

# MV24 - reverte o NOVO bloco `if ruleset_ids: resolve_bypass(...); if problemas: return FAIL` para
# nada: o ramo `if context not in contextos: if nao_medidos:` volta a ir direto para NOT_VERIFIED
# sem NUNCA consultar rulesets/{id}, mesmo com 'ruleset_id' resolvivel - o DEFEITO VIVO exato que
# esta onda corrige (reproduzido em V40).
cat > "$TMP/mv24-de.txt" <<'EOF'
            if ruleset_ids:
                detalhes_rulesets = resolve_bypass(
                    owner, repo, ruleset_ids, nao_medidos, problemas, medicao_parcial)
                if problemas:
                    return Resultado(
                        FAIL,
                        f"Applies(P,r) vale e uma violacao ja medida (Bypass(a,P) ou a politica "
                        f"de atualizacao) decide Gate(P,a,r) = False, independente de Required(P) "
                        f"para '{context}' ficar indeterminado (regra required_status_checks "
                        f"aplicavel ilegivel: " + "; ".join(nao_medidos) + "): "
                        + "; ".join(problemas),
                        {"rules": rules, "rulesets": detalhes_rulesets},
                    )
EOF
: > "$TMP/mv24-para.txt"
mutante MV24 "C-1: NOT_VERIFIED volta a ser devolvido sem NUNCA consultar rulesets/{id}" \
  "  CHAMA o endpoint de ruleset (a correcao consulta antes de decidir NOT_VERIFIED)" \
  "$TMP/mv24-de.txt" "$TMP/mv24-para.txt"

echo "== mutacao: A-3 (wave7) - predicado de agregacao de strict, confirmado contra fonte primaria =="

# MV25 - restaura `not all(strict_medidos)`: uma UNICA regra aplicavel com strict=false volta a
# reprovar mesmo com outra regra aplicavel em strict=true - o FALSO POSITIVO que a fonte primaria
# ("About rule layering", ver comentario no probe) desmente. Kill em V41 ([True, False]).
cat > "$TMP/mv25-de.txt" <<'EOF'
    if strict_medidos and not any(strict_medidos):
EOF
cat > "$TMP/mv25-para.txt" <<'EOF'
    if not all(strict_medidos):
EOF
mutante MV25 "predicado volta a 'not all' - strict=false de UMA regra reprova mesmo com outra em true" \
  "  NAO relata estado FAIL (nao fabrica violacao de strict so por haver um strict=false)" \
  "$TMP/mv25-de.txt" "$TMP/mv25-para.txt"

# MV26 - remove SO o guard `strict_medidos and`, deixando `not any(strict_medidos)` sozinho. Ao
# contrario do guard antigo (S3, `all([])` vacuamente `True` - termo morto), este guard NAO e
# vacuo: `any([])` e vacuamente `False`, entao `not any([])` e `True` sem o guard - fabricaria
# violacao quando NENHUMA regra aplicavel teve strict genuinamente medido (V23: strict ausente).
cat > "$TMP/mv26-de.txt" <<'EOF'
    if strict_medidos and not any(strict_medidos):
EOF
cat > "$TMP/mv26-para.txt" <<'EOF'
    if not any(strict_medidos):
EOF
mutante MV26 "guard 'strict_medidos and' removido - lista vazia (nada medido) vira violacao fabricada" \
  "  NAO relata estado FAIL (guard 'strict_medidos and': lista vazia nao e violacao fabricada)" \
  "$TMP/mv26-de.txt" "$TMP/mv26-para.txt"

echo "== mutacao: O OITAVO DEGRAU (wave8) - MEDICAO PARCIAL DECLARADA vs lacuna geral =="

# MV27 - remove POR COMPLETO o carve-out de MEDICAO PARCIAL: 'bypass_actors' ausente volta a ser
# SEMPRE lacuna geral, mesmo quando 'current_user_can_bypass'='never' foi medido para o ator
# autenticado. Reproduz o defeito VIVO exato que esta onda fecha (o CI nunca ficava verde sob
# GITHUB_TOKEN/contents:read) - sem este mutante, a distincao entre as duas lacunas poderia ser
# removida em silencio e a suite continuaria verde.
cat > "$TMP/mv27-de.txt" <<'EOF'
        if bp_status == FALTANTE:
            # (wave8, O OITAVO DEGRAU) `current_user_can_bypass` e o campo que o SERVIDOR calcula
            # e devolve PARA O ATOR AUTENTICADO, sem exigir acesso de escrita ao ruleset (ao
            # contrario de `bypass_actors`, a LISTA completa - ver o docstring desta funcao).
            # Segunda leitura, PURA, do mesmo `valida_campo` ja chamado abaixo na posicao normal
            # (sem efeito colateral - so verifica, nao substitui a validacao de baixo): se o
            # servidor ja confirma 'never' PARA ESTE ator, not Bypass(a,P) foi MEDIDO POR
            # COMPLETO para ele - MEDICAO PARCIAL DECLARADA, nao lacuna geral (a lacuna que sobra,
            # bypass concedido a OUTRO ator/role, e nomeada explicitamente, nunca escondida).
            cucb_pre_status, cucb_pre = valida_campo(detalhe, "current_user_can_bypass", str)
            if cucb_pre_status is None and cucb_pre == "never":
                msg = (
                    f"ruleset {rid}: 'bypass_actors' ausente da resposta (a API so devolve este "
                    f"campo a quem tem acesso de escrita ao ruleset), mas "
                    f"'current_user_can_bypass'='never' foi medido para o ator autenticado - "
                    f"MEDICAO PARCIAL DECLARADA de not Bypass(a,P), nao lacuna geral: bypass "
                    f"concedido a OUTRO ator/role nao pode ser descartado por este probe sob "
                    f"este token.")
                nao_medidos.append(msg)
                medicao_parcial.append(msg)
            else:
                nao_medidos.append(
                    f"ruleset {rid}: 'bypass_actors' ausente da resposta - not Bypass(a,P) NAO "
                    f"foi medido. A API so devolve este campo a quem tem acesso de escrita ao "
                    f"ruleset.")
EOF
cat > "$TMP/mv27-para.txt" <<'EOF'
        if bp_status == FALTANTE:
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' ausente da resposta - not Bypass(a,P) NAO foi "
                f"medido. A API so devolve este campo a quem tem acesso de escrita ao ruleset.")
EOF
mutante MV27 "carve-out de MEDICAO PARCIAL removido - bypass_actors ausente volta a ser SEMPRE lacuna geral" \
  "relata estado PASS_PARCIAL (nunca PASS puro, nunca NOT_VERIFIED)" \
  "$TMP/mv27-de.txt" "$TMP/mv27-para.txt"

# MV28 - quebra o INVARIANTE de subconjunto (`medicao_parcial` SEMPRE tambem entra em
# `nao_medidos` - ver o docstring de `resolve_bypass`): a entrada tolerada passa a entrar SO em
# `medicao_parcial`, nunca em `nao_medidos`. Para V4 (unico ruleset, unica lacuna), isto esvazia
# `nao_medidos` por completo - o bloco `if nao_medidos:` (que envolve o proprio ramo PASS_PARCIAL)
# nunca e alcancado, e o probe cai direto no PASS puro incondicional do fim da funcao: a
# LIMITACAO desaparece do relatorio, exatamente o "PASS silencioso sobre o residuo" que a
# doutrina do OITAVO DEGRAU proibe.
cat > "$TMP/mv28-de.txt" <<'EOF'
                nao_medidos.append(msg)
                medicao_parcial.append(msg)
EOF
cat > "$TMP/mv28-para.txt" <<'EOF'
                medicao_parcial.append(msg)
EOF
mutante MV28 "invariante de subconjunto quebrado - medicao_parcial sem entrada correspondente em nao_medidos vira PASS silencioso" \
  "  NAO relata estado PASS puro (a limitacao tem de ficar nomeada, nao escondida)" \
  "$TMP/mv28-de.txt" "$TMP/mv28-para.txt"

# MV29 - enfraquece o guard final de PASS_PARCIAL: `if medicao_parcial:` (removendo a comparacao
# de tamanho) aceita qualquer traco de medicao parcial, mesmo quando OUTRA lacuna, sem relacao
# com bypass_actors/current_user_can_bypass (ex.: 'enforcement' ausente, V19), coexiste em
# `nao_medidos`. Reproduz o defeito OPOSTO de MV27: nao "lacuna vira PASS fabricado por omissao",
# e sim "lacuna GERAL vira PASS_PARCIAL fabricado por presenca de ALGUM traco tolerado" -
# precisamente o que a comparacao de tamanho existe para proibir.
cat > "$TMP/mv29-de.txt" <<'EOF'
        if medicao_parcial and len(nao_medidos) == len(medicao_parcial):
EOF
cat > "$TMP/mv29-para.txt" <<'EOF'
        if medicao_parcial:
EOF
mutante MV29 "guard final enfraquecido - qualquer traco de medicao parcial vira PASS_PARCIAL mesmo com outra lacuna coexistindo" \
  "exit code 2 (nao 1 - a ausencia nao e mais coagida em violacao)" \
  "$TMP/mv29-de.txt" "$TMP/mv29-para.txt"

cp -f "$TMP/orig.py" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
