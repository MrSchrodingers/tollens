#!/usr/bin/env bash
# SUITE DO NUCLEO QUE JULGA O DELTA (evidence/lint-delta.py).
#
# O valor desta suite esta nos casos que separam "o portao funciona" de "o portao aprova tudo".
# Um portao de delta tem um modo de falha proprio e silencioso: aprovar por nao ter olhado. Cada
# caso positivo aqui tem o negativo correspondente.
set -uo pipefail
. "$(dirname "$0")/../lib/lock.sh"
cd "$(dirname "$0")/../.." || exit 1
LD="evidence/lint-delta.py"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }
rodar(){ python3 "$LD" --diagnostics "$1" --hunks "$2" --baseline "$3" --breakage-codes "$4" 2>/dev/null; }
rc_de(){ python3 "$LD" --diagnostics "$1" --hunks "$2" --baseline "$3" --breakage-codes "$4" >/dev/null 2>&1; echo $?; }

QUEBRA="F821,F811,F822,E999"
HIG='[{"path":"a.py","line":8,"code":"F401","message":"`uuid` imported but unused"}]'
QBR='[{"path":"b.py","line":3,"code":"F821","message":"Undefined name `foo`"}]'

echo "== LD1. higiene FORA das linhas tocadas nao bloqueia =="
# E o caso dos 80 de 86 medidos em /var/www/amaral-intern-hub.
chk "higiene sem hunk naquele arquivo: exit 0" "$(rc_de "$HIG" '{}' '' "$QUEBRA")" 0
chk "  e ela e contada como IGNORADA, nao sumida" \
    "$(rodar "$HIG" '{}' '' "$QUEBRA" | python3 -c 'import json,sys;print(json.load(sys.stdin)["ignorados"])')" 1

echo "== LD2. higiene DENTRO das linhas tocadas bloqueia =="
# CONTROLE NEGATIVO de LD1: sem ele, "nao bloqueou" nao distingue "e alheia" de "nao olhei".
chk "higiene na linha tocada: exit 1" "$(rc_de "$HIG" '{"a.py":[[5,10]]}' '' "$QUEBRA")" 1
chk "  e a faixa e fechada nos dois lados (linha 8 em [8,8])" \
    "$(rc_de "$HIG" '{"a.py":[[8,8]]}' '' "$QUEBRA")" 1
chk "  hunk que NAO cobre a linha nao bloqueia (borda inferior)" \
    "$(rc_de "$HIG" '{"a.py":[[9,20]]}' '' "$QUEBRA")" 0

echo "== LD3. quebra bloqueia em arquivo NAO tocado =="
# A razao de `per_file` sozinho estar errado: remover uma funcao quebra quem a chama, e esse
# arquivo nao esta no diff.
chk "quebra sem hunk nenhum: exit 1" "$(rc_de "$QBR" '{}' '' "$QUEBRA")" 1

echo "== LD4. quebra no BASELINE e tolerada, nao ignorada =="
FP="$(python3 "$LD" --diagnostics "$QBR" --hunks '{}' --breakage-codes "$QUEBRA" --emit-baseline 2>/dev/null)"
chk "o baseline emitido tem 1 digital" "$(printf '%s' "$FP" | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" 1
chk "quebra preexistente nao bloqueia" "$(rc_de "$QBR" '{}' "$FP" "$QUEBRA")" 0
chk "  e ela e REPORTADA em stderr (baseline nao cala)" \
    "$(python3 "$LD" --diagnostics "$QBR" --hunks '{}' --baseline "$FP" --breakage-codes "$QUEBRA" 2>&1 >/dev/null | grep -c 'QUEBRA PREEXISTENTE TOLERADA')" 1
chk "  e contabilizada como tolerada, nao como ignorada" \
    "$(rodar "$QBR" '{}' "$FP" "$QUEBRA" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(str(d["tolerados"])+"/"+str(d["ignorados"]))')" "1/0"

echo "== LD5. quebra NOVA bloqueia mesmo com baseline =="
# Sem este caso, um baseline que casasse tudo passaria por "catraca funcionando".
NOVA='[{"path":"c.py","line":1,"code":"F821","message":"Undefined name `outro`"}]'
chk "quebra fora do baseline: exit 1" "$(rc_de "$NOVA" '{}' "$FP" "$QUEBRA")" 1

echo "== LD6. A DIGITAL SOBREVIVE A DESLOCAMENTO DE LINHA =="
# O ponto sutil do desenho. Casar por (arquivo, linha) faria QUALQUER edicao acima gerar
# falso-novo em massa. Aqui o MESMO defeito aparece na linha 3 e depois na 47.
DESLOCADA='[{"path":"b.py","line":47,"code":"F821","message":"Undefined name `foo`"}]'
chk "mesmo defeito 44 linhas abaixo: continua tolerado" "$(rc_de "$DESLOCADA" '{}' "$FP" "$QUEBRA")" 0
chk "  CONTROLE: defeito de OUTRO simbolo no mesmo arquivo NAO e tolerado" \
    "$(rc_de '[{"path":"b.py","line":3,"code":"F821","message":"Undefined name `bar`"}]' '{}' "$FP" "$QUEBRA")" 1
chk "  CONTROLE: mesmo simbolo em OUTRO arquivo NAO e tolerado" \
    "$(rc_de '[{"path":"z.py","line":3,"code":"F821","message":"Undefined name `foo`"}]' '{}' "$FP" "$QUEBRA")" 1

echo "== LD7. mensagem com contador nao gera falso-novo =="
# `redefinition of unused 'x' from line 3` vira `line #`: senao a digital muda quando o alvo
# se move, que e o mesmo falso-novo pela porta dos fundos.
M1='[{"path":"d.py","line":9,"code":"F811","message":"Redefinition of unused `x` from line 3"}]'
M2='[{"path":"d.py","line":9,"code":"F811","message":"Redefinition of unused `x` from line 51"}]'
B2="$(python3 "$LD" --diagnostics "$M1" --hunks '{}' --breakage-codes "$QUEBRA" --emit-baseline 2>/dev/null)"
chk "numero na mensagem nao muda a digital" "$(rc_de "$M2" '{}' "$B2" "$QUEBRA")" 0

echo "== LD8. falhas de entrada sao NAO VERIFICADO, nunca aprovacao =="
# Um portao que aprova por nao entender a entrada e pior que a ausencia dele.
chk "diagnostics ilegivel -> exit 2" "$(rc_de 'nao e json' '{}' '' "$QUEBRA")" 2
chk "hunks ilegivel -> exit 2"       "$(rc_de "$HIG" 'nao e json' '' "$QUEBRA")" 2
chk "baseline ilegivel -> exit 2"    "$(rc_de "$HIG" '{}' 'nao e json' "$QUEBRA")" 2
chk "diagnostico sem campo -> exit 2" "$(rc_de '[{"path":"a.py","line":1}]' '{}' '' "$QUEBRA")" 2
chk "breakage-codes VAZIO -> exit 2 (senao a arvore deixa de ser olhada)" \
    "$(rc_de "$QBR" '{}' '' ",, ")" 2

echo "== LD9. ANTIVACUIDADE: entrada vazia nao e aprovacao com significado =="
chk "zero diagnosticos: exit 0" "$(rc_de '[]' '{}' '' "$QUEBRA")" 0
chk "  e o relatorio declara zero em TODAS as classes" \
    "$(rodar '[]' '{}' '' "$QUEBRA" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["bloqueiam"]+d["tolerados"]+d["ignorados"])')" 0

echo "== LD10. saida NATIVA do analisador via mapa declarativo =="
# O mapa vem do ADAPTADOR. Embutir os nomes de campo aqui faria cada ferramenta nova exigir
# edicao do nucleo - e e assim que um executor generico vira um executor de ruff.
RAW='[{"filename":"/abs/repo/a.py","location":{"row":8},"code":"F401","message":"`uuid` imported but unused"}]'
MAPA='{"path":"filename","line":"location.row","code":"code","message":"message"}'
nat(){ python3 "$LD" --raw "$1" --map "$2" --strip-prefix "${3:-}" --hunks "${4:-{\}}" --baseline "${5:-}" --breakage-codes "$QUEBRA" "${@:6}"; }
chk "traduz saida nativa e o prefixo absoluto some" \
    "$(nat "$RAW" "$MAPA" '/abs/repo/' '{"a.py":[[8,8]]}' 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["detalhe"][0]["path"])')" "a.py"
chk "  e o veredito usa o caminho JA traduzido (bloqueia no hunk)" \
    "$(python3 "$LD" --raw "$RAW" --map "$MAPA" --strip-prefix '/abs/repo/' --hunks '{"a.py":[[8,8]]}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1
chk "  CONTROLE: sem --strip-prefix o caminho nao casa o hunk e NAO bloqueia" \
    "$(python3 "$LD" --raw "$RAW" --map "$MAPA" --hunks '{"a.py":[[8,8]]}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0
chk "--raw sem --map e NAO VERIFICADO, nao aprovacao" \
    "$(python3 "$LD" --raw "$RAW" --hunks '{}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2
chk "chave do mapa que nao existe na saida -> exit 2" \
    "$(python3 "$LD" --raw "$RAW" --map '{"path":"nao_existe","line":"location.row","code":"code","message":"message"}' --hunks '{}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 2

echo "== LD11. diagnostico em checkout ANINHADO nunca foi objeto do turno =="
# Medido: 87 de 173 em /var/www/amaral-intern-hub vinham de 4 worktrees dentro do repo. Nao e
# escopo semantico nem baseline - aquele codigo nao esta no HEAD do turno.
ANIN='[{"path":".worktrees/outra/x.py","line":3,"code":"F821","message":"Undefined name `z`"}]'
chk "quebra dentro de checkout aninhado NAO bloqueia" \
    "$(python3 "$LD" --diagnostics "$ANIN" --hunks '{}' --nested-roots '[".worktrees/outra"]' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0
chk "  e ela e contada como ALHEIA, nao como ignorada" \
    "$(python3 "$LD" --diagnostics "$ANIN" --hunks '{}' --nested-roots '[".worktrees/outra"]' --breakage-codes "$QUEBRA" 2>/dev/null | python3 -c 'import json,sys;d=json.load(sys.stdin);print(str(d["alheios"])+"/"+str(d["ignorados"]))')" "1/0"
chk "  CONTROLE: a MESMA quebra fora do checkout aninhado bloqueia" \
    "$(python3 "$LD" --diagnostics "$ANIN" --hunks '{}' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1
chk "  CONTROLE: prefixo parcial nao casa ('.worktrees/outra2' != '.worktrees/outra')" \
    "$(python3 "$LD" --diagnostics '[{"path":".worktrees/outra2/x.py","line":3,"code":"F821","message":"Undefined name `z`"}]' --hunks '{}' --nested-roots '[".worktrees/outra"]' --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 1
chk "o baseline NAO grava digital de checkout aninhado" \
    "$(python3 "$LD" --diagnostics "$ANIN" --hunks '{}' --nested-roots '[".worktrees/outra"]' --breakage-codes "$QUEBRA" --emit-baseline 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" 0

echo "== LD12. a SEMEADURA do baseline nao depende de hunks =="
# Regressao real: `--hunks` era obrigatorio e a semeadura nao os passa. O executor engolia o erro
# em `2>/dev/null`, seguia sem baseline, e reprovava por quebra preexistente para sempre. A
# suite unitaria nao via porque sempre passava `--hunks`; quem pegou foi o teste ponta a ponta.
chk "emit-baseline SEM --hunks: exit 0" \
    "$(python3 "$LD" --diagnostics "$QBR" --breakage-codes "$QUEBRA" --emit-baseline >/dev/null 2>&1; echo $?)" 0
chk "  e emite a digital mesmo assim" \
    "$(python3 "$LD" --diagnostics "$QBR" --breakage-codes "$QUEBRA" --emit-baseline 2>/dev/null | python3 -c 'import json,sys;print(len(json.load(sys.stdin)))')" 1
chk "  julgar SEM --hunks trata como zero linhas tocadas (higiene nao bloqueia)" \
    "$(python3 "$LD" --diagnostics "$HIG" --breakage-codes "$QUEBRA" >/dev/null 2>&1; echo $?)" 0

EXPECTED=35
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
echo
echo "================ PASS=$P  FAIL=$F ================"
[ "$F" -eq 0 ] && echo "lint-delta verde ($P/$EXPECTED)" || echo "lint-delta VERMELHO ($F falhas)"
exit "$F"
