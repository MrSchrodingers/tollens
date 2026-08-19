#!/usr/bin/env bash
# VALIDACAO POR MUTACAO DO PORTAO DE CONFORMIDADE DE CAPABILITY.
#
# POR QUE EXISTE, e o achado e do portao final da onda 13.
#
# `tests/unit/capability-conformance.py` nasceu com sete mutantes validando suas assercoes - e
# os sete foram rodados A MAO, num clone descartado no fim da sessao. Nenhum comando deste
# repositorio os reexecutava. A tabela de validacao do ADR 0033 era honesta e IRREPRODUZIVEL, o
# que a torna afirmacao, nao evidencia: ninguem consegue refutar amanha o que so existiu num
# terminal ontem.
#
# Pior, e o portao final mediu: `docs/status.generated.md` registra o exit do portao como VALOR
# numa tabela, nao como condicao. Com o portao reprovando, `scripts/status.sh --check` acusa o
# artefato desatualizado e a instrucao publicada manda regenerar - o que grava `| 15 | 1 |` e
# devolve o `--check` ao verde COM O PORTAO VERMELHO. Enforcement por comparacao de bytes de uma
# tabela e lavavel. Por isso o portao entra tambem em `tests/unit/runtime-ports.sh`, que e passo
# dedicado de CI com propagacao de exit.
#
# Este arnes e `.sh` de proposito: a varredura de completude de `scripts/status.sh` faz
# `for _mf in tests/mutation/*.sh`, e um arnes `.py` nasceria fora do relatorio - a mesma classe
# que o ADR 0029 nomeia como "instrumento escrito e nao reportado".
#
# CADA MUTANTE MUTA O REGISTRY (ou o manifesto), NUNCA O PORTAO. Mutar o verificador provaria
# que ele reage a si mesmo; o que precisa ser provado e que ele reage ao ARTEFATO.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
. tests/lib/lock.sh
. tests/lib/arena.sh

P=0; F=0; EXPECTED_MUTANTS=11
REG="orchestration/registry.json"
LOCK="install/manifest.lock"
POR="tests/unit/capability-conformance.py"

# BASELINE. Sem ele todo "mutante morto" abaixo poderia ser crash de ambiente, e o arnes de
# `tests/mutation/methodology.py` ja pagou exatamente essa forma nesta mesma semana: matava
# 16/16 por FileNotFoundError, com o tester nao mutado ja reprovando.
if ! python3 "$POR" >/dev/null 2>&1; then
  echo "BASELINE VERMELHO: o portao ja reprova na arvore nao mutada." >&2
  echo "Sem baseline verde, todo 'MORTO' abaixo seria crash e nao assercao - o arnes e VACUO." >&2
  exit 1
fi
echo "baseline verde: portao sai 0 na arvore nao mutada"

_bak(){ cp "$REG" "$REG.bak"; cp "$LOCK" "$LOCK.bak"; }
_rst(){ mv -f "$REG.bak" "$REG"; mv -f "$LOCK.bak" "$LOCK"; }

mutante(){ # $1=nome $2=descricao $3=exit esperado $4=script python de mutacao
  local nome="$1" desc="$2" want="$3" prog="$4" got
  _bak
  python3 -c "$prog" || { echo "  ERRO  $nome: mutacao falhou"; F=$((F+1)); _rst; return; }
  python3 "$POR" >/dev/null 2>&1; got=$?
  if [ "$got" -eq "$want" ]; then echo "  MORTO $nome - $desc (exit=$got)"; P=$((P+1))
  else echo "  SOBREVIVEU $nome - $desc (exit=$got, esperado=$want)"; F=$((F+1)); fi
  _rst
}

_PY='import json,pathlib
p=pathlib.Path("orchestration/registry.json"); r=json.loads(p.read_text()); c=r["capabilities"]
'
_SAVE='
p.write_text(json.dumps(r,ensure_ascii=False,indent=2))'

echo "== mutantes do lifecycle =="
mutante MCAP1 "promoted sem dossie reprova" 1 \
  "$_PY"'c["graphify"]["state"]="promoted"'"$_SAVE"

mutante MCAP2 "dossie cobrindo 2 dos 7 requisitos reprova" 1 \
  "$_PY"'
import os
os.makedirs("evidence/skills",exist_ok=True)
open("evidence/skills/graphify.json","w").write(json.dumps({"paired_evaluation":{"ok":1},"cost_measurement":{"ok":1}}))
c["graphify"].update(state="promoted",evidence={"dossier":"evidence/skills/graphify.json","status":"valid"})'"$_SAVE"

# CONTROLE POSITIVO, e ele e o que impede o portao de ser "reprova tudo". Sem este caso,
# "nunca aprova" seria indistinguivel de "verifica corretamente".
mutante MCAP3 "dossie cobrindo os 7 requisitos APROVA" 0 \
  "$_PY"'
import os
reqs=json.load(open("orchestration/skill-policy.json"))["lifecycle"]["promotion_requires"]
os.makedirs("evidence/skills",exist_ok=True)
open("evidence/skills/graphify.json","w").write(json.dumps({k:{"ok":True} for k in reqs}))
c["graphify"].update(state="promoted",evidence={"dossier":"evidence/skills/graphify.json","status":"valid"})'"$_SAVE"

mutante MCAP4 "dossie com os 7 nomes e valores VAZIOS reprova" 1 \
  "$_PY"'
import os
reqs=json.load(open("orchestration/skill-policy.json"))["lifecycle"]["promotion_requires"]
os.makedirs("evidence/skills",exist_ok=True)
open("evidence/skills/graphify.json","w").write(json.dumps({k:None for k in reqs}))
c["graphify"].update(state="promoted",evidence={"dossier":"evidence/skills/graphify.json","status":"valid"})'"$_SAVE"

echo "== mutantes da divida de avaliacao =="
mutante MCAP5 "capability nova em candidate estoura o teto" 1 \
  "$_PY"'c["nova"]={"kind":"skill","source":"execution/skills/graphify","state":"candidate","installed":False,"activation":"contextual","evidence":{"dossier":None,"status":"absent"}}'"$_SAVE"

# O FURO QUE O PORTAO FINAL ACHOU: `quarantine` e o `initial_state` da policy e ficava FORA da
# contagem. Entrada gratuita usando o estado default, sem precisar levantar o teto.
mutante MCAP6 "capability nova em QUARANTINE tambem estoura o teto" 1 \
  "$_PY"'c["nova"]={"kind":"skill","source":"execution/skills/graphify","state":"quarantine","installed":False,"activation":"contextual","evidence":{"dossier":None,"status":"absent"}}'"$_SAVE"

mutante MCAP7 "capability em quarantine INSTALADA reprova" 1 \
  "$_PY"'c["graphify"]["state"]="quarantine"'"$_SAVE"

# ONDA 14. AS DUAS FUGAS DO TETO CONSTANTE, medidas por auditoria externa. `D_MAX` era numero
# literal DENTRO do arquivo que o PR edita, entao a proibicao de levanta-lo era prosa no objeto
# governado - `PolicyDeclared`, nao `PolicyEnforced`. Agora o criterio e o SHA-base.
mutante MCAP10 "capability nova + o PR levantando o proprio teto reprova" 1 \
  "$_PY"'
import os
os.makedirs("execution/skills/nova",exist_ok=True)
open("execution/skills/nova/SKILL.md","w").write("---\nname: nova\ndescription: x\n---\n")
c["nova"]={"kind":"skill","source":"execution/skills/nova","state":"candidate","installed":False,"activation":"contextual","evidence":{"dossier":None,"status":"absent"}}'"$_SAVE"

# A FUGA MAIS SUTIL: paga um dossie e adiciona outra sem dossie. O TAMANHO da divida nao muda
# (8 -> 8), entao qualquer regra baseada em contagem aprova. So a regra de SUBCONJUNTO pega.
mutante MCAP11 "trocar uma divida por outra reprova (tamanho constante nao basta)" 1 \
  "$_PY"'
import os
reqs=json.load(open("orchestration/skill-policy.json"))["lifecycle"]["promotion_requires"]
os.makedirs("evidence/skills",exist_ok=True)
open("evidence/skills/graphify.json","w").write(json.dumps({k:{"ok":True} for k in reqs}))
c["graphify"]["evidence"]={"dossier":"evidence/skills/graphify.json","status":"valid"}
os.makedirs("execution/skills/nova",exist_ok=True)
open("execution/skills/nova/SKILL.md","w").write("---\nname: nova\ndescription: x\n---\n")
c["nova"]={"kind":"skill","source":"execution/skills/nova","state":"candidate","installed":False,"activation":"contextual","evidence":{"dossier":None,"status":"absent"}}'"$_SAVE"

echo "== mutantes do par registry x manifesto =="
mutante MCAP8 "manifesto sem uma skill do registry reprova" 1 \
  'import pathlib
p=pathlib.Path("install/manifest.lock")
p.write_text("\n".join(l for l in p.read_text().splitlines() if "skills/forge" not in l)+"\n")'

# Este sobreviveu na primeira versao do portao, que comparava so o nome de destino.
mutante MCAP9 "manifesto com a ORIGEM do layout antigo reprova" 1 \
  'import pathlib
p=pathlib.Path("install/manifest.lock")
p.write_text(p.read_text().replace("\texecution/skills/forge\t","\texecution/skills/promoted/forge\t"))'

rm -rf evidence/skills execution/skills/nova 2>/dev/null
echo
echo "baseline=ok  mutantes_esperados=$EXPECTED_MUTANTS  mortos=$P  sobreviventes=$F"
if [ "$F" -eq 0 ] && [ "$P" -eq "$EXPECTED_MUTANTS" ]; then
  echo "================================================================"
  echo "mutacao verde: os $EXPECTED_MUTANTS mutantes se comportaram como o portao promete"
  exit 0
fi
echo "mutacao VERMELHA"
exit 1
