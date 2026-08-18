#!/usr/bin/env bash
# CONTRATO DOS INSTALADORES E DA VARREDURA DE ARENA.
#
# POR QUE ESTE ARQUIVO EXISTE, e a razao e uma assimetria medida, nao uma preferencia de estilo.
#
# A onda 12 fechou tres defeitos de severidade alta ou critica, todos no caminho PRIVILEGIADO ou
# DESTRUTIVO, e todos verificados a mao uma vez cada:
#
#   1. `install/apply.sh --help` INSTALAVA. Medido: exit 0, 66 arquivos escritos no destino.
#      Qualquer argumento que nao fosse exatamente `--dry-run` caia no ramo de aplicar.
#   2. `install/apply-managed.sh --revert --dry-run` executava um revert REAL e privilegiado: o
#      ramo fazia `exec worker "$@"` antes de qualquer contagem, e o worker so inspeciona `$1`.
#   3. A varredura de arena usava glob terminado em BARRA, o que faz `-d`, `find` e `rm -rf`
#      ATRAVESSAREM symlink. Com /tmp 1777, qualquer usuario local plantava
#      `tollens-arena.pwn -> ~/.claude` e o proximo arnes apagava a politica. Reproduzido
#      executando o bloco literal do arquivo contra um symlink.
#
# Ao mesmo tempo, a classe de MENOR severidade da mesma onda - referencia publicada que nao
# resolve - ganhou tres portoes automatizados. O portao final nomeou a inversao: a classe
# destrutiva ficou com comentario citando medicao manual de uma vez so.
#
# Medicao manual nao regride sozinha; ela regride quando alguem edita o `case`. E esta onda existe
# porque as correcoes manualmente verificadas da onda 11 precisaram de correcao.
#
# ESCOPO: contrato de ARGUMENTO e recusa de caminho hostil. Nao testa o conteudo do que e
# instalado - disso cuidam install/verify.sh e tests/unit/managed.sh.
set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1
P=0; F=0
chk(){ if [ "$2" = "$3" ]; then echo "  PASS  $1"; P=$((P+1)); else echo "  FAIL  $1 (got=$2 want=$3)"; F=$((F+1)); fi; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/tollens-ci.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------------------------------------
echo "== CI1. apply.sh: so --dry-run e ausencia de argumento chegam a escrever =="

apply_escreveu(){ # $1..= argumentos; ecoa "<exit> <arquivos escritos>"
  local d rc n
  d="$(mktemp -d "$TMP/dest.XXXXXX")"
  CLAUDE_HOME="$d" bash install/apply.sh "$@" >/dev/null 2>&1; rc=$?
  n="$(find "$d" -type f 2>/dev/null | wc -l)"
  echo "$rc $n"
}

r="$(apply_escreveu --help)"
chk "--help NAO instala"                    "${r#* }" 0
chk "--help sai 0 (e ajuda, nao erro)"      "${r%% *}" 0

r="$(apply_escreveu --dryrun)"
chk "typo --dryrun e RECUSADO"              "${r%% *}" 2
chk "typo --dryrun nao escreve"             "${r#* }" 0

r="$(apply_escreveu --dry_run)"
chk "typo --dry_run e RECUSADO"             "${r%% *}" 2

r="$(apply_escreveu --dry-run)"
chk "--dry-run sai 0"                       "${r%% *}" 0
chk "--dry-run NAO escreve (portao, nao filtro)" "${r#* }" 0

r="$(apply_escreveu --dry-run extra)"
chk "argumento em excesso e RECUSADO"       "${r%% *}" 2

r="$(apply_escreveu)"
chk "sem argumento instala"                 "${r%% *}" 0
[ "${r#* }" -gt 40 ] && { echo "  PASS  sem argumento escreve o conjunto (${r#* } arquivos)"; P=$((P+1)); } \
                     || { echo "  FAIL  sem argumento deveria escrever muitos (got=${r#* })"; F=$((F+1)); }

# ---------------------------------------------------------------------------------------------
echo "== CI2. apply.sh: backup cobre CLAUDE.md, nao so hooks/agents/skills =="
# A semeadura byte-exata torna o PRIMEIRO apply um no-op. Ela nao protege o SEGUNDO, e o segundo
# e exatamente o caso descrito por escrito em install/manifest.sh. Sem este caso, a perda de 288
# linhas de politica escrita a mao passaria em silencio.
D="$(mktemp -d "$TMP/bk.XXXXXX")"
printf 'CONFIG DIVERGENTE DO OPERADOR\n' > "$D/CLAUDE.md"
SHA_ORIG="$(sha256sum "$D/CLAUDE.md" | cut -d' ' -f1)"
CLAUDE_HOME="$D" bash install/apply.sh >/dev/null 2>&1
BK="$(find "$D/backups" -name CLAUDE.md 2>/dev/null | head -1)"
chk "existe backup do CLAUDE.md sobrescrito" "$([ -n "$BK" ] && echo sim || echo nao)" sim
chk "o backup preserva o conteudo ORIGINAL" \
    "$([ -n "$BK" ] && [ "$(sha256sum "$BK" | cut -d' ' -f1)" = "$SHA_ORIG" ] && echo sim || echo nao)" sim
chk "o destino foi de fato sobrescrito (o caso e real)" \
    "$([ "$(sha256sum "$D/CLAUDE.md" | cut -d' ' -f1)" != "$SHA_ORIG" ] && echo sim || echo nao)" sim

# ---------------------------------------------------------------------------------------------
echo "== CI3. apply-managed.sh: os quatro modos passam, o resto e recusado =="
# REGRESSAO REGISTRADA: a primeira versao do endurecimento listou so --verify|--revert e jogou
# --dry-run e --enforce em exit 2. Isso quebrou o unico passo publicado que liga
# allowManagedHooksOnly (docs/HANDOFF.md) e empurraria o operador a chamar o worker DIRETO,
# pulando snapshot, rollback e a checagem de raiz root-owned do ADR 0026. Endurecimento que
# empurra o operador para fora do mecanismo de seguranca e regressao de seguranca.
mg(){ MANAGED_PREFIX="$(mktemp -d "$TMP/mg.XXXXXX")" bash install/apply-managed.sh "$@" >/dev/null 2>&1; echo $?; }
for m in --dry-run --enforce --verify --revert --help; do
  rc="$(mg "$m")"
  [ "$rc" -ne 2 ] && { echo "  PASS  modo $m nao e recusado como desconhecido (exit=$rc)"; P=$((P+1)); } \
                  || { echo "  FAIL  modo $m foi RECUSADO (exit=2) - contrato quebrado"; F=$((F+1)); }
done
chk "argumento desconhecido e recusado"        "$(mg --typo)" 2
chk "--revert --dry-run e RECUSADO (era revert real)" "$(mg --revert --dry-run)" 2
chk "--verify extra e recusado ANTES do exec"  "$(mg --verify extra)" 2

echo "== CI4. o worker tem contagem propria (e invocavel direto) =="
mw(){ MANAGED_PREFIX="$(mktemp -d "$TMP/mw.XXXXXX")" bash install/apply-managed-worker.sh "$@" >/dev/null 2>&1; echo $?; }
chk "worker recusa argumento em excesso"       "$(mw --revert --dry-run)" 64

# ---------------------------------------------------------------------------------------------
echo "== CI5. manifest.sh nao deixa manifesto truncado quando a fonte some =="
# A cadeia medida: fonte ausente -> componente sai do manifesto -> apply.sh ve "removido" e a
# convergencia apaga o arquivo VIVO correspondente. O `exit 1` dentro de `{ } > "$OUT"` nao
# bastava: o redirecionamento ja truncara o destino ao ENTRAR no grupo.
CL="$TMP/clone"; mkdir -p "$CL"
tar -cf - --exclude=./.git --exclude='*/__pycache__' . 2>/dev/null | ( cd "$CL" && tar -xf - 2>/dev/null )
ANTES="$(wc -l < "$CL/install/manifest.lock")"
rm -f "$CL/execution/config/CLAUDE.md"
( cd "$CL" && bash install/manifest.sh install/manifest.lock >/dev/null 2>&1 ); rc=$?
DEPOIS="$(wc -l < "$CL/install/manifest.lock")"
chk "manifest.sh reprova quando a fonte do config some" "$rc" 1
chk "e o manifesto NAO foi truncado"                    "$DEPOIS" "$ANTES"
chk "a linha config sobreviveu"                         "$(grep -c '^config' "$CL/install/manifest.lock")" 1

echo "== CI6. apply.sh aborta se uma origem do manifesto nao existe =="
# Antes, `cp -a` nao tinha retorno conferido e o contador somava assim mesmo: o instalador
# imprimia "componentes instalados: 49" com o componente AUSENTE no destino.
DD="$(mktemp -d "$TMP/miss.XXXXXX")"
chk "origem ausente aborta a instalacao" \
    "$( cd "$CL" && CLAUDE_HOME="$DD" bash install/apply.sh >/dev/null 2>&1; echo $? )" 1

# ---------------------------------------------------------------------------------------------
echo "== CI7. a varredura de arena nao atravessa symlink nem toca diretorio alheio =="
# CRITICO da onda 11, achado por auditoria: glob com barra final faz -d/find/rm -rf seguirem o
# link. Este caso extrai o laco REAL do arquivo em vez de reimplementa-lo - um teste contra copia
# do laco passaria mesmo se o original regredisse.
AT="$(mktemp -d "$TMP/arena.XXXXXX")"
VIT="$TMP/vitima"; mkdir -p "$VIT/sub"; echo dados > "$VIT/importante.txt"
ln -s "$VIT" "$AT/tollens-arena.pwn"
touch -d '3 days ago' "$VIT" 2>/dev/null
sed -n '/^  for _a in /,/^  done$/p' tests/lib/arena.sh > "$TMP/varredura.sh"
if [ ! -s "$TMP/varredura.sh" ]; then
  echo "  NAO VERIFICADO: nao consegui extrair o laco de varredura de tests/lib/arena.sh" >&2
  F=$((F+1))
else
  TMPDIR="$AT" bash "$TMP/varredura.sh" >/dev/null 2>&1
  chk "o alvo do symlink sobreviveu"  "$([ -f "$VIT/importante.txt" ] && echo sim || echo nao)" sim
  chk "o symlink em si foi ignorado"  "$([ -L "$AT/tollens-arena.pwn" ] && echo sim || echo nao)" sim
fi

# ANTIVACUIDADE: o caso acima so significa algo se o laco de fato varre. Uma arena PROPRIA, sem
# dono vivo e velha, tem de ser removida - senao "vitima sobreviveu" seria verdade por inacao.
MORTA="$AT/tollens-arena.morta"; mkdir -p "$MORTA"; echo 999999 > "$MORTA/.arena-pid"
TMPDIR="$AT" bash "$TMP/varredura.sh" >/dev/null 2>&1
chk "arena propria de dono morto E removida (o laco varre mesmo)" \
    "$([ -d "$MORTA" ] && echo nao || echo sim)" sim

echo
echo "================ PASS=$P  FAIL=$F ================"
[ "$F" -eq 0 ] && echo "contrato de instalador verde" || echo "contrato de instalador VERMELHO"
exit $([ "$F" -eq 0 ] && echo 0 || echo 1)
