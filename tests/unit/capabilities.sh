#!/usr/bin/env bash
# SUITE DO VERIFICADOR DE CAPACIDADE DECLARADA (evidence/runtime-probes/declared-capabilities.py).
#
# POR QUE ESTA SUITE EXISTE - o verificador era, ate esta onda, o UNICO executavel novo sem
# nenhum teste (github-ruleset.py tem 14 casos em fronteira-viva.sh, validate-literature.py tem
# 27 em literatura.sh, schedule.py tem 15+4). Foi exatamente aqui que o defeito estava: a saida
# de `--repo-only` era byte-identica a do modo completo (medido por `diff`) enquanto a linha de
# PASS continuava afirmando "identico nas 3 fontes" - uma prova de comparacao que nao ocorreu,
# arquivavel em log de CI. Sem suite alguma, nada discriminava essa mentira de saida.
#
# ISOLAMENTO: o script sob teste le TRES arvores via variavel de ambiente
# (EVIDENCE_GATE_ROOT/execution/agents, EVIDENCE_GATE_ROOT/.claude/agents, CLAUDE_HOME/agents) -
# por isso toda fixture desta suite vive em diretorio descartavel, nunca em execution/agents/ ou
# .claude/agents/ deste repositorio (que sao o DADO que o probe observa - mutar o dado para o
# probe passar seria fraude, nao teste).
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
# LOCK: suites deste repo nao sao reentrantes entre si (tests/lib/lock.sh).
. "$(dirname "$0")/../lib/lock.sh"
PROBE="$PWD/evidence/runtime-probes/declared-capabilities.py"
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

command -v python3 >/dev/null 2>&1 || { echo "NAO VERIFICADO: python3 ausente - o probe nao pode ser exercitado." >&2; exit 2; }

T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

# --- FIXTURE: um arquivo de agente com frontmatter minimo e `tools:` na forma pedida. ---
# spec: "INLINE:A,B"  -> `tools: A, B` numa linha so
#       "BLOCK:A,B"   -> `tools:` seguido de `  - A` / `  - B`
#       "OMIT"        -> nenhuma chave `tools:` (arquivo existe, frontmatter fecha)
agente(){  # $1=caminho do .md  $2=spec
  local path="$1" spec="$2"
  mkdir -p "$(dirname "$path")"
  {
    echo "---"
    echo "name: fixture"
    echo "description: fixture de teste"
    case "$spec" in
      OMIT) : ;;
      BLOCK:*)
        echo "tools:"
        IFS=',' read -ra itens <<< "${spec#BLOCK:}"
        for it in "${itens[@]}"; do echo "  - $it"; done
        ;;
      INLINE:*) echo "tools: ${spec#INLINE:}" ;;
      *) echo "SPEC DESCONHECIDA: $spec" >&2; exit 90 ;;
    esac
    echo "model: sonnet"
    echo "---"
    echo "corpo de fixture"
  } > "$path"
}

rodar(){  # $1=ROOT  $2=HOME  $3...=argumentos extras do probe
  local root="$1" home="$2"; shift 2
  EVIDENCE_GATE_ROOT="$root" CLAUDE_HOME="$home" python3 "$PROBE" "$@" >"$T/out" 2>"$T/err"
  echo $?
}

echo "== K1. duas arvores integras (canonica == projecao == instalada) -> PASS, exit 0 =="
R="$T/k1"; H="$T/k1-home"
agente "$R/execution/agents/a.md" "INLINE:Read, Grep, Glob"
agente "$R/.claude/agents/a.md"   "INLINE:Read, Grep, Glob"
agente "$H/agents/a.md"           "INLINE:Read, Grep, Glob"
RC="$(rodar "$R" "$H")"
chk "exit code 0" "$RC" 0
chk "  reporta 0 divergentes" "$(grep -q 'divergentes: 0' "$T/out" && echo sim || echo nao)" "sim"
chk "  PASS declara as 3 fontes comparadas (canonica, projecao, instalada)" \
    "$(grep -q '^PASS a: tools: identico nas 3 fontes comparadas' "$T/out" && echo sim || echo nao)" "sim"

echo "== K2. arquivo de projecao do repo AUSENTE (arvore existe, arquivo nao) -> NAO_VERIFICADO, exit 2 =="
R="$T/k2"; H="$T/k2-home"
agente "$R/execution/agents/a.md" "INLINE:Read, Grep"
mkdir -p "$R/.claude/agents"          # arvore existe, mas SEM a.md
agente "$H/agents/a.md"           "INLINE:Read, Grep"
RC="$(rodar "$R" "$H")"
chk "exit code 2" "$RC" 2
chk "  aponta a fonte concreta ausente" \
    "$(grep -q 'projecao do repo (.claude/agents) ausente em' "$T/out" && echo sim || echo nao)" "sim"
chk "  nao imprime PASS nenhum (nada foi decidido)" \
    "$(grep -q '^PASS' "$T/out" && echo vazou || echo contido)" "contido"

echo "== K3. tools: DIVERGENTE entre canonica e projecao -> VIOLACAO, exit 1 =="
R="$T/k3"; H="$T/k3-home"
agente "$R/execution/agents/a.md" "INLINE:Read, Grep, Glob"
agente "$R/.claude/agents/a.md"   "INLINE:Read, Grep"          # falta Glob
agente "$H/agents/a.md"           "INLINE:Read, Grep, Glob"
RC="$(rodar "$R" "$H")"
chk "exit code 1" "$RC" 1
chk "  nomeia o que falta na fonte divergente" \
    "$(grep -q 'projecao do repo (.claude/agents) DIVERGE do canonico (ausentes ali: Glob)' "$T/out" && echo sim || echo nao)" "sim"

echo "== K4. diretorio .claude/agents INTEIRO ausente (nao so um arquivo) -> NAO_VERIFICADO, exit 2 =="
R="$T/k4"; H="$T/k4-home"
agente "$R/execution/agents/a.md" "INLINE:Read, Grep"
# $R/.claude nao e criado de forma alguma
agente "$H/agents/a.md"           "INLINE:Read, Grep"
RC="$(rodar "$R" "$H")"
chk "exit code 2 (mesma logica de arquivo ausente, agora para a arvore inteira)" "$RC" 2

echo "== K5. --repo-only com divergencia plantada SO na perna instalada -> exit 0, mas DECLARA que a instalada nao foi verificada =="
# Esta e a reproducao literal do defeito original: canonica == projecao do repo, e a UNICA
# divergencia real mora na perna instalada (a mesma forma do achado de refutador: Write a mais).
R="$T/k5"; H="$T/k5-home"
agente "$R/execution/agents/a.md" "INLINE:Read, Grep"
agente "$R/.claude/agents/a.md"   "INLINE:Read, Grep"
agente "$H/agents/a.md"           "INLINE:Read, Grep, Write"   # divergencia SO aqui
RC="$(rodar "$R" "$H" --repo-only)"
chk "--repo-only: exit 0 (a divergencia plantada esta fora do que este modo compara)" "$RC" 0
chk "  PASS declara SO 2 fontes (nao 3) - a mentira original" \
    "$(grep -q '^PASS a: tools: identico nas 2 fontes comparadas' "$T/out" && echo sim || echo nao)" "sim"
chk "  a linha PASS NAO afirma '3 fontes' (a saida byte-identica ao modo completo era o defeito)" \
    "$(grep -q '3 fontes' "$T/out" && echo vazou || echo contido)" "contido"
chk "  declara explicitamente que a perna instalada NAO foi verificada" \
    "$(grep -q 'perna instalada.*NAO.*verificada\|NAO e verificada nesta execucao' "$T/out" && echo sim || echo nao)" "sim"
# CONTROLE - a MESMA fixture, SEM --repo-only, tem que acusar a divergencia real (prova de que
# a divergencia plantada e genuina, nao um caso que nunca reprovaria em modo nenhum).
RC2="$(rodar "$R" "$H")"
chk "  controle: a MESMA fixture SEM --repo-only reprova (exit 1) - a divergencia e real" "$RC2" 1
chk "    controle: aponta 'a mais ali: Write' na perna instalada" \
    "$(grep -q 'instalada (CLAUDE_HOME/agents) DIVERGE do canonico (a mais ali: Write)' "$T/out" && echo sim || echo nao)" "sim"

echo "== K6. tools: AUSENTE (omitido) numa projecao -> VIOLACAO, exit 1 (D2: nao e mais NAO_VERIFICADO) =="
# Doutrina confirmada na doc primaria do Claude Code (tabela de frontmatter, sub-agents):
# omitir 'tools:' faz o subagente herdar TODAS as ferramentas - a concessao MAXIMA, nao uma
# lacuna. Antes desta correcao este caso saia NAO_VERIFICADO/exit 2; a decisao inverte para
# VIOLACAO porque a ausencia agora e informacao DECIDIVEL, nao indecidibilidade.
R="$T/k6"; H="$T/k6-home"
agente "$R/execution/agents/a.md" "INLINE:Read, Grep"
agente "$R/.claude/agents/a.md"   "OMIT"
agente "$H/agents/a.md"           "INLINE:Read, Grep"
RC="$(rodar "$R" "$H")"
chk "tools: ausente numa projecao -> exit 1 (VIOLACAO, nao 2)" "$RC" 1
chk "  a mensagem nomeia a concessao MAXIMA por omissao (HERDA TODAS as ferramentas)" \
    "$(grep -q 'HERDA TODAS as ferramentas' "$T/out" && echo sim || echo nao)" "sim"
chk "  nao aparece em NAO VERIFICADO (a decisao mudou de secao, nao so de rotulo)" \
    "$(grep -A5 '^NAO VERIFICADO' "$T/out" | grep -q ': projecao do repo' && echo vazou || echo contido)" "contido"

echo "== K7. tools: EM BLOCO YAML (lista, nao inline) e reconhecido como igual ao canonico -> exit 0 =="
# Prova o segundo ponto de D2: RE_TOOLS so casava a forma inline; uma lista de bloco nao podia
# virar VIOLACAO por engano de leitura (parser cego a uma forma valida != capacidade divergente).
R="$T/k7"; H="$T/k7-home"
agente "$R/execution/agents/a.md" "INLINE:Read, Grep"
agente "$R/.claude/agents/a.md"   "BLOCK:Read,Grep"
agente "$H/agents/a.md"           "INLINE:Read, Grep"
RC="$(rodar "$R" "$H")"
chk "lista de bloco YAML equivalente a inline -> exit 0 (nao falso-VIOLACAO por forma)" "$RC" 0

echo "== K8. tools: ausente na fonte CANONICA -> defeito estrutural (violacao), nao lacuna silenciosa =="
R="$T/k8"; H="$T/k8-home"
agente "$R/execution/agents/a.md" "OMIT"
agente "$R/.claude/agents/a.md"   "INLINE:Read, Grep"
agente "$H/agents/a.md"           "INLINE:Read, Grep"
RC="$(rodar "$R" "$H")"
chk "canonica sem tools: legivel -> exit 1" "$RC" 1
chk "  aponta a fonte canonica como o defeito" \
    "$(grep -q 'fonte canonica .*sem .tools:. legivel' "$T/out" && echo sim || echo nao)" "sim"

echo "== K9. CLI: flag desconhecida NAO roda modo completo calado -> exit 2, sem PASS nenhum =="
# Antes: \`\"--repo-only\" in sys.argv\` aceitava qualquer outro token sem reclamar - um erro de
# digitacao (--repoonly) rodava o modo completo em silencio, sem aplicar o filtro pedido.
R="$T/k9"; H="$T/k9-home"
agente "$R/execution/agents/a.md" "INLINE:Read, Grep"
agente "$R/.claude/agents/a.md"   "INLINE:Read, Grep"
agente "$H/agents/a.md"           "INLINE:Read, Grep"
RC="$(rodar "$R" "$H" --repoonly)"
chk "flag desconhecida -> exit 2 (nao 0 por omissao de validacao)" "$RC" 2
chk "  nao imprime PASS algum (nao chegou a rodar a comparacao)" \
    "$(grep -q '^PASS' "$T/out" && echo vazou || echo contido)" "contido"
chk "  stderr nomeia o argumento nao reconhecido" \
    "$(grep -q 'unrecognized arguments' "$T/err" && echo sim || echo nao)" "sim"

echo
printf '================ PASS=%s  FAIL=%s ================\n' "$P" "$F"
# CONTAGEM INVARIANTE: um caso que parasse de rodar aqui sumiria em silencio - a mesma disciplina
# de tests/unit/fronteira-viva.sh e tests/unit/literatura.sh.
EXPECTED=24
if [ "$P" -ne "$EXPECTED" ]; then
  echo "CONTAGEM INESPERADA: PASS=$P, esperado $EXPECTED. Caso removido ou nao executado."
  exit 1
fi
[ "$F" -eq 0 ] && echo "capabilities verde ($P/$EXPECTED)" || echo "capabilities VERMELHA ($F falhas)"
exit "$F"
