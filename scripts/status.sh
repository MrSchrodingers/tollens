#!/usr/bin/env bash
# Gera docs/status.generated.md a partir de execucao real. Numeros de suites e mutantes sao
# derivados dos proprios oraculos; o README referencia este artefato em vez de duplica-los.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
. "$(dirname "$0")/../tests/lib/lock.sh"
export LC_ALL=C
OUT="docs/status.generated.md"
CHECK=0
[ "${1:-}" = "--check" ] && CHECK=1 || OUT="${1:-$OUT}"

conta(){ bash "$1" 2>&1 | grep -oE 'PASS=[0-9]+' | tail -1 | cut -d= -f2; }
TMP="$(mktemp)" || exit 1
trap 'rm -f "$TMP"' EXIT

{
  printf '# Estado gerado\n\n'
  printf 'NAO EDITAR. Gerado por `scripts/status.sh` a partir de execucao real.\n'
  printf 'O README referencia este arquivo em vez de duplicar numeros.\n\n'

  printf '## Suites\n\n| Suite | Assercoes | Exit |\n|---|---:|---:|\n'
  for t in tests/unit/regressao-gate.sh tests/unit/document-tools.sh tests/unit/supply-chain.sh \
           tests/unit/reprodutibilidade.sh tests/unit/concorrencia.sh tests/unit/claims.sh \
           tests/unit/propriedades.sh tests/unit/fronteira-externa.sh tests/unit/managed.sh \
           tests/unit/conformidade-managed.sh tests/unit/arnes-de-mutacao.sh \
           tests/unit/schedule.sh tests/unit/fronteira-viva.sh tests/unit/literatura.sh \
           tests/unit/capabilities.sh \
           tests/unit/capabilities.sh \
           tests/unit/run.sh; do
    bash "$t" >/dev/null 2>&1; rc=$?
    if grep -q 'EXPECTED=\$((' "$t"; then n='variavel (ambiente)'; else n="$(conta "$t")"; fi
    printf '| `%s` | %s | %s |\n' "$t" "${n:-?}" "$rc"
  done
  bash tests/unit/managed-root-trust.sh >/dev/null 2>&1; rc=$?
  printf '| `tests/unit/managed-root-trust.sh` | variavel (sudo) | %s |\n' "$rc"

  printf '\n## Mutacao\n\n| Alvo | Mutantes | Exit |\n|---|---:|---:|\n'
  mg="$(grep -c '^mutante M' tests/mutation/run.sh)"; bash tests/mutation/run.sh >/dev/null 2>&1
  printf '| gate | %s | %s |\n' "$mg" "$?"
  mc="$(grep -c '^mutante M' tests/mutation/contrato.sh)"; bash tests/mutation/contrato.sh >/dev/null 2>&1
  printf '| contrato de subagente | %s | %s |\n' "$mc" "$?"
  # EXIT AMBIENTE-DEPENDENTE NAO ENTRA COMO NUMERO FIXO. MI4/MI5 exigem oraculo root; sem sudo
  # sem senha a suite sai 1, com sudo sai 0. Como este arquivo e commitado e conferido por
  # `--check` na CI, um numero aqui so podia ser verde no ambiente que o gerou - e obrigava quem
  # regenerasse localmente a escrever um valor que NAO observou. Rotulo constante e honesto e a
  # unica forma de o artefato ser reproduzivel nos dois ambientes. Mesmo tratamento ja dado a
  # `managed-root-trust.sh`, e a `reprodutibilidade.sh` na coluna de assercoes.
  # NAO executamos aqui: com o Exit virando rotulo constante, rodar a suite (~40 s) e descartar
  # o `$?` e execucao que nao produz sinal algum. A cobertura nao se perde - os dois workflows
  # tem passo dedicado `validacao por mutacao (instalador)`, que e onde o oraculo root existe.
  mi="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/install.sh | head -1 | cut -d= -f2)"
  printf '| instalador | %s | variavel (sudo) |\n' "${mi:-?}"
  mf="$(grep -c '^mutante MF' tests/mutation/fronteira.sh)"; bash tests/mutation/fronteira.sh >/dev/null 2>&1
  printf '| fronteira externa | %s | %s |\n' "$mf" "$?"
  mcm="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/conformidade.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/conformidade.sh >/dev/null 2>&1
  printf '| conformidade de dois escopos | %s | %s |\n' "${mcm:-?}" "$?"
  msc="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/schedule.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/schedule.sh >/dev/null 2>&1
  printf '| escalonamento | %s | %s |\n' "${msc:-?}" "$?"
  m_fronteira_viva="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/fronteira-viva.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/fronteira-viva.sh >/dev/null 2>&1
  printf '| fronteira viva | %s | %s |\n' "${m_fronteira_viva:-?}" "$?"
  m_literatura="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/literatura.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/literatura.sh >/dev/null 2>&1
  printf '| camada de literatura | %s | %s |\n' "${m_literatura:-?}" "$?"
  m_claims="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/claims.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/claims.sh >/dev/null 2>&1
  printf '| claim ledger | %s | %s |\n' "${m_claims:-?}" "$?"
  m_fronteira_viva="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/fronteira-viva.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/fronteira-viva.sh >/dev/null 2>&1
  printf '| fronteira viva | %s | %s |\n' "${m_fronteira_viva:-?}" "$?"
  m_literatura="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/literatura.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/literatura.sh >/dev/null 2>&1
  printf '| camada de literatura | %s | %s |\n' "${m_literatura:-?}" "$?"
  m_claims="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/claims.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/claims.sh >/dev/null 2>&1
  printf '| claim ledger | %s | %s |\n' "${m_claims:-?}" "$?"

  printf '\n## Componentes\n\n| Tipo | Qtd |\n|---|---:|\n'
  awk -F'\t' '!/^#/{c[$1]++} END{for(t in c) printf "| %s | %s |\n", t, c[t]}' install/manifest.lock | sort
  printf '| **total** | **%s** |\n' "$(grep -vc '^#' install/manifest.lock)"

  printf '\n## Limites declarados\n\n'
  printf -- '- `allowManagedHooksOnly` continua sendo uma decisao administrativa de deploy; o repositorio nao afirma que esteja ativo em toda instalacao.\n'
  printf -- '- a execucao root do instalador stock agora recusa fonte que nao seja integralmente `root:root`, livre de symlinks e sem escrita de grupo/outros; isso e uma precondicao operacional, nao autenticacao criptografica do release.\n'
  printf -- '- `EVIDENCE_GATE_REPO`, quando usado por hooks managed para localizar verificadores, continua sendo uma dependencia que deve receber uma fronteira de confianca compativel com o ambiente onde for ativada.\n'
  printf -- '- o ambiente de CI e auditavel, nao hermetico: `ubuntu-24.04` fixa a familia da imagem, nao seu digest, e a excecao `apt` permanece declarada.\n'
  printf -- '- sem corpus proprio de desfecho, nao ha claim de superioridade universal de engenharia; a governanca de skills e evidence-gated e falsificavel.\n'
  printf -- '- parsers e adaptadores documentais nao constituem sandbox de sistema operacional.\n'
  printf -- '- rollback cobre falhas observadas pelo supervisor. `SIGKILL` do supervisor, falha de host/filesystem e comprometimento administrativo permanecem fora da garantia.\n'
  printf -- '- ownership/mode checks usam semantica POSIX/GNU exercitada no CI; ACLs, capabilities e atributos de filesystem fora desse contrato exigem verificacao especifica antes de ampliar a claim.\n'
  printf -- '- o ruleset impoe o check requerido enquanto a regra estiver ativa; administradores com autoridade para alterar a regra permanecem fora desse mecanismo.\n'

  printf '\n## Propriedades de seguranca medidas\n\n'
  printf -- '- fonte privilegiada user-owned, symlinkada ou group/world-writable e rejeitada antes da delegacao quando o supervisor roda como root na raiz real.\n'
  printf -- '- `EVIDENCE_GATE_MANAGED_LEGACY` e proibido em execucao root sobre a raiz real; o override permanece apenas para ensaios com `MANAGED_PREFIX`.\n'
  printf -- '- modos esperados sao revalidados apos o deploy (`0755` para diretorios/scripts/document-tools; `0644` para os demais arquivos regulares), e divergencia provoca rollback.\n'
  printf -- '- ownership usa `find ... \\( ! -user root -o ! -group root \\) -print -quit`, evitando o bug de precedencia onde `owner!=root, group=root` podia nao produzir saida.\n'
  printf -- '- confinamento de origem/destino do manifesto, re-hash do staging, restauracao transacional e verificacao de permissao continuam cobertos pelas suites managed existentes.\n'
} > "$TMP"

if [ "$CHECK" -eq 1 ]; then
  if cmp -s "$TMP" docs/status.generated.md; then
    echo 'status atualizado'
    exit 0
  fi
  echo 'docs/status.generated.md DESATUALIZADO - rode scripts/status.sh e commite'
  diff -u docs/status.generated.md "$TMP" | head -40
  exit 1
fi
mv "$TMP" "$OUT"
trap - EXIT
echo "gerado: $OUT"
