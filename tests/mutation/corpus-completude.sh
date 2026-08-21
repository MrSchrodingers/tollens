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

P=0; F=0; EXPECTED_MUTANTS=16
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

_PY='import json,pathlib,sys
p=pathlib.Path("evidence/corpus/agente-x-defeito.json"); d=json.loads(p.read_text())
sys.path.insert(0,"evidence/corpus"); import render
def salvar():
    d["derived"]={"_comment":d["derived"]["_comment"],**render.derivar(d["findings"])}
    p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")
'

echo "== o caso que separa consistencia de completude =="
mutante MCC1 "achado citado no ADR sumiu do corpus, COM counts_by_mode recontado" 1 \
  "$_PY"'d["findings"]=[f for f in d["findings"] if f.get("finding_id")!="F2"]
salvar()'

echo "== a consistencia interna, que ja era verificada =="
mutante MCC2 "derived.counts_by_mode diverge das linhas presentes" 1 \
  "$_PY"'d["derived"]["counts_by_mode"]["remedicao"]=d["derived"]["counts_by_mode"]["remedicao"]+7
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

# CONTROLE DE DIRECAO, REESCRITO NA ONDA 18. Ate a onda 17 este caso provava que numeral
# historico em PROSA era absolvido por uma palavra na janela anterior - e foi exatamente essa
# excecao que a auditoria derrubou, mostrando que ela absorvia claim corrente falsa. A excecao
# saiu. O historico nao: ele passou a viver ESTRUTURADO em `historical_states`, e este controle
# prova que registrar o proprio erro continua possivel - que era a preocupacao legitima por tras
# da excecao antiga, agora atendida sem adivinhar intencao a partir de vizinhanca de palavra.
mutante MCC6 "CONTROLE: historico registrado em historical_states nao e violacao" 0 \
  "$_PY"'d["historical_states"].append({"as_of":"onda 17","n_findings":52,"nota":"controle MCC6"})
salvar()'

# NEGATIVA UNIVERSAL SOBRE LITERATURA. O ADR 0033 afirmava "nenhum trabalho conhecido mede
# P(declara sucesso | verificador reprova)" enquanto o ledger do MESMO repositorio registrava o
# paper que mede exatamente isso. Forma inverificavel por construcao: nao se cita evidencia da
# ausencia de toda a literatura.
mutante MCC7 "ADR volta a fazer negativa universal sobre literatura, fora de errata" 1 \
  'import pathlib
p=pathlib.Path("docs/adr/0030-o-verificador-instalado-que-nunca-observou.md")
p.write_text(p.read_text()+"\n\nNenhum trabalho conhecido mede esta propriedade.\n")'

echo "== onda 18: frame derivado, e a excecao que nao e mais autodeclarada =="
# G11 - o frame do corpus e DERIVADO dos findings. Editar `derived` a mao tem de reprovar.
mutante MCC8 "bloco derived editado a mao, divergente dos findings" 1 \
  "$_PY"'d["derived"]["n_findings"]=999
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

# G13 - a excecao lexical foi REMOVIDA. Este e o caso exato que a auditoria mediu passando na
# onda 17: numeral corrente FALSO absolvido por uma palavra na janela anterior.
mutante MCC9 "claim corrente falsa precedida de 'Antes' (a excecao da onda 17 a absolvia)" 1 \
  "$_PY"'d["limits"][0]="Antes de discutir severidade: sao 40 achados no corpus atual."
p.write_text(json.dumps(d,ensure_ascii=False,indent=2)+"\n")'

# G12 - a unica forma autorizada de afirmar ausencia e a busca delimitada. O token de escape da
# onda 17 nao absolve mais: ele era criterio de excecao dentro do objeto governado.
mutante MCC10 "negativa universal reformulada, sem busca delimitada" 1 \
  'import pathlib
p=pathlib.Path("docs/adr/0030-o-verificador-instalado-que-nunca-observou.md")
p.write_text(p.read_text()+"\n\nA literatura ainda nao mede esta propriedade.\n")'

mutante MCC11 "referencia [busca:<id>] que nao resolve para registro algum" 1 \
  'import pathlib
p=pathlib.Path("docs/adr/0030-o-verificador-instalado-que-nunca-observou.md")
p.write_text(p.read_text()+"\n\nNenhum estudo foi encontrado. [busca:BL-9999]\n")'

echo "== onda 19: referencia que resolve, e estado que nao e prosa =="
# G14 - a familia da onda 12 ("referencia publicada que nao resolve") voltando DENTRO do
# instrumento construido para medir a trajetoria de defeitos. O renderer derivava `sources` do
# que foi DECLARADO, sem nada garantir que existisse.
mutante MCC12 "source_ref apontando para arquivo inexistente" 1 \
  "$_PY"'d["findings"][0]["source_ref"]="docs/adr/nao-existe.md"
salvar()'
mutante MCC13 "source_ref escapando do repositorio" 1 \
  "$_PY"'d["findings"][0]["source_ref"]="../../etc/passwd"
salvar()'
# G15 - `open_findings` derivava de texto livre: trocar a string por "corrigido" removia o
# achado dos abertos com tudo consistente. O estado virou enum, e `resolved` exige artefato.
mutante MCC14 "state fora do enum declarado" 1 \
  "$_PY"'d["findings"][0]["state"]="talvez"
salvar()'
mutante MCC15 "resolved apontando para artefato de resolucao inexistente" 1 \
  "$_PY"'d["findings"][0]["state"]="resolved"; d["findings"][0]["resolution_ref"]="docs/adr/nada.md"
salvar()'
mutante MCC16 "open sem dizer o que falta" 1 \
  "$_PY"'f=[x for x in d["findings"] if x["state"]=="open"][0]
f.pop("open_note",None)
salvar()'

echo "== CONTROLE POSITIVO =="
# Sem ele o portao podia ser `return FAIL` e os tres mutantes acima "morreriam" sem testar nada.
# O caso tambem fixa a direcao da regra: o corpus pode CONTER MAIS do que os ADRs citam - achado
# de onda antiga nao tem ID em ADR nenhum -, e isso nao e violacao. A regra e
# `citados SUBCONJUNTO DE corpus`, nao igualdade.
# O programa monta um achado BEM FORMADO segundo o schema corrente - com `state`,
# `resolution_ref` e a prosa atualizada -, que e o que um contribuidor real faz. Este controle ja
# precisou ser reescrito tres vezes conforme o schema apertou (numeral em prosa na onda 17,
# bloco derivado na 18, estado e referencia na 19), e isso e o controle FUNCIONANDO: cada campo
# novo exigido aparece aqui, ou o caso deixa de provar o que promete. Sem isso o controle positivo reprovaria
# pela regra nova, mascarando o que ele existe para medir: que o corpus pode conter MAIS do que
# os ADRs citam.
mutante MCC4 "CONTROLE: achado NOVO nao citado em ADR algum - o portao deve PASSAR" 0 \
  "$_PY"'import re
d["findings"].append({"finding_id":"W99-1","wave":15,"review_round":"medicao",
  "found_by":"aplicacao-de-instrumento","mode":"aplicacao-de-instrumento",
  "class":"controle","defect":"achado sintetico do controle positivo MCC4",
  "state":"resolved","resolution_ref":"tests/mutation/corpus-completude.sh",
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
