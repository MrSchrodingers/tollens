#!/usr/bin/env bash
# VALIDACAO POR MUTACAO - camada de qualidade de evidencia para literatura
# (evidence/validate-literature.py).
#
# Por que existe: esta camada e o mecanismo anti-fabricacao da citacao de literatura externa -
# a mesma garantia que a onda que corrigiu titulo fabricado e citacao verbatim inventada em
# evidence/literature/*.yaml deixou sem cobertura de mutacao (docs/adr/0020, regra de metodo 2:
# toda garantia de seguranca/integridade e validada por MUTACAO, nao so por caso positivo).
# Remova cada guarda do validador e a suite (tests/unit/literatura.sh) tem de REPROVAR. Um teste
# que sobrevive ao mutante nao testa a garantia: testa outra coisa.
#
# Convencao: tests/mutation/conformidade.sh (baseline antes de mutar, `troca` por substituicao
# literal com contagem de ancora, kill atribuido ao caso-alvo exato via grep na saida).
#
# LIMITE DECLARADO DESTE ARQUIVO: mutacao prova que o validador REJEITA forma malformada (campo
# ausente, vocabulario fora do fechado, numero sem marcador). Ela NAO prova fidelidade de
# conteudo a fonte primaria - nenhum mutante aqui pode fabricar ou corrigir um titulo, autor ou
# quote, porque o validador nao le o artigo (ver docstring de validate-literature.py e a nota no
# cabecalho de cada evidence/literature/*.yaml).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
ORIG="evidence/validate-literature.py"
REG="tests/unit/literatura.sh"
TMP="$(mktemp -d)"; trap 'cp -f "$TMP/orig.py" "$ORIG" 2>/dev/null || true; rm -rf "$TMP"' EXIT
cp -f "$ORIG" "$TMP/orig.py"
P=0; F=0; BASELINE=nao; EXPECTED_MUTANTS=12

echo "== baseline: a suite precisa passar ANTES de qualquer mutacao =="
if bash "$REG" >/dev/null 2>&1; then echo "  PASS  baseline verde"; BASELINE=ok
else echo "  FAIL  baseline VERMELHO - mutacao nao tem significado; abortando"; exit 1; fi
echo

# SUBSTITUICAO LITERAL: o alvo e Python cheio de f-strings, aspas e chaves - um padrao de sed
# ficaria ilegivel e fragil (mesma razao documentada em tests/mutation/run.sh). `troca` falha
# alto se a ancora nao casar exatamente uma vez, para nunca confundir "mutante nao aplicado" com
# "mutante sobrevivente" - sao defeitos distintos deste arnes.
troca(){ # $1=trecho original  $2=substituto
  python3 - "$ORIG" "$1" "$2" <<'PY'
import sys
alvo, velho, novo = sys.argv[1:4]
s = open(alvo, encoding="utf-8").read()
if s.count(velho) != 1:
    sys.exit("ANCORA NAO CASOU (%d ocorrencias)" % s.count(velho))
open(alvo, "w", encoding="utf-8").write(s.replace(velho, novo))
PY
}

mutante(){ # $1=nome $2=descricao $3=caso-alvo que DEVE reprovar $4..=comando
  local nome="$1" desc="$2" alvo="$3"; shift 3
  cp -f "$TMP/orig.py" "$ORIG"
  "$@"
  if cmp -s "$TMP/orig.py" "$ORIG"; then
    echo "  FAIL  $nome NAO FOI APLICADO - a ancora nao casa com o codigo atual."
    echo "        Mutante nao aplicado nao e mutante sobrevivente: e teste invalido."
    F=$((F+1)); cp -f "$TMP/orig.py" "$ORIG"; return
  fi
  if ! python3 -c "import ast; ast.parse(open('$ORIG', encoding='utf-8').read())" 2>/dev/null; then
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
  fi
  cp -f "$TMP/orig.py" "$ORIG"
}

echo "== mutacao: cada guarda removida DEVE quebrar a validacao da camada de literatura =="

# ML1 - campo obrigatorio 'citation' sai da lista - um documento sem titulo/autor passaria.
mutante ML1 "'citation' e obrigatorio" \
  "'citation' ausente -> reprova" \
  troca 'OBRIGATORIOS = ("literature_id", "citation", "identifier", "url", "provenance",' \
        'OBRIGATORIOS = ("literature_id", "identifier", "url", "provenance",'

# ML2 - formato de literature_id deixa de ser exigido - maiuscula/espaco passariam.
mutante ML2 "literature_id casa com o formato fechado" \
  "literature_id com maiuscula/espaco -> reprova" \
  troca 'if not RE_LITERATURE_ID.match(lid):' \
        'if False and RE_LITERATURE_ID.match(lid):'

# ML3 - nome de arquivo deixa de precisar casar com literature_id - permite arquivo com
# qualquer nome apontando para um id diferente (a mesma classe de erro que nomeou mal um yaml).
mutante ML3 "nome do arquivo casa com literature_id" \
  "arquivo 'nome-errado.yaml' com literature_id 'arxiv-0000.00000' -> reprova" \
  troca 'if os.path.basename(arquivo) != esperado:' \
        'if False and os.path.basename(arquivo) != esperado:'

# ML4 - guarda de literature_id duplicado sai. Esta e a garantia que motivou a correcao do caso
# L6 desta mesma onda: sem checagem de MENSAGEM, um caso que so afira exit code sobreviveria a
# este mutante (a violacao de nome de arquivo, estruturalmente inseparavel da duplicidade nesta
# fixture, ainda produz exit 1) - ver comentario de L6 em tests/unit/literatura.sh.
mutante ML4 "literature_id duplicado e NOMEADO na mensagem" \
  "  a violacao de duplicidade e NOMEADA na mensagem (nao so o mismatch de nome de arquivo)" \
  troca 'if lid in vistos:
        erro(f"literature_id '"'"'{lid}'"'"' duplicado (ja usado em {vistos[lid]})")
    else:
        vistos[lid] = os.path.basename(arquivo)' \
        'vistos[lid] = os.path.basename(arquivo)'

# SEM MUTANTE PARA A CHECAGEM DE VAZIO/TIPO DE `_valida_findings` (a condicao
# `not isinstance(findings, list) or not findings` no topo daquela funcao). Medido ao tentar: um
# mutante que remova so a metade "or not findings" SOBREVIVE ao caso "findings=[] -> reprova" de
# tests/unit/literatura.sh (L7a) - mesma classe de sobredeterminacao do L6 corrigido nesta onda,
# so que aqui a garantia redundante e OUTRA checagem DESTE MESMO programa, nao uma coincidencia
# de fixture: o loop `for campo in OBRIGATORIOS` (que inclui "findings") ja reprova QUALQUER
# `findings: []` antes de `_valida_findings` ser chamada, porque `[] in (None, "", [], {})` e
# verdadeiro - `if e: return e` interrompe a validacao ali, e a funcao especifica nunca roda.
# A metade "isinstance" da mesma guarda tem valor real (evita um crash de `enumerate()` sobre um
# `findings` nao-iteravel, ex.: `findings: true`), mas nao ha hoje, em tests/unit/literatura.sh,
# um caso com `findings` NAO-vazio e NAO-lista para atribuir esse kill sem inventar fixture nova
# fora do escopo desta entrega. Registrado aqui em vez de forjar um mutante "morto" por engano.
echo "  NOTA  sem mutante para _valida_findings(vazio/tipo): redundante com o OBRIGATORIOS para" \
     "findings=[] (ver comentario acima); nao ha fixture hoje para o caso nao-vazio-nao-lista."

# ML5 - inference_strength sai do vocabulario fechado - qualquer string livre passaria,
# inclusive uma que nao significa nada ("PROBABLY").
mutante ML5 "inference_strength no vocabulario fechado" \
  "inference_strength='PROBABLY' -> reprova" \
  troca "if doc[\"inference_strength\"] not in FORCA_INFERENCIA:" \
        "if False and doc[\"inference_strength\"] not in FORCA_INFERENCIA:"

# ML6 - provenance sai do vocabulario fechado - mesma classe de defeito do ML5, outro campo.
mutante ML6 "provenance no vocabulario fechado" \
  "provenance='trust_me_bro' -> reprova" \
  troca 'if doc["provenance"] not in PROVENIENCIA:' \
        'if False and doc["provenance"] not in PROVENIENCIA:'

# ML7 - findings[].metric deixa de exigir snake_case - nome de metrica livre quebra o contrato
# que liga um achado numerico a uma chave estavel e referenciavel por outros campos.
mutante ML7 "findings[].metric em snake_case" \
  "metric='Not Snake Case' -> reprova" \
  troca 'if isinstance(metrica, str) and metrica and not RE_METRIC.match(metrica):' \
        'if False and isinstance(metrica, str) and metrica and not RE_METRIC.match(metrica):'

# ML8 - findings[].source deixa de ser exigido - um numero em findings ficaria SEM fonte
# declarada, o proprio motivo estrutural pelo qual findings existe nesta camada.
mutante ML8 "findings[] exige 'source'" \
  "findings[0] sem 'source' -> reprova" \
  troca 'for campo in ("metric", "value", "source"):' \
        'for campo in ("metric", "value"):'

# ML9 - a varredura de numero-sem-marcador-de-fonte desliga (RE_MARCADOR_FONTE casa tudo). E a
# guarda central desta camada: sem ela, um numero pode entrar pela prosa argumentativa
# (inference_rationale, applicability, study_quality) sem NUNCA passar por findings.source - a
# rota exata do defeito original da secao 6.1 do README (ver docstring do validador).
mutante ML9 "numero solto fora de findings exige marcador 'fonte'/'verificad'" \
  "'47 por cento' solto, sem marcador -> reprova" \
  troca 'RE_MARCADOR_FONTE = re.compile(r"fonte|verificad", re.IGNORECASE)' \
        'RE_MARCADOR_FONTE = re.compile(r".*")'

# ML10 - REGRA 5 (contradicao interna verbatim, adicionada nesta onda) desliga - uma citacao
# retratada num campo poderia reaparecer verbatim, sem retratacao, noutro campo do MESMO
# documento sem que a camada de literatura reprovasse. Escopo do que este mutante prova: so a
# reaparicao LITERAL (ver limites declarados na docstring de validate-literature.py) - a
# variante de parafrase nao tem guarda mecanica, por design, e por isso nao tem mutante aqui.
mutante ML10 "citacao retratada nao pode reaparecer verbatim sem marca (contradicao interna)" \
  "citacao retratada reaparece verbatim em limitations -> reprova" \
  troca 'for v in _varre_contradicao(doc):
        erro(v)' \
        'for v in []:
        erro(v)'

# ML11 - a JANELA_RETRATACAO deixa de limitar a proximidade e volta a valer para o CAMPO
# INTEIRO (o falso positivo medido pela revisao independente antes desta correcao: em
# arxiv-2602.06547.yaml o titulo CORRETO, citado legitimamente longe do marcador de retratacao
# no mesmo campo `citation`, virava "retratado" so por estar no mesmo campo que a citacao
# fabricada perto do marcador). L23 e o caso construido para essa forma exata: titulo correto
# reusado em `limitations` tem de PASSAR; com a janela efetivamente infinita, ele reprova.
mutante ML11 "JANELA_RETRATACAO limita 'por perto' a uma vizinhanca real, nao ao campo inteiro" \
  "L23 titulo CORRETO reusado em limitations -> passa (fix do falso positivo)" \
  troca 'JANELA_RETRATACAO = 100' \
        'JANELA_RETRATACAO = 10**9'

# ML12 - RE_RETRATACAO volta a ser substring desancorada (\binvent\w*) em vez de formas de
# palavra especificas - o falso negativo medido pela revisao independente: uma palavra
# irrelevante que comeca por "invent-" (ex.: "inventario") casava o marcador por acidente e
# isentava um campo que na verdade reafirma a citacao fabricada como fato. L25 e o caso
# construido para essa forma exata.
mutante ML12 "RE_RETRATACAO ancorado a formas de palavra especificas, nao substring solta" \
  "L25 'inventario' (raiz invent- irrelevante) nao desliga mais a deteccao -> reprova" \
  troca 'RE_RETRATACAO = re.compile(
    r"nao existe (no|na)\b|\binvent(ada|ado|adas|ados|ou|aram)\b|\bfabricad(a|o|as|os)\b",
    re.IGNORECASE)' \
        'RE_RETRATACAO = re.compile(
    r"nao existe (no|na)|\binvent\w*|\bfabricad\w*",
    re.IGNORECASE)'

cp -f "$TMP/orig.py" "$ORIG"
echo
printf 'baseline=%s  mutantes_esperados=%s  mortos=%s  invalidos_ou_sobreviventes=%s\n' \
       "$BASELINE" "$EXPECTED_MUTANTS" "$P" "$F"
echo "================================================================"
if [ "$F" -ne 0 ]; then echo "mutacao VERMELHA: ha garantia que a suite nao protege"; exit 1; fi
if [ "$P" -ne "$EXPECTED_MUTANTS" ]; then
  echo "mutacao VERMELHA: $P mortos para $EXPECTED_MUTANTS mutantes - algum nao executou"; exit 1; fi
echo "mutacao verde: os $EXPECTED_MUTANTS mutantes morreram no caso-alvo correspondente"; exit 0
