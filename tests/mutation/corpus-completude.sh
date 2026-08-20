#!/usr/bin/env bash
# VALIDACAO POR MUTACAO DO PORTAO DE COMPLETUDE DO CORPUS.
#
# POR QUE EXISTE. `tests/unit/governance-links.py` passou a exigir que todo achado citado com
# marcador estruturado num ADR exista como `finding_id` em
# `evidence/corpus/agente-x-defeito.json`. A discriminacao dessa regra foi PROVADA A MAO numa
# copia descartavel - e "provado a mao num clone que ninguem reexecuta" e literalmente o defeito
# que o ADR 0033 registrou sobre os sete mutantes da onda 13. Repetir a forma logo depois de
# documenta-la seria o pior tipo de reincidencia.
#
# O QUE A REGRA GARANTE, e por que a consistencia interna nao bastava: o portao ja recontava
# `counts_by_mode` contra as linhas PRESENTES. Um corpus a que faltem achados continua
# perfeitamente consistente consigo mesmo - foi assim que uma conclusao comparativa publicada
# ("a auditoria externa foi o modo mais produtivo") sobreviveu a um portao verde e estava
# invertida. MCC1 e o caso que separa as duas propriedades: ele REMOVE um achado E RECONTA a
# tabela, entao a consistencia interna fica intacta e so a completude reprova.
#
# CADA MUTANTE MUTA O CORPUS OU O ADR, NUNCA O PORTAO.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib/lock.sh
. tests/lib/arena.sh

P=0; F=0; EXPECTED_MUTANTS=7
POR="tests/unit/governance-links.py"
CORPUS="evidence/corpus/agente-x-defeito.json"
ADR="docs/adr/0035-a-divida-era-de-uma-classe-so.md"

# BASELINE. Sem ele todo "MORTO" abaixo poderia ser crash de ambiente em vez de assercao - a
# forma que `tests/mutation/methodology.py` ja pagou nesta mesma semana, matando 16/16 por
# FileNotFoundError com a arvore nao mutada ja reprovando.
if ! python3 "$POR" >/dev/null 2>&1; then
  echo "BASELINE VERMELHO: o portao ja reprova na arvore nao mutada." >&2
  echo "Sem baseline verde, todo 'MORTO' abaixo seria crash e nao assercao - o arnes e VACUO." >&2
  exit 1
fi
echo "baseline verde: o portao sai 0 na arvore nao mutada"

# MCC7 muta um ADR DIFERENTE do de referencia, entao o backup cobre a arvore inteira de ADRs.
_ADRDIR="docs/adr"
_bak(){ cp "$CORPUS" "$CORPUS.bak"; cp -a "$_ADRDIR" "$_ADRDIR.bak"; }
_rst(){ mv -f "$CORPUS.bak" "$CORPUS"; rm -rf "$_ADRDIR"; mv -f "$_ADRDIR.bak" "$_ADRDIR"; }

mutante(){ # $1=nome $2=descricao $3=exit esperado $4=programa python
  local nome="$1" desc="$2" want="$3" prog="$4" got
  _bak
  if ! python3 -c "$prog"; then
    echo "  ERRO  $nome: a mutacao nao aplicou"; F=$((F+1)); _rst; return
  fi
  python3 "$POR" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then echo "  MORTO $nome - $desc (exit=$got)"; P=$((P+1))
  else echo "  SOBREVIVEU $nome - $desc (exit=$got, esperado=$want)"; F=$((F+1)); fi
  _rst
}

_PY='import json,pathlib
from collections import Counter
p=pathlib.Path("evidence/corpus/agente-x-defeito.json"); d=json.loads(p.read_text())
def salvar():
    c=Counter(f["mode"] for f in d["findings"])
    d["counts_by_mode"]={k:c[k] for k in sorted(c)}
    p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")
'

echo "== o caso que separa consistencia de completude =="
mutante MCC1 "achado citado no ADR sumiu do corpus, COM counts_by_mode recontado" 1 \
  "$_PY"'d["findings"]=[f for f in d["findings"] if f.get("finding_id")!="F2"]
salvar()'

echo "== a consistencia interna, que ja era verificada =="
mutante MCC2 "counts_by_mode diverge das linhas presentes" 1 \
  "$_PY"'d["counts_by_mode"]["remedicao"]=d["counts_by_mode"]["remedicao"]+7
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

echo "== o criterio de inclusao =="
mutante MCC3 "corpus sem criterio de inclusao explicito" 1 \
  "$_PY"'d.pop("inclusion_criterion",None)
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

echo "== onda 17: a prosa derivada, e a negativa universal =="
# A completude fechou "faltam linhas". Sobrou a forma menor: o corpus foi de 26 para 47 e a
# PROSA dentro dele continuou dizendo "40 achados". Dado estruturado correto, narrativa derivada
# obsoleta - e o portao antigo, que so reconferia counts_by_mode, nao via numeral em texto.
mutante MCC5 "prosa cita contagem que nao bate com os dados" 1 \
  "$_PY"'d["limits"][0]="N PEQUENO. Sao 40 achados de uma sessao."
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

# CONTROLE DE DIRECAO: numeral HISTORICO e legitimo. O corpus precisa poder dizer "a primeira
# versao trazia 26 achados" sem que isso vire violacao, senao a regra proibiria registrar o
# proprio erro - que e o oposto do que este repositorio faz.
mutante MCC6 "CONTROLE: numeral marcado como estado ANTERIOR nao e violacao" 0 \
  "$_PY"'d["limits"][0]="N PEQUENO. A primeira versao trazia 26 achados; hoje sao outros."
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

# NEGATIVA UNIVERSAL SOBRE LITERATURA. O ADR 0033 afirmava "nenhum trabalho conhecido mede
# P(declara sucesso | verificador reprova)" enquanto o ledger do MESMO repositorio registrava o
# paper que mede exatamente isso. Forma inverificavel por construcao: nao se cita evidencia da
# ausencia de toda a literatura.
mutante MCC7 "ADR volta a fazer negativa universal sobre literatura, fora de errata" 1 \
  'import pathlib
p=pathlib.Path("docs/adr/0030-o-verificador-instalado-que-nunca-observou.md")
p.write_text(p.read_text()+"\n\nNenhum trabalho conhecido mede esta propriedade.\n")'

echo "== CONTROLE POSITIVO =="
# Sem ele o portao podia ser `return FAIL` e os tres mutantes acima "morreriam" sem testar nada.
# O caso tambem fixa a direcao da regra: o corpus pode CONTER MAIS do que os ADRs citam - achado
# de onda antiga nao tem ID em ADR nenhum -, e isso nao e violacao. A regra e
# `citados SUBCONJUNTO DE corpus`, nao igualdade.
# O programa atualiza a PROSA junto, que e o que um contribuidor real faz ao acrescentar um
# achado - e o que o portao da onda 17 passou a exigir. Sem isso o controle positivo reprovaria
# pela regra nova, mascarando o que ele existe para medir: que o corpus pode conter MAIS do que
# os ADRs citam.
mutante MCC4 "CONTROLE: achado NOVO nao citado em ADR algum - o portao deve PASSAR" 0 \
  "$_PY"'import re
d["findings"].append({"finding_id":"W99-1","wave":15,"review_round":"medicao",
  "found_by":"aplicacao-de-instrumento","mode":"aplicacao-de-instrumento",
  "class":"controle","defect":"achado sintetico do controle positivo MCC4",
  "source_ref":"tests/mutation/corpus-completude.sh"})
n=len(d["findings"])
for campo in ("limits","reading"):
    d[campo]=[re.sub(r"\b\d+ achados\b",f"{n} achados",re.sub(r"\bN=\d+\b",f"N={n}",s)) for s in d[campo]]
salvar()'

echo
echo "MUTANTES=$((P+F)) ESPERADOS=$EXPECTED_MUTANTS CORRETOS=$P DIVERGENTES=$F"
if [ "$((P+F))" -ne "$EXPECTED_MUTANTS" ]; then
  echo "ERRO: $((P+F)) mutantes executados, $EXPECTED_MUTANTS declarados." >&2
  exit 1
fi
[ "$F" -eq 0 ]
