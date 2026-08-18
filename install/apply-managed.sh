#!/usr/bin/env bash
set -uo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)" || exit 1
REPO="$(cd "$SELF_DIR/.." && pwd -P)" || exit 1
DEFAULT_WORKER="$SELF_DIR/apply-managed-worker.sh"

RAW_PREFIX="${MANAGED_PREFIX:-}"
case "$RAW_PREFIX" in
  ""|/) PREFIX="" ;;
  *) PREFIX="${RAW_PREFIX%/}" ;;
esac
OPT="${PREFIX}/opt/tollens"
SETTINGS="${PREFIX}/etc/claude-code/managed-settings.json"
REAL=0; [ -z "$PREFIX" ] && REAL=1

# PRIVILEGED TRUST BOUNDARY.
# A real-root deployment must never execute a helper from a checkout writable by the governed
# actor. This check covers the entire repository because apply-managed-worker.sh executes
# install/hooks-spec.sh today and future privileged helpers must inherit the same invariant.
# Symlinks are rejected as well: ownership of the link does not establish ownership of its
# target. TOLLENS_MANAGED_WORKER remains available only for prefixed, non-production tests.
if [ "$REAL" -eq 1 ] && [ "$(id -u)" -eq 0 ]; then
  if [ -n "${TOLLENS_MANAGED_WORKER:-}" ]; then
    echo "ERRO: override TOLLENS_MANAGED_WORKER e proibido em execucao root sobre a raiz real." >&2
    exit 78
  fi
  trust_bad="$(find "$REPO" -xdev \( -type l -o \! -user root -o \! -group root -o -perm /022 \) -print -quit 2>/dev/null || true)"
  if [ -n "$trust_bad" ]; then
    echo "ERRO: fonte privilegiada nao confiavel: $trust_bad" >&2
    echo "      A execucao root exige snapshot inteiro root:root, sem symlinks e sem escrita de grupo/outros." >&2
    echo "      Nao execute este instalador com sudo diretamente de um checkout gravavel pelo usuario." >&2
    exit 78
  fi
fi

WORKER="${TOLLENS_MANAGED_WORKER:-$DEFAULT_WORKER}"
[ -x "$WORKER" ] || { echo "NOT_VERIFIED: instalador (worker) ausente" >&2; exit 2; }

# ONDA 12. O `case` tratava --verify e --revert e CAIA FORA para todo o resto, seguindo direto
# para o apply managed completo. Aqui a consequencia e pior que no apply.sh de escopo de usuario:
# este roda como root e escreve em /opt e nas managed settings. `apply-managed.sh --help`, ou um
# typo, disparava a instalacao privilegiada inteira em silencio.
#
# CORRECAO DA CORRECAO, mesma onda: a primeira versao deste bloco listava so --verify|--revert e
# jogava --dry-run e --enforce no ramo de erro. Isso QUEBROU o caminho publicado - `docs/HANDOFF.md`
# manda `sudo bash install/apply-managed.sh --enforce`, que e o unico passo que liga
# `allowManagedHooksOnly` - e reprovou tests/unit/managed.sh (MG2/MG6/MG7) e
# tests/unit/managed-root-trust.sh. Pior que a inconveniencia: o operador bloqueado chamaria
# `apply-managed-worker.sh --enforce` direto, PULANDO o snapshot/rollback deste supervisor e a
# checagem de raiz de confianca root-owned (ADR 0026, exit 78). Endurecimento que empurra o
# operador para fora do mecanismo de seguranca e regressao de seguranca, nao ganho.
#
# A CONTAGEM VEM ANTES DO `case`: o ramo --verify|--revert faz `exec` e nunca alcancava uma
# checagem posterior. Medido pelo auditor: `--revert --dry-run` chegava ao worker com argc=2, e o
# worker so inspeciona "$1" - um revert REAL e privilegiado com o --dry-run engolido em silencio.
[ "$#" -le 1 ] || {
  printf 'ERRO: argumentos em excesso (%s)\nuso: %s [--dry-run|--enforce|--verify|--revert]\n' "$#" "$0" >&2
  exit 2
}
case "${1:-}" in
  --verify|--revert)
    exec "$WORKER" "$@"
    ;;
  --dry-run|--enforce|"")
    # Seguem para o corpo do supervisor, que invoca o worker em "$WORKER" "$@" com
    # snapshot e rollback ao redor. --enforce DEPENDE desse rollback; nao mova para o `exec`.
    : ;;
  --help|-h)
    printf 'uso: %s [--dry-run|--enforce|--verify|--revert]\n  sem argumento: aplica o escopo managed (exige root)\n' "$0"; exit 0 ;;
  *)
    printf 'ERRO: argumento desconhecido: %s\nuso: %s [--dry-run|--enforce|--verify|--revert]\n' "$1" "$0" >&2; exit 2 ;;
esac

REC="$(mktemp -d "${TMPDIR:-/tmp}/tollens-recovery.XXXXXX")" || exit 1
cleanup(){ rm -rf "$REC" 2>/dev/null || true; }
trap cleanup EXIT

HAD_OPT=0
HAD_SETTINGS=0
if [ -d "$OPT" ]; then
  HAD_OPT=1
  cp -a "$OPT" "$REC/opt" || exit 1
fi
if [ -f "$SETTINGS" ]; then
  HAD_SETTINGS=1
  cp -a "$SETTINGS" "$REC/settings.json" || exit 1
fi

rollback(){
  local bad=0
  rm -rf "$OPT" 2>/dev/null || bad=1
  rm -f "$SETTINGS" 2>/dev/null || bad=1
  if [ "$HAD_OPT" -eq 1 ]; then
    mkdir -p "$(dirname "$OPT")" && cp -a "$REC/opt" "$OPT" || bad=1
  fi
  if [ "$HAD_SETTINGS" -eq 1 ]; then
    mkdir -p "$(dirname "$SETTINGS")" && cp -a "$REC/settings.json" "$SETTINGS" || bad=1
  fi
  if [ "$bad" -ne 0 ]; then
    trap - EXIT
    echo "ROLLBACK_FAILED: recuperacao preservada em $REC" >&2
    return 1
  fi
  return 0
}

"$WORKER" "$@"
rc=$?
if [ "$rc" -ne 0 ]; then
  rollback && exit "$rc" || exit 70
fi

# Exact mode contract. The delegated installer intends directories and executable policy material
# to be 0755, with other regular files at 0644. Verifying exact modes here closes the previous
# gap where chmod failures could be hidden by a content-only postcondition.
mode_bad="$(find "$OPT" -xdev \( \
  -type d \! -perm 0755 -o \
  -type f -name '*.sh' \! -perm 0755 -o \
  -type f -path '*/document-tools/*' \! -perm 0755 -o \
  -type f \! -name '*.sh' \! -path '*/document-tools/*' \! -perm 0644 \
\) -print -quit 2>/dev/null || true)"
if [ -n "$mode_bad" ]; then
  echo "modo inseguro ou inesperado: $mode_bad" >&2
  rollback && exit 1 || exit 70
fi

# Defense in depth: no policy object may remain group/world writable.
unsafe="$(find "$OPT" -xdev \( -type f -o -type d \) -perm /022 -print -quit 2>/dev/null || true)"
if [ -n "$unsafe" ]; then
  echo "permissao insegura: $unsafe" >&2
  rollback && exit 1 || exit 70
fi

# Ownership validation is meaningful whenever this supervisor itself runs as root, including
# MANAGED_PREFIX test roots. Parentheses are intentional: -a binds tighter than -o in find.
if [ "$(id -u)" -eq 0 ]; then
  owner_bad="$(find "$OPT" -xdev \( \! -user root -o \! -group root \) -print -quit 2>/dev/null || true)"
  if [ -n "$owner_bad" ]; then
    echo "posse insegura: $owner_bad" >&2
    rollback && exit 1 || exit 70
  fi
fi

cleanup
trap - EXIT
echo "managed transaction committed"
