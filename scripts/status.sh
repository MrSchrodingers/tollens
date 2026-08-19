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

# INTERPRETADOR PELO SUFIXO. Achado da revisao da onda 13: a lista abaixo era invocada com
# `bash "$t"` e ganhou um `.py`. Bash sobre Python devolve exit 2 com stdout vazio - a coluna de
# assercoes virava `?` e a de exit virava `2` PERMANENTE no artefato publicado, que e
# normalizacao de desvio. Pior: o bash executa as crases do docstring como substituicao de
# comando; `python3 tests/unit/methodology.py` entre crases foi de fato invocado.
# Verificar o artefato nao e verificar a integracao (regra 3 da §6.3): os sete mutantes do portao
# novo morreram porque eu o chamei a mao. O mutante que faltava era o do WIRING.
roda_suite(){ case "$1" in *.py) python3 "$1" ;; *) bash "$1" ;; esac; }
conta(){ roda_suite "$1" 2>&1 | grep -oE 'PASS=[0-9]+|TOTAL=[0-9]+' | tail -1 | cut -d= -f2; }
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
           tests/unit/capabilities.sh tests/unit/cobertura.sh \
           tests/unit/contrato-de-instalador.sh \
           tests/unit/hooks-de-guarda.sh \
           tests/unit/capability-conformance.py \
           tests/unit/run.sh; do
    roda_suite "$t" >/dev/null 2>&1; rc=$?
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
  m_cap="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/capabilities.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/capabilities.sh >/dev/null 2>&1
  printf '| capability declarada | %s | %s |\n' "${m_cap:-?}" "$?"
  m_cobertura="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' tests/mutation/cobertura.sh | head -1 | cut -d= -f2)"
  bash tests/mutation/cobertura.sh >/dev/null 2>&1
  printf '| cobertura de decisao | %s | %s |\n' "${m_cobertura:-?}" "$?"
  # COMPLETUDE, nao lista digitada a mao. As linhas acima tem rotulo curado por arnes; esta
  # varredura garante que um arnes NOVO nunca nasca fora do relatorio. Foi o que aconteceu com
  # tests/mutation/fable-guard.sh, escrito na onda 7 (12 mutantes sobre 148 linhas de superficie
  # de autorizacao) e ausente daqui ate esta correcao - a MESMA classe que a varredura de
  # completude de ALVOS fechou em evidence/cobertura.sh. Instrumento escrito e nao reportado e
  # a versao pequena do instrumento escrito e nao executado (ADR 0029).
  CURADOS='run install fronteira conformidade schedule fronteira-viva literatura claims capabilities cobertura contrato'
  for _mf in tests/mutation/*.sh; do
    _b="$(basename "$_mf" .sh)"
    case " $CURADOS " in *" $_b "*) continue ;; esac
    _n="$(grep -oE 'EXPECTED_MUTANTS=[0-9]+' "$_mf" | head -1 | cut -d= -f2)"
    # ROTULO CONSTANTE, NAO EXIT CODE MEDIDO. Defeito meu, pago com uma CI vermelha (run
    # 31607753782): a primeira versao desta varredura EXECUTAVA o arnes e gravava o `$?` no
    # artefato. `fable-guard.sh` deu 0 nesta maquina e 1 no runner - o ubuntu-24.04 restringe
    # user namespace nao privilegiado por AppArmor, e 3 dos 12 mutantes dependem de
    # `unshare --map-root-user` para exercitar posse de root sem sudo. Resultado: o artefato
    # NUNCA poderia bater nos dois ambientes, e `--check` reprovava para sempre.
    # E exatamente o que o comentario 30 linhas acima ja explicava sobre `install.sh`, e que eu
    # li antes de escrever isto. Enunciar a regra nao a executa.
    # A execucao real acontece no passo dedicado do workflow, que e onde o veredito importa.
    printf '| %s (auto) | %s | passo dedicado no CI |\n' "$_b" "${_n:-?}"
  done

  printf '\n## Cobertura de decisao (branch), medida via subprocesso instrumentado\n\n'
  printf 'Piso por arquivo (evidence/cobertura.sh --check); ver o script para a mecanica de\n'
  printf 'medicao e o LIMITE declarado (cobertura prova execucao de ramo, nao correcao de\n'
  printf 'assercao).\n\n'
  printf '| Arquivo | Medido | Piso | Status |\n|---|---:|---:|---|\n'
  bash evidence/cobertura.sh 2>/dev/null \
    | awk -F'\t' '$1=="COBFILE"{printf "| `%s` | %s%% | %s%% | %s |\n", $2, $3, $4, $5}'

  printf '\n## Componentes\n\n| Tipo | Qtd |\n|---|---:|\n'
  awk -F'\t' '!/^#/{c[$1]++} END{for(t in c) printf "| %s | %s |\n", t, c[t]}' install/manifest.lock | sort
  printf '| **total** | **%s** |\n' "$(grep -vc '^#' install/manifest.lock)"

  printf '\n## Limites declarados\n\n'
  printf -- '- `allowManagedHooksOnly` continua sendo uma decisao administrativa de deploy; o repositorio nao afirma que esteja ativo em toda instalacao.\n'
  printf -- '- a execucao root do instalador stock agora recusa fonte que nao seja integralmente `root:root`, livre de symlinks e sem escrita de grupo/outros; isso e uma precondicao operacional, nao autenticacao criptografica do release.\n'
  printf -- '- `TOLLENS_REPO`, quando usado por hooks managed para localizar verificadores, continua sendo uma dependencia que deve receber uma fronteira de confianca compativel com o ambiente onde for ativada.\n'
  printf -- '- o ambiente de CI e auditavel, nao hermetico: `ubuntu-24.04` fixa a familia da imagem, nao seu digest, e a excecao `apt` permanece declarada.\n'
  printf -- '- sem corpus proprio de desfecho, nao ha claim de superioridade universal de engenharia; a governanca de skills e evidence-gated e falsificavel.\n'
  printf -- '- parsers e adaptadores documentais nao constituem sandbox de sistema operacional.\n'
  printf -- '- rollback cobre falhas observadas pelo supervisor. `SIGKILL` do supervisor, falha de host/filesystem e comprometimento administrativo permanecem fora da garantia.\n'
  printf -- '- ownership/mode checks usam semantica POSIX/GNU exercitada no CI; ACLs, capabilities e atributos de filesystem fora desse contrato exigem verificacao especifica antes de ampliar a claim.\n'
  printf -- '- o ruleset impoe o check requerido enquanto a regra estiver ativa; administradores com autoridade para alterar a regra permanecem fora desse mecanismo.\n'
  printf -- '- cobertura de decisao (branch, evidence/cobertura.sh) prova que um ramo foi executado por algum teste; nao prova que a assercao daquele teste esta correta. E piso, nao teto: torna a omissao detectavel (ramo nunca exercitado), nunca a torna impossivel (ramo exercitado e mal testado continua passando).\n'

  printf '\n## Propriedades de seguranca medidas\n\n'
  printf -- '- fonte privilegiada user-owned, symlinkada ou group/world-writable e rejeitada antes da delegacao quando o supervisor roda como root na raiz real.\n'
  printf -- '- `TOLLENS_MANAGED_WORKER` e proibido em execucao root sobre a raiz real; o override permanece apenas para ensaios com `MANAGED_PREFIX`.\n'
  printf -- '- modos esperados sao revalidados apos o deploy (`0755` para diretorios/scripts/document-tools; `0644` para os demais arquivos regulares), e divergencia provoca rollback.\n'
  printf -- '- ownership usa `find ... \\( ! -user root -o ! -group root \\) -print -quit`, evitando o bug de precedencia onde `owner!=root, group=root` podia nao produzir saida.\n'
  printf -- '- confinamento de origem/destino do manifesto, re-hash do staging, restauracao transacional e verificacao de permissao continuam cobertos pelas suites managed existentes.\n'
} > "$TMP"

if [ "$CHECK" -eq 1 ]; then
  # EXIT NAO-ZERO REPROVA, e nao apenas "o artefato mudou". Ate a onda 13 este portao era
  # SO `cmp -s`: o documento registra o exit de cada suite como VALOR numa tabela, entao uma
  # suite vermelha gravada como `| 30 | 1 |` batia com a regeneracao e o `--check` aprovava.
  #
  # Nao e hipotese. Aconteceu nesta onda: `tests/unit/propriedades.sh` foi de 31/0 para 30/1
  # por uma colisao de nome de mutante que eu introduzi, a regeneracao assou o vermelho no
  # artefato, `--check` fechou exit 0, e so o passo dedicado da CI pegou. O portao final desta
  # mesma onda tinha nomeado a forma - "enforcement por comparacao de bytes de uma tabela e
  # lavavel" - e a instrucao publicada logo abaixo ("rode scripts/status.sh e commite") era o
  # mecanismo de lavagem: seguir a instrucao ao pe da letra grava o vermelho e devolve o verde.
  #
  # Rotulo nao-numerico ("variavel (sudo)", "passo dedicado no CI", "OK") e ambiente-dependente
  # por decisao ja registrada acima e NAO entra nesta checagem.
  _vermelhas="$(awk -F'|' '/^\| `/ {e=$(NF-1); gsub(/ /,"",e); if (e ~ /^[0-9]+$/ && e+0 != 0) {s=$2; gsub(/ |`/,"",s); print s" (exit="e")"}}' "$TMP")"
  if [ -n "$_vermelhas" ]; then
    echo 'SUITE VERMELHA - o artefato nao pode ser aceito com exit nao-zero:'
    printf '  %s\n' $_vermelhas
    echo 'Regenerar o documento NAO resolve: ele registra o exit, entao gravar o vermelho'
    echo 'devolveria este portao ao verde. Conserte a suite.'
    exit 1
  fi
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
