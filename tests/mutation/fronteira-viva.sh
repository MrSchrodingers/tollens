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
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=7

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

# MV1 - O MUTANTE CENTRAL. Reverte a ausencia de 'bypass_actors' para a linha EXATA do defeito em
# producao: `detalhe.get("bypass_actors") or []`. Isto colapsa "campo nao devolvido" (falta de
# acesso de escrita ao ruleset) em "medido: []" - o PASS fabricado que a revisao independente
# encontrou contra github/docs.
cat > "$TMP/mv1-de.txt" <<'EOF'
        if "bypass_actors" not in detalhe:
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' ausente da resposta - not Bypass(a,P) NAO foi "
                f"medido. A API so devolve este campo a quem tem acesso de escrita ao ruleset.")
        elif detalhe["bypass_actors"] is None:
            # Mesma doutrina da chave ausente, um passo adiante: um valor `null` EXPLICITO
            # tambem nao e "medido: []". `atores = detalhe["bypass_actors"] or []` colapsava os
            # dois casos no mesmo PASS fabricado que a correcao anterior fechou so para a chave
            # ausente - a INSTANCIA foi corrigida, a CLASSE (valor nulo) continuava aberta.
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' e null na resposta - not Bypass(a,P) NAO foi "
                f"medido (mesma doutrina de campo ausente).")
        elif not isinstance(detalhe["bypass_actors"], list):
            # Tipo inesperado (ex.: string, numero): sem este guard, `**a` sobre um elemento que
            # nao e mapeamento (ou a propria iteracao sobre uma string) produz TypeError nao
            # tratado - a mesma promessa de "nunca traceback" que ja valia para o OBJETO
            # `detalhe`, agora tambem para este CAMPO dele.
            nao_medidos.append(
                f"ruleset {rid}: 'bypass_actors' tem tipo inesperado "
                f"({type(detalhe['bypass_actors']).__name__}, esperava lista) - oraculo "
                f"malformado, not Bypass(a,P) NAO foi medido.")
        else:
            atores = detalhe["bypass_actors"]
            if atores:
                bypass_total.extend({"ruleset_id": rid, **a} for a in atores)
EOF
cat > "$TMP/mv1-para.txt" <<'EOF'
        atores = detalhe.get("bypass_actors") or []
        if atores:
            bypass_total.extend({"ruleset_id": rid, **a} for a in atores)
EOF
mutante MV1 "campo ausente vira PASS fabricado outra vez ('or []' sobre bypass_actors)" \
  "  motivo cita 'bypass_actors' ausente" "$TMP/mv1-de.txt" "$TMP/mv1-para.txt"

# MV2 - mesma doutrina, segundo campo: current_user_can_bypass ausente volta a ser aceito como
# "never" por omissao (`cucb not in (None, "never")`), em vez de NOT_VERIFIED.
cat > "$TMP/mv2-de.txt" <<'EOF'
        if "current_user_can_bypass" not in detalhe:
            nao_medidos.append(
                f"ruleset {rid}: 'current_user_can_bypass' ausente da resposta - not Bypass(a,P) "
                f"NAO foi medido para o ator autenticado (mesma doutrina de 'bypass_actors': "
                f"ausencia nao e 'never').")
        else:
            cucb = detalhe["current_user_can_bypass"]
            if cucb != "never":
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

# MV3 - o type-guard sobre a resposta de rulesets/{id} some. `detalhe.get(...)` sobre uma lista
# ou string estoura AttributeError nao tratado: o processo sai com traceback e exit 1 (FAIL) em
# vez de exit 2 (NOT_VERIFIED) - o mesmo defeito de "oraculo malformado vira FAIL" que a linha
# `rules` ja evitava, e `detalhe` ainda nao evitava antes desta correcao.
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
mutante MV3 "resposta nao-dict de rulesets/{id} crasha com AttributeError, nao NOT_VERIFIED" \
  "  nao ha traceback do Python em stderr" "$TMP/mv3-de.txt" "$TMP/mv3-para.txt"

# MV4 - a DETECCAO de campo ausente continua populando `nao_medidos`, mas o portao final que a
# transforma em NOT_VERIFIED some. Ponto de codigo DIFERENTE de MV1/MV2 (o guard por-campo
# continua escrito; o que falta e o efeito): prova que a garantia depende de DOIS pontos, nao so
# do primeiro, e que remover so o segundo tambem quebra o veredito.
cat > "$TMP/mv4-de.txt" <<'EOF'
    if nao_medidos:
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
  "  motivo cita 'bypass_actors' ausente" "$TMP/mv4-de.txt" "$TMP/mv4-para.txt"

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
  "  motivo cita 'bypass_actors nao vazio'" "$TMP/mv5-de.txt" "$TMP/mv5-para.txt"

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
  "  motivo cita 'bypass_actors nao vazio'" "$TMP/mv6-de.txt" "$TMP/mv6-para.txt"

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
mutante MV7 "ordem do portao final invertida: nao_medidos passa a vencer problemas" \
  "  NAO relata NOT_VERIFIED (a lacuna de bypass_actors nao decide aqui)" \
  "$TMP/mv7-de.txt" "$TMP/mv7-para.txt"

cp -f "$TMP/orig.py" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
