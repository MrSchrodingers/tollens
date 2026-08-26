#!/usr/bin/env bash
# INSTALADOR: repositorio -> ~/.claude, a partir do manifesto. Idempotente.
#
# Regra que este arquivo existe para tornar verdadeira: nao existe "instalar manualmente".
# `cp hook.sh ~/.claude` foi como o sistema divergiu do repositorio sem ninguem perceber.
# Aqui: manifesto -> installer -> verificador. Backup antes de qualquer escrita.
#
# ESCOPO DESTA FASE: escopo de usuario. A politica continua gravavel pelo ator governado -
# limitacao DECLARADA, nao resolvida. A fase 2 (managed settings root-owned +
# allowManagedHooksOnly) exige sudo e so deve rodar depois que todo hook estiver versionado,
# porque allowManagedHooksOnly desliga de uma vez todo hook de escopo de usuario.
set -uo pipefail
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
DEST="${CLAUDE_HOME:-$HOME/.claude}"
MAN="install/manifest.lock"
# ONDA 12. ARGUMENTO DESCONHECIDO APLICAVA. A linha anterior era
# `DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1`: qualquer coisa que nao fosse exatamente
# `--dry-run` caia em DRY=0, isto e, em INSTALAR. Medido, nao inferido:
#
#   $ CLAUDE_HOME="$(mktemp -d)" bash install/apply.sh --help
#   exit=0 ; arquivos escritos no destino: 66
#
# O modo "ajuda" instalava o sistema inteiro. Um typo (`--dryrun`, `--dry_run`) fazia o mesmo, em
# silencio e com exit 0 - indistinguivel de sucesso do que o operador pediu.
DRY=0
case "${1:-}" in
  "")         : ;;
  --dry-run)  DRY=1 ;;
  --help|-h)  printf 'uso: %s [--dry-run]\n  --dry-run  mostra o plano, NAO escreve nada\n' "$0"; exit 0 ;;
  *)          printf 'ERRO: argumento desconhecido: %s\nuso: %s [--dry-run]\n' "$1" "$0" >&2; exit 2 ;;
esac
[ "$#" -le 1 ] || { printf 'ERRO: argumentos em excesso (%s)\nuso: %s [--dry-run]\n' "$#" "$0" >&2; exit 2; }

[ -f "$MAN" ] || bash install/manifest.sh >/dev/null

# DRY-RUN E UM PORTAO, NAO UM FILTRO. A versao anterior filtrava a copia mas caia na etapa de
# convergencia e chegava a executar `rm -rf` antes de checar DRY - o modo anunciado como
# inspecao segura apagava componente. Medido: --dry-run removeu o arquivo e o digest do HOME
# voltou ao estado anterior. Agora tudo que escreve fica DEPOIS deste bloco.
if [ "$DRY" -eq 1 ]; then
  echo "== plano (nada sera escrito) =="
  LOCK_D="$DEST/tollens/managed-files.lock"
  NOVO_D="$(awk -F"\t" '!/^#/{print $3}' "$MAN")"
  n=0
  while IFS=$'\t' read -r tipo origem destino digest; do
    case "$tipo" in ''|'#'*) continue;; esac
    if [ -e "$DEST/$destino" ]; then printf '  [dry] atualiza  %s\n' "$destino"
    else printf '  [dry] instala   %s\n' "$destino"; fi
    n=$((n+1))
  done < "$MAN"
  if [ -f "$LOCK_D" ]; then
    while IFS= read -r antigo; do
      [ -n "$antigo" ] || continue
      printf '%s\n' "$NOVO_D" | grep -qxF "$antigo" && continue
      [ -e "$DEST/$antigo" ] && printf '  [dry] REMOVERIA %s (saiu do manifesto)\n' "$antigo"
    done < "$LOCK_D"
  fi
  echo "  [dry] $n componentes; nenhuma escrita, remocao ou backup realizados."
  exit 0
fi

TS="$(date +%Y%m%d-%H%M%S)"
BK="$DEST/backups/apply-$TS"

if [ "$DRY" -eq 0 ]; then
  mkdir -p "$BK"
  for d in hooks agents skills; do [ -d "$DEST/$d" ] && cp -a "$DEST/$d" "$BK/" 2>/dev/null; done
  # ONDA 12. `CLAUDE.md` entrou aqui junto com o tipo `config`, e o conjunto de backup NAO o
  # cobria. Medido: destino com CLAUDE.md divergente -> apply sobrescreve -> zero copia
  # recuperavel. A semeadura byte-exata torna o PRIMEIRO apply um no-op; ela nao protege o
  # segundo, e o segundo e exatamente o caso que `install/manifest.sh` descreve por escrito
  # ("o proximo apply.sh SOBRESCREVE essa edicao"). Reconhecer a consequencia em comentario e
  # nao estender o mecanismo que existe para ela e o defeito que este repositorio persegue.
  # Sao 288 linhas de politica escrita a mao, e a perda seria irreversivel.
  for f in settings.json CLAUDE.md; do [ -f "$DEST/$f" ] && cp -a "$DEST/$f" "$BK/" 2>/dev/null; done
  echo "backup: $BK"
fi

# CONFINAMENTO DE CAMINHO - o furo gemeo do que a auditoria de 2026-08-04 achou em
# `apply-managed.sh`. Aqui a escrita e do USUARIO, nao de root, entao nao ha escalada de
# privilegio; mas o alvo e `~/.claude`, isto e, OS PROPRIOS HOOKS QUE CONSTITUEM A POLITICA, e
# `rm -rf "$alvo"` com `destino` hostil apaga fora de `$DEST`. Corrigir so o instalador managed
# deixaria a mesma classe aberta no caminho que roda todo dia.
# Rejeita e ABORTA - nao saneia: caminho hostil saneado deixa duvida sobre o que sobrou.
confinado(){ # $1=candidato $2=raiz
  local c r
  c="$(realpath -m "$1" 2>/dev/null)" || return 1
  r="$(realpath -m "$2" 2>/dev/null)" || return 1
  case "$c" in "$r"|"$r"/*) return 0 ;; *) return 1 ;; esac
}
RUINS=0
while IFS=$'\t' read -r tipo origem destino digest; do
  case "$tipo" in ''|'#'*) continue;; esac
  case "$destino" in ""|/*|../*|*/../*|*/..|"..") echo "  DESTINO INVALIDO: [$destino]"; RUINS=$((RUINS+1)); continue;; esac
  case "$origem"  in ""|/*|../*|*/../*|*/..|"..") echo "  ORIGEM INVALIDA: [$origem]";  RUINS=$((RUINS+1)); continue;; esac
  confinado "$DEST/$destino" "$DEST" || { echo "  DESTINO ESCAPA DE $DEST: [$destino]"; RUINS=$((RUINS+1)); }
  confinado "$PWD/$origem" "$PWD"    || { echo "  ORIGEM ESCAPA DO REPO: [$origem]";    RUINS=$((RUINS+1)); }
done < "$MAN"
if [ "$RUINS" -ne 0 ]; then
  echo "ERRO: manifesto rejeitado - caminho fora dos limites. NADA foi instalado." >&2
  echo "      Regenere com 'bash install/manifest.sh' e inspecione o diff." >&2
  exit 1
fi

N=0
while IFS=$'\t' read -r tipo origem destino digest; do
  case "$tipo" in ''|'#'*) continue;; esac
  alvo="$DEST/$destino"
  mkdir -p "$(dirname "$alvo")"
  # ONDA 12, defeito PRE-EXISTENTE achado ao provar outra coisa: `cp -a` nao tinha retorno
  # conferido, e `N` somava de qualquer jeito. Com a origem ausente o instalador imprimia
  # "componentes instalados: 49" e o componente NAO estava no destino - medido num clone sem
  # `execution/config/CLAUDE.md`. Contar como instalado o que falhou e a forma exata que este
  # repositorio persegue: o numero verde declarando um estado que nao existe.
  if ! [ -e "$origem" ]; then
    echo "ERRO: origem do manifesto ausente: [$origem] -> [$destino]" >&2
    echo "      Instalacao ABORTADA. Regenere com 'bash install/manifest.sh'." >&2
    exit 1
  fi
  if [ -d "$origem" ]; then rm -rf "$alvo"; cp -a "$origem" "$alvo" || { echo "ERRO: falha ao copiar [$origem]" >&2; exit 1; }
  else cp -a "$origem" "$alvo" || { echo "ERRO: falha ao copiar [$origem]" >&2; exit 1; }
    case "$destino" in hooks/*|*/document-tools/*) chmod +x "$alvo";; esac; fi
  N=$((N+1))
done < "$MAN"
echo "componentes instalados: $N"

# CONVERGENCIA: apply(desired, installed) tem de resultar em installed == desired. Sem isto,
# componente removido do manifesto continuava instalado e ativo, e rodar apply de novo NAO
# resolvia o drift que o verify apontava. Remove apenas o que ESTE instalador gerenciou antes -
# nunca arquivo desconhecido em ~/.claude, que pode pertencer a outro sistema.
LOCK="$DEST/tollens/managed-files.lock"
NOVO="$(awk -F"\t" '!/^#/{print $3}' "$MAN")"
if [ -f "$LOCK" ]; then
  while IFS= read -r antigo; do
    [ -n "$antigo" ] || continue
    printf '%s\n' "$NOVO" | grep -qxF "$antigo" && continue
    if [ -e "$DEST/$antigo" ]; then rm -rf "${DEST:?}/$antigo"; echo "  removido (saiu do manifesto): $antigo"; fi
  done < "$LOCK"
fi
mkdir -p "$(dirname "$LOCK")"; printf '%s\n' "$NOVO" > "$LOCK"

# --- registro de hooks no settings.json, preservando as demais chaves ---
S="$DEST/settings.json"; [ -f "$S" ] || echo '{}' > "$S"
# A lista de hooks NAO vive mais aqui. `install/hooks-spec.sh` e a fonte unica, consumida
# tambem por `install/apply-managed.sh`. Duas copias da mesma lista divergiriam em silencio -
# e o defeito central deste repositorio, e ele ja reincidiu como comentario obsoleto dentro de
# um hook. `$HOME` sai LITERAL: quem o expande e o runtime, na execucao.
HOOKS_JSON="$(bash "$(dirname "$0")/hooks-spec.sh" '$HOME/.claude/hooks')" || {
  echo "ERRO: nao foi possivel gerar a especificacao de hooks"; exit 1; }
TMPS="$(mktemp)"
if jq --argjson h "$HOOKS_JSON" \
      --arg ad "$DEST/tollens/adapters/code" --arg dd "$DEST/tollens/adapters/documents" \
      --arg rp "$REPO" \
      '.hooks=$h | .env=((.env//{}) + {CLAUDE_ADAPTERS_DIR:$ad, DOC_ADAPTERS_DIR:$dd, TOLLENS_REPO:$rp})' \
      "$S" > "$TMPS" 2>/dev/null && jq -e . "$TMPS" >/dev/null 2>&1; then
  mv "$TMPS" "$S"; echo "settings.json: hooks registrados, demais chaves preservadas"
else
  rm -f "$TMPS"; echo "ERRO: nao foi possivel atualizar settings.json - nada foi alterado nele"; exit 1
fi

echo; echo "=== conformidade pos-instalacao ==="
bash install/verify.sh; _VRC=$?

# ONDA 22c. O INSTALADOR NAO REPROVA POR ESCOPO QUE NAO INSTALA. Ate aqui a chamada acima era o
# ULTIMO comando do arquivo, entao o exit do verificador virava o exit deste instalador. Quando o
# verificador passou a auditar tambem o escopo managed, `apply.sh` - que instala EXCLUSIVAMENTE a
# projecao de usuario - passou a sair 1 em toda maquina sem a fase managed implantada, com os 48
# componentes corretamente instalados. Medido na CI em d4fd41b (runs 33007234824/33007230205):
# "componentes instalados: 48" seguido de exit 1.
#
# Implantar managed exige root e uma arvore de origem root-owned (ADR 0026); esta chamada roda como
# o ator. Reprovar aqui e reprovar por algo que este script nao pode consertar - e o operador que
# segue o caminho documentado ve o instalador falhar sem ter feito nada errado.
#
# O que este script responde e "a projecao de usuario ficou como o manifesto declara". Os demais
# estados sao REPORTADOS com o passo acionavel, nunca silenciados, e nunca convertidos em falha
# deste instalador.
case "$_VRC" in
  0) exit 0 ;;
  1) exit 1 ;;   # projecao de USUARIO divergente: e deste script, propaga
  3) printf '\nA projecao de usuario esta instalada. A fase managed NAO esta implantada nesta\n'
     printf 'maquina - enquanto isso, a politica em vigor e gravavel pelo ator governado.\n'
     printf 'Para implantar (exige root e arvore de origem root:root, ver docs/adr/0026):\n'
     printf '  sudo bash %s/install/apply-managed.sh --enforce\n' "$REPO"
     exit 0 ;;
  4) printf '\nATENCAO: a fase managed esta implantada mas GRAVAVEL pelo ator. A imposicao nao se\n'
     printf 'sustenta: quem e governado pode reescrever a politica que o governa. Isto NAO e\n'
     printf 'consertavel por este instalador, e nao deve ser lido como conformidade.\n'
     printf '  sudo bash %s/install/apply-managed.sh --verify\n' "$REPO"
     exit 0 ;;
  *) exit "$_VRC" ;;
esac
