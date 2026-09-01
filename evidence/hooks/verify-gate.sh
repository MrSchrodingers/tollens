#!/usr/bin/env bash
# PLANO DE EVIDENCIA - verifica o snapshot e registra o veredito no ledger.  Hook: Stop.
#
# O QUE ESTE HOOK NAO E, e por que a reescrita:
# Ele NAO e o portao de conclusao. `Stop` nao pode ser fronteira de confianca, por quatro
# razoes independentes, todas verificadas:
#   - `stop_hook_active=true` na parada seguinte a um bloqueio (semantica anti-loop oficial);
#   - o runtime SOBREPOE o hook apos N bloqueios consecutivos (default 8);
#   - esse N vive em CLAUDE_CODE_STOP_HOOK_BLOCK_CAP, dentro do settings.json que o proprio
#     ator governado pode escrever - politica no espaco de escrita do governado nao e politica;
#   - `Stop` nao dispara quando o usuario interrompe a sessao nem em falha de API.
# Logo este hook produz no maximo um CANDIDATO e um registro auditavel. Quem certifica e a CI
# sobre o SHA exato, sob politica que o ator nao pode alterar.  Ver docs/adr/0022.
#
# INVARIANTES (cada um pago com defeito REPRODUZIDO - tests/unit/regressao-gate.sh):
#  G1. O cache guarda VEREDITO, nao carimbo. `pass` do mesmo snapshot e reutilizavel; `fail`
#      jamais vira verde. A versao anterior gravava (timestamp, assinatura) ANTES de executar:
#      a segunda parada dentro de 5 min achava a assinatura e saia 0 com o codigo quebrado.
#  G2. `stop_hook_active` nao pode ser verde silencioso. stderr com exit 0 NAO chega ao modelo
#      (docs/adr/0021); quem avisa sem bloquear usa additionalContext.
#  G3. A identidade e sobre BYTES. Nome nao identifica estado: a versao anterior hasheava
#      nomes + `git diff HEAD`, e `git diff` nao enxerga conteudo de arquivo untracked.
#  G4. Conjuncao sobre TODOS os adaptadores aplicaveis: Ready(x) = AND Pass(a,x). A anterior
#      parava no primeiro que casava - monorepo com JS valido e Python quebrado passava verde.
#  G5. Sem `sh -c`. O adaptador declara exec.command + exec.args[]; o executor decide o que
#      roda. String interpretada por shell permite redirecao, substituicao e composicao.
#  G6. Ferramenta ausente e LACUNA declarada, nao falha de codigo. Falso bloqueio e o que faz
#      o operador desligar o gate - e gate desligado protege zero.
#  G7. Tabela ausente e FAIL-CLOSED com aviso. Inercia silenciosa e o modo de falha que este
#      projeto inteiro combate.
#  G16. Zero unidades examinadas NAO e aprovacao. Um adaptador considerado APLICAVEL que examina
#      NADA (arquivo apagado, renomeado com conteudo divergente, symlink quebrado, ou ecossistema
#      inteiro ausente de uma arvore que uma ferramenta nao-per_file escaneia) caia no ramo de
#      APROVADO - RC nunca saia do valor de inicializacao, ou a ferramenta (ex.: ruff numa arvore
#      sem .py) saia 0 por conta propria sem examinar nada. Vira LACUNA, nunca FALHA nem PASS:
#      "nao verifiquei isto" e verdade, "reprovou" mentiria, "passou" seria o verde vazio.
set -uo pipefail

# LEITURA DO EVENTO. `$(</dev/stdin)` depende do CAMINHO `/dev/stdin` existir e ser abrivel, e
# ha processos em que ele nao e: `claude -p` lancado fora de uma sessao - um processo de desktop,
# um companion, um cron - falha com `/dev/stdin: No such device or address`. Sem `set -e`, a
# atribuicao falha em silencio e `INPUT` fica VAZIO.
#
# E ai vem o dano, que e maior que o erro: o guarda anti-loop deste hook decide por
# `stop_hook_active` LIDO DE `$INPUT`. Com `$INPUT` vazio ele nunca casa, o gate nunca
# curto-circuita, roda o verificador, reprova, re-prompta - e repete. MEDIDO PELO OPERADOR:
# 9 re-prompts, 43 mil tokens, resposta VAZIA, 43 segundos. Reproduzido aqui com `0<&-`:
# `stop_hook_active=true` com stdin normal sai 0; com stdin fechado sai 2 e bloqueia.
#
# `cat` le o DESCRITOR 0, nao um caminho, e por isso funciona onde `/dev/stdin` nao existe. O
# `[ ! -t 0 ]` evita travar quando alguem roda o hook a mao num terminal - ali nao ha evento para
# ler e esperar seria pendurar o processo.
INPUT=""
# `timeout` E OBRIGATORIO, nao zelo: medido aqui, `cat` com o descritor 0 FECHADO nao retorna -
# o hook fica pendurado no caminho critico de toda parada, que e uma forma pior do mesmo dano que
# esta correcao existe para remover. Em operacao normal o runtime fecha o cano e `cat` volta na
# hora; o limite so age no caso degenerado.
if [ ! -t 0 ]; then INPUT="$(timeout 5 cat 2>/dev/null || true)"; fi

# EVENTO ILEGIVEL NAO PODE BLOQUEAR. Se nao da para ler o evento, nao da para saber se esta parada
# JA e a continuacao de um bloqueio anterior - e bloquear sem poder ver isso e exatamente o laco
# sem fim acima. A escolha entre "portao que pode ser contornado fechando stdin" e "portao que
# gasta a cota do operador em laco e devolve vazio" nao e simetrica: o segundo e pior, e nao tem
# como parar sozinho. Declara a lacuna e libera a parada.
if [ -z "$INPUT" ]; then
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg c "GATE - EVENTO ILEGIVEL. O hook nao conseguiu ler o evento de Stop na entrada
padrao (processo sem /dev/stdin abrivel, ou stdin fechado). Sem o evento nao da para saber se esta
parada ja e continuacao de um bloqueio, entao bloquear aqui seria laco sem fim. NADA foi
verificado neste turno - nao diga verde nem vermelho." \
      '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:$c}}'
  fi
  echo "GATE - evento ilegivel na entrada padrao; nada foi verificado. Parada liberada para nao entrar em laco." >&2
  exit 0
fi
# G9: DEPENDENCIA ESTRUTURAL ausente e LACUNA, nao sucesso. Ferramenta de adaptador ausente ja
# virava lacuna (G6); ferramenta do proprio gate saia 0 em silencio - a mesma inercia que G7
# combate, no lugar mais critico. Fora de repositorio git, inerte e legitimo: nao ha o que verificar.
if ! command -v jq >/dev/null 2>&1; then
  if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # sem jq nao ha como emitir additionalContext; em continuacao forcada resta sair.
    printf '%s' "$INPUT" | grep -q '"stop_hook_active"[[:space:]]*:[[:space:]]*true' && exit 0
    { echo "GATE - dependencia estrutural ausente: 'jq' nao esta no PATH."
      echo "O verificador nao pode ler o evento nem emitir contexto. Nada foi verificado."
      echo "Estado: NAO VERIFICADO / NOT_VERIFIED."; } >&2
    exit 2
  fi
  exit 0
fi
ACTIVE="$(printf '%s' "$INPUT" | jq -r '.stop_hook_active // false' 2>/dev/null)"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
ADAPTERS="${CLAUDE_ADAPTERS_DIR:-$(cd "$HERE/../../execution/adapters/code" 2>/dev/null && pwd)}"
LEDGER_DIR="${EVIDENCE_LEDGER_DIR:-$HOME/.claude/evidence}"

# CANAIS (docs/adr/0021): exit 2 bloqueia e entrega; additionalContext avisa e nao bloqueia;
# stderr com exit 0 e inerte - nunca usar para informacao que precisa chegar.
aviso(){ jq -cn --arg c "$1" '{hookSpecificOutput:{hookEventName:"Stop",additionalContext:$c}}' 2>/dev/null; exit 0; }
barra(){ printf '%s\n' "$1" >&2; exit 2; }
# Quando o runtime ja esta em continuacao forcada, bloquear nao e opcao: avisa.
reporta(){ if [ "$ACTIVE" = "true" ]; then aviso "$1"; else barra "$1"; fi; }

# G9b: `git` ausente tambem e dependencia estrutural. Sem git nao da para usar `rev-parse`,
# entao a deteccao de "estou num repositorio" e feita subindo a arvore atras de .git (que pode
# ser diretorio ou arquivo, no caso de worktree/submodulo). Havia .git e nao havia git: sair 0
# seria dizer verde sobre um repositorio que nunca foi olhado.
if ! command -v git >/dev/null 2>&1; then
  _d="$PWD"
  while [ "$_d" != "/" ] && [ -n "$_d" ]; do
    if [ -e "$_d/.git" ]; then
      reporta "GATE - dependencia estrutural ausente: 'git' nao esta no PATH, mas '$_d/.git' existe.
Nao foi possivel determinar o que mudou. Nenhuma verificacao rodou.
Estado: NAO VERIFICADO / NOT_VERIFIED."
    fi
    _d="$(dirname "$_d")"
  done
  exit 0   # fora de repositorio: inerte e legitimo
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0
ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || exit 0
[ -n "$ROOT" ] || exit 0

# --- o que mudou: nao-commitado + untracked + commits nao publicados ---
#
# G12 - BASE DE COMPARACAO SEM UPSTREAM. Defeito reproduzido antes de corrigir: numa branch
# sem `@{u}`, o conjunto de commits nao publicados era simplesmente OMITIDO do calculo. Como
# `git commit` tambem zera `diff HEAD` e a lista de untracked, o resultado era CHANGED vazio e
# `exit 0` - o gate ficava INERTE exatamente no instante em que existe artefato pronto para
# atravessar a fronteira. Medido: branch nova com `origin/main` publicado e um commit contendo
# F821, gate saia 0 e mudo.
#
# A base honesta depende de existir fronteira a atravessar:
#   1. ha `@{u}`            -> a base e o upstream (comportamento anterior, preservado);
#   2. nao ha `@{u}` mas HA remoto -> commit local PODE ser publicado, logo precisa de base:
#      usa-se o ponto de divergencia em relacao ao alvo de publicacao (origin/HEAD, main,
#      master). Se o remoto existe mas nenhum ref dele e conhecido (remoto vazio ou sem fetch),
#      entao NENHUM commit desta arvore foi publicado e a base correta e a ARVORE VAZIA;
#   3. nao ha remoto nenhum -> nao existe fronteira externa a atravessar. Inerte segue
#      legitimo, pela mesma razao que "fora de repositorio git" e inerte: e AUSENCIA DE
#      FRONTEIRA, nao lacuna de verificacao. Declarar NOT_VERIFIED aqui seria ruido em todo
#      repositorio local, e ruido e o que faz o operador desligar o gate.
UPSTREAM="$(git -C "$ROOT" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null || true)"
BASE=""
if [ -n "$UPSTREAM" ]; then
  BASE="$UPSTREAM"
elif [ -n "$(git -C "$ROOT" remote 2>/dev/null)" ]; then
  for _c in refs/remotes/origin/HEAD refs/remotes/origin/main refs/remotes/origin/master; do
    if git -C "$ROOT" rev-parse --verify -q "$_c" >/dev/null 2>&1; then BASE="$_c"; break; fi
  done
  [ -n "$BASE" ] || BASE="$(git -C "$ROOT" hash-object -t tree /dev/null 2>/dev/null || true)"
fi
# Normaliza para um unico objeto de comparacao. `merge-base` da o ponto de divergencia (evita
# atribuir a esta branch o que veio do outro lado); quando nao ha ancestral comum - caso da
# arvore vazia - o proprio BASE serve, e `git diff <arvore> HEAD` lista tudo.
DIFFBASE=""
if [ -n "$BASE" ]; then
  DIFFBASE="$(git -C "$ROOT" merge-base "$BASE" HEAD 2>/dev/null || true)"
  [ -n "$DIFFBASE" ] || DIFFBASE="$BASE"
fi
CHANGED="$( { git -C "$ROOT" diff --name-only HEAD 2>/dev/null
              git -C "$ROOT" ls-files --others --exclude-standard 2>/dev/null
              [ -n "$DIFFBASE" ] && git -C "$ROOT" diff --name-only "$DIFFBASE" HEAD 2>/dev/null
            } | sed '/^$/d' | sort -u )"
[ -n "$CHANGED" ] || exit 0

# --- G7: tabela ausente e fail-closed ---
if [ ! -d "$ADAPTERS" ] || ! ls "$ADAPTERS"/*.json >/dev/null 2>&1; then
  reporta "GATE - tabela de adaptadores nao encontrada em '${ADAPTERS:-<vazio>}'.
O verificador esta DESLIGADO neste turno. Estado: NAO VERIFICADO.
Defina CLAUDE_ADAPTERS_DIR ou rode install/apply.sh."
fi

# --- G4: TODO adaptador cuja extensao foi tocada e aplicavel (nao so o primeiro) ---
APLICAVEIS=(); ECOS=""; EXECUTORES=""
for a in "$ADAPTERS"/*.json; do
  [ -f "$a" ] || continue
  while IFS= read -r ext; do
    [ -z "$ext" ] && continue
    if printf '%s\n' "$CHANGED" | grep -q -- "${ext}\$"; then
      # G10: adaptador que DECLARA executar codigo do repositorio nunca roda automaticamente.
      # Pago com um defeito proprio: o adaptador .NET declarava executes_repository_code=false
      # sobre `dotnet format`, e a documentacao da Microsoft adverte que ele "may restore,
      # compile, and run analyzers... Only invoke the tool against trusted code."
      if [ "$(jq -r '.declared_effects.executes_repository_code // false' "$a")" = "true" ]; then
        EXECUTORES="$EXECUTORES
  - $(jq -r '.id' "$a") ($(jq -r '.ecosystem' "$a")): declara executar codigo do repositorio; exige aprovacao"
      else
        APLICAVEIS+=("$a"); ECOS="$ECOS $(jq -r '.ecosystem // "?"' "$a")"
      fi
      break
    fi
  done < <(jq -r '.extensions[]? // empty' "$a" 2>/dev/null)
done
if [ "${#APLICAVEIS[@]}" -eq 0 ]; then
  [ -n "$EXECUTORES" ] && reporta "GATE - LACUNA DE COBERTURA: nenhum analisador seguro para o que mudou.$EXECUTORES
Nenhuma verificacao rodou. Estado: NAO VERIFICADO / NOT_VERIFIED.
Adaptador que executa codigo do repositorio so roda sob aprovacao explicita."
  exit 0
fi

# --- G8: comando do REPOSITORIO so executa com aprovacao que PERTENCE A ROOT ---
# Classe CVE-2025-59536. `.claude/verify.json` vem do repositorio clonado: sem esta trava,
# abrir um repo hostil daria execucao de comando. A lista de aprovacao vive fora de qualquer
# repo E precisa ser de root - dono != root significa que o proprio ator pode se auto-aprovar,
# e ai a aprovacao nao e autoridade, e formalidade. Mutante em tests/unit/run.sh caso 5.
AVISO_REPO=""
REPO_VERIFY="$ROOT/.claude/verify.json"
if [ -f "$REPO_VERIFY" ] && jq -e '.exec.command' "$REPO_VERIFY" >/dev/null 2>&1; then
  # SHA-256 COMPLETO, 64 hex. Ate 2026-08-04 este era o unico lugar do arquivo que truncava em
  # 16 hex - 64 bits - enquanto a identidade do ambiente logo abaixo (G11, linha ~206) ja
  # documentava que "truncar em 16 hex daria 64 bits, o que e outra propriedade". A mesma regra
  # com dois tratamentos, e o truncado era justamente o que AUTORIZA EXECUCAO de um comando
  # vindo do repositorio. Achado da auditoria externa, e a incoerencia era interna ao arquivo.
  CH="$(sha256sum "$REPO_VERIFY" 2>/dev/null | cut -d' ' -f1)"
  APPROVED="$HOME/.claude/verify-cmd-approved"
  OWNER="$(stat -c '%U' "$APPROVED" 2>/dev/null || echo '')"
  if [ -n "$CH" ] && [ -f "$APPROVED" ] && [ "$OWNER" = "root" ] \
     && grep -qE "(^|[[:space:]])${CH}([[:space:]]|$)" "$APPROVED" 2>/dev/null; then
    # --- CONTRATO EXPLICITO DE SUBSTITUICAO ---
    # Antes: `APLICAVEIS=("$REPO_VERIFY")`. O comando do projeto SUBSTITUIA todos os analisadores
    # genericos, em silencio. Um repositorio poliglota cujo verify.json so roda a suite de Python
    # perdia a checagem de Node, Go e shell sem nenhum sinal - e a perda de cobertura tinha a
    # forma de uma aprovacao. Agora a substituicao e DECLARADA e ESCOPADA: o projeto diz quais
    # ecossistemas assume, e justifica por escrito. O que ele nao reivindica continua coberto.
    SUBST="$(jq -r '.replaces[]? // empty' "$REPO_VERIFY" 2>/dev/null | tr '\n' ' ')"
    JUST="$(jq -r '.coverage_justification // ""' "$REPO_VERIFY" 2>/dev/null)"
    if [ -z "$SUBST" ] || [ -z "$JUST" ]; then
      AVISO_REPO="
NOTA: $ROOT/.claude/verify.json esta APROVADO, mas nao declara o contrato de substituicao.
NAO foi executado, e os analisadores genericos seguem valendo.
Um comando de projeto que substitui a cobertura generica precisa dizer o que assume:
  \"replaces\": [\"python\", \"node\"]         # ecossistemas que ele passa a cobrir
  \"coverage_justification\": \"...\"          # por que a cobertura dele basta para esses
Ecossistemas fora de 'replaces' continuam sendo verificados pelos adaptadores genericos."
    else
      MANTIDOS=()
      for a in "${APLICAVEIS[@]}"; do
        eco="$(jq -r '.ecosystem // "?"' "$a" 2>/dev/null)"
        case " $SUBST " in
          *" $eco "*) : ;;                    # o projeto reivindicou este ecossistema
          *) MANTIDOS+=("$a") ;;              # nao reivindicado: cobertura generica permanece
        esac
      done
      APLICAVEIS=("$REPO_VERIFY" ${MANTIDOS[@]+"${MANTIDOS[@]}"})
    fi
  else
    MOTIVO="nao esta aprovado"
    [ -z "$CH" ] && MOTIVO="nao pode ser conferido (sha256sum indisponivel) - fail-closed"
    [ -f "$APPROVED" ] && [ "$OWNER" != "root" ] && [ -n "$CH" ] \
      && MOTIVO="tem lista de aprovacao pertencente a '$OWNER', nao a root - IGNORADA"
    AVISO_REPO="
NOTA: $ROOT/.claude/verify.json existe e $MOTIVO. NAO foi executado.
Digest: ${CH:-<indisponivel>}
Se voce LEU o comando e ele e legitimo, o USUARIO aprova (caminho ABSOLUTO: dentro de sudo o
\$HOME e o de root; apague o arquivo antes se existir com dono errado, porque append nao troca dono):
  sudo sh -c 'echo \"${CH}  # $(basename "$ROOT")\" >> $HOME/.claude/verify-cmd-approved && chown root:root $HOME/.claude/verify-cmd-approved'

LIMITE DECLARADO: o digest cobre os BYTES de verify.json, nao os bytes que ele manda executar.
Um verify.json que roda \`bash scripts/verify.sh\` permanece aprovado enquanto esse script muda.
Fechar isso exige digest transitivo ou sandbox - nao esta implementado (ver README, roadmap)."
  fi
fi

# --- G3: identidade sobre BYTES do estado avaliado ---
sha(){ sha256sum 2>/dev/null | cut -c1-32; }
SNAPSHOT="$( {
    printf 'head %s\n' "$(git -C "$ROOT" rev-parse HEAD 2>/dev/null || echo none)"
    [ -n "$UPSTREAM" ] && git -C "$ROOT" rev-list "${UPSTREAM}..HEAD" 2>/dev/null
    printf '%s\n' "$CHANGED" | while IFS= read -r f; do
      if [ -f "$ROOT/$f" ]; then printf '%s %s\n' "$f" "$(sha256sum "$ROOT/$f" 2>/dev/null | cut -d' ' -f1)"
      else printf '%s absent\n' "$f"; fi
    done
  } | sha )"
VERIFIERS="$(for a in "${APLICAVEIS[@]}"; do cat "$a"; done | sha)"
# G11: identidade do AMBIENTE, nao do caminho. Hash so do path nao muda quando o binario e
# atualizado ou substituido no mesmo lugar - e ai um `pass` em cache sobrevive a troca do
# verificador. Inclui realpath, digest do executavel e a string de versao.
ENVD="$(for a in "${APLICAVEIS[@]}"; do
          c="$(jq -r '.exec.command' "$a")"
          pth="$(command -v "$c" 2>/dev/null || echo absent)"
          if [ "$pth" != "absent" ]; then
            rp="$(readlink -f "$pth" 2>/dev/null || printf '%s' "$pth")"
            # SHA-256 COMPLETO: truncar em 16 hex daria 64 bits, o que e outra propriedade.
            # Numa identidade de evidencia nao ha ganho em truncar.
            bh="$(sha256sum "$rp" 2>/dev/null | cut -d' ' -f1 || echo '?')"
            vs="$(timeout 5 "$c" --version 2>&1 | head -1 || echo '?')"
            printf '%s|%s|%s|%s\n' "$c" "$rp" "$bh" "$vs"
          else printf '%s|absent\n' "$c"; fi
        done | sha)"
# G3/G1: sem sha256sum a identidade e vazia e casaria com tudo -> fail-closed.
if [ -z "$SNAPSHOT" ] || [ -z "$VERIFIERS" ]; then
  reporta "GATE - sha256sum indisponivel; a identidade do snapshot nao pode ser calculada.
Estado: NAO VERIFICADO (fail-closed)."
fi

# --- G1: ledger append-only; so `pass` do MESMO snapshot e reutilizavel ---
KEY="$(printf '%s' "$ROOT" | sha)"
LEDGER="$LEDGER_DIR/${KEY}.jsonl"
mkdir -p "$LEDGER_DIR" 2>/dev/null || true
PRIOR="$(grep -F "\"snapshot\":\"$SNAPSHOT\"" "$LEDGER" 2>/dev/null \
         | grep -F "\"verifiers\":\"$VERIFIERS\"" | grep -F "\"env\":\"$ENVD\"" | tail -1)"
if [ -n "$PRIOR" ] && [ "$(printf '%s' "$PRIOR" | jq -r '.verdict' 2>/dev/null)" = "pass" ]; then
  exit 0   # mesmo snapshot, mesmos verificadores, mesmo ambiente, veredito aprovado
fi
# veredito anterior `fail` ou `gap` NAO e reutilizado: reexecuta. Nunca vira verde por cache.

registra(){  # $1=verdict $2=detalhe
  jq -cn --arg t "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)" --arg s "$SNAPSHOT" \
         --arg v "$VERIFIERS" --arg e "$ENVD" --arg d "$1" --arg m "$2" \
         '{ts:$t,snapshot:$s,verifiers:$v,env:$e,verdict:$d,detail:$m}' >> "$LEDGER" 2>/dev/null || true
}

# --- G5: execucao por command + args, sem shell ---
FALHAS=""; LACUNAS=""; SAIDA=""
for a in "${APLICAVEIS[@]}"; do
  ID="$(jq -r '.id // "?"' "$a")"; ECO="$(jq -r '.ecosystem // "?"' "$a")"
  CMD="$(jq -r '.exec.command' "$a")"
  TMO="$(jq -r '.limits.timeout_seconds // 120' "$a")"
  if ! command -v "$CMD" >/dev/null 2>&1; then
    LACUNAS="$LACUNAS
  - $ID: '$CMD' nao esta no PATH (ecossistema $ECO)"; continue
  fi
  mapfile -t ARGS < <(jq -r '.exec.args[]? // empty' "$a" 2>/dev/null)
  # ===================== ESCOPO DELTA (onda 25) =====================
  # A PERGUNTA QUE O PORTAO FAZ MUDA. Ate aqui ele perguntava "esta arvore esta limpa?", cuja
  # resposta nao depende do trabalho do turno. Medido no log deste proprio portao
  # (~/.claude/evidence/*.jsonl): 2942 `fail` contra 2110 `pass` em 5054 registros, e a causa de
  # TODAS as 2942 e a mesma linha - `falharam: python-analyzer`. Um portao que reprova 58% das
  # vezes por divida alheia ensina o operador a ignora-lo, e ai deixa de ser portao.
  #
  # `delta` nao e um meio-termo entre `per_file` e arvore inteira - a onda 24 tentou escolher um
  # lado e falhou nos dois. Sao DUAS CLASSES com escopos diferentes, e a decisao mora em
  # `evidence/lint-delta.py`, fora deste executor, para poder ser exercitada sem repo e sem hook.
  if [ "$(jq -r '.scope // ""' "$a")" = "delta" ]; then
    LD="$HERE/../lint-delta.py"
    if [ ! -f "$LD" ] || ! command -v python3 >/dev/null 2>&1; then
      LACUNAS="$LACUNAS
  - $ID: nucleo de delta ausente ($LD) ou python3 fora do PATH"; continue
    fi
    # RAIZES DERIVADAS, nunca lista de nomes: checkout aninhado e diretorio com `.git` proprio.
    # `.worktrees` e convencao de quem criou, nao contrato - medir por convencao erraria em todo
    # repositorio que use outro nome.
    NESTED="$(cd "$ROOT" && find . -mindepth 2 -maxdepth 4 -name .git -printf '%h\n' 2>/dev/null \
              | sed 's|^\./||' | jq -R . | jq -sc . || echo '[]')"
    HUNKS="$(cd "$ROOT" && git diff -U0 HEAD 2>/dev/null | python3 -c '
import sys,re,json,collections
h=collections.defaultdict(list); f=None
for l in sys.stdin:
    if l.startswith("+++ b/"): f=l[6:].strip()
    elif l.startswith("@@") and f:
        m=re.search(r"\+(\d+)(?:,(\d+))?", l)
        if m:
            i=int(m.group(1)); n=int(m.group(2) or 1)
            if n: h[f].append([i,i+n-1])
print(json.dumps(dict(h)))' 2>/dev/null || echo '{}')"
    # G_VAZIO NO ESCOPO DELTA. A mesma armadilha das outras duas formas, e ela e PIOR aqui:
    # um analisador sobre arvore sem nenhum arquivo do ecossistema devolve LISTA VAZIA, e lista
    # vazia atravessa o nucleo inteiro como "nada a bloquear" - aprovacao sobre nada, com todos os
    # contadores em zero e nenhum sinal. Zero diagnosticos NAO e observacao de limpeza quando nao
    # havia o que observar. `tests/unit/regressao-gate.sh` G20 mede exatamente isto, e reprovou
    # este ramo enquanto a guarda faltava.
    NEXT="$(jq -r '.extensions // [] | length' "$a" 2>/dev/null || echo 0)"
    if [ "${NEXT:-0}" -gt 0 ]; then
      PRESENTES=0
      while IFS= read -r ext; do
        [ -z "$ext" ] && continue
        n="$(git -C "$ROOT" ls-files --cached --others --exclude-standard -- "*${ext}" 2>/dev/null | wc -l)"
        PRESENTES=$((PRESENTES + n))
      done < <(jq -r '.extensions[]? // empty' "$a")
      if [ "$PRESENTES" -eq 0 ]; then
        LACUNAS="$LACUNAS
  - $ID: nenhum arquivo do ecossistema $ECO existe mais na arvore - nada para '$CMD' examinar"
        continue
      fi
    fi
    RAW="$(cd "$ROOT" && timeout "$TMO" "$CMD" "${ARGS[@]}" 2>/dev/null)"; RCTOOL=$?
    if [ "$RCTOOL" -eq 127 ]; then
      LACUNAS="$LACUNAS
  - $ID: binario interno ausente (exit 127)"; continue
    fi
    [ -n "$RAW" ] || RAW='[]'
    BLPATH="${TOLLENS_BASELINE_DIR:-$HOME/.claude/tollens/baselines}/$(printf '%s' "$ROOT" | sha256sum | cut -c1-16).$ID.json"
    BL=""; [ -f "$BLPATH" ] && BL="$(cat "$BLPATH")"
    MAPA="$(jq -c '.diagnostics.map' "$a")"
    BRK="$(jq -r '.breakage_codes // [] | join(",")' "$a")"
    TMPERR="$(mktemp "${TMPDIR:-/tmp}/tollens-delta.XXXXXX")" || TMPERR=/dev/null
    VER="$(python3 "$LD" --raw "$RAW" --map "$MAPA" --strip-prefix "$ROOT/" \
             --hunks "$HUNKS" --baseline "$BL" --nested-roots "$NESTED" \
             --breakage-codes "$BRK" 2>"$TMPERR")"; RC=$?
    OUT="$VER
$(cat "$TMPERR" 2>/dev/null)"
    [ "$TMPERR" != /dev/null ] && rm -f "$TMPERR"
    # SEMEADURA DO BASELINE, e ela e explicita e visivel. Sem baseline o portao reprovaria por
    # quebra preexistente para sempre; semear em silencio seria anistia. Semeia UMA vez, avisa, e
    # a partir dai a catraca so aceita o que ja estava la.
    if [ "$RC" -eq 1 ] && [ ! -f "$BLPATH" ] && [ "${TOLLENS_BASELINE_SEED:-1}" = "1" ]; then
      mkdir -p "$(dirname "$BLPATH")" 2>/dev/null
      # ESCRITA ATOMICA, e ela e obrigatoria aqui. `> "$BLPATH"` cria o arquivo ANTES de o
      # programa rodar: uma emissao que falha deixa um baseline VAZIO que (a) bloqueia a
      # re-semeadura pelo `[ ! -f ]` seguinte e (b) se lido, tolera NADA - o portao volta a
      # reprovar por quebra preexistente para sempre, agora com um arquivo no disco sugerindo que
      # ha catraca. Medido: foi exatamente o que aconteceu na primeira execucao ponta a ponta.
      # O BASELINE VEM DO ESTADO ANTERIOR AO TURNO, NUNCA DO ATUAL. Semear a partir da arvore
      # como ela esta agora ANISTIA a quebra que o proprio turno acabou de introduzir: a primeira
      # parada gravaria a digital do defeito recem-criado e o toleraria para sempre. Isso nao e
      # hipotese - `tests/unit/regressao-gate.sh` G1 mede exatamente essa garantia ("falha em cache
      # NAO vira sucesso na segunda parada") e reprovou com got=0 want=2 na primeira versao deste
      # ramo. O portao de regressao pegou o defeito de desenho antes de qualquer humano.
      #
      # `git archive HEAD` e LEITURA PURA: extrai o commit sem registrar worktree, sem escrever no
      # `.git` do repositorio analisado e sem tocar no indice. `git worktree add` faria as tres.
      SEEDDIR="$(mktemp -d "${TMPDIR:-/tmp}/tollens-seed.XXXXXX")" || SEEDDIR=""
      RAWBASE=""
      if [ -n "$SEEDDIR" ] && git -C "$ROOT" archive HEAD 2>/dev/null | tar -x -C "$SEEDDIR" 2>/dev/null; then
        RAWBASE="$(cd "$SEEDDIR" && timeout "$TMO" "$CMD" "${ARGS[@]}" 2>/dev/null)"
        [ -n "$RAWBASE" ] || RAWBASE='[]'
      fi
      BLTMP="$(mktemp "${BLPATH}.XXXXXX")" || BLTMP=""
      if [ -n "$BLTMP" ] && [ -n "$RAWBASE" ] && python3 "$LD" --raw "$RAWBASE" --map "$MAPA" \
           --strip-prefix "$SEEDDIR/" \
           --nested-roots "$NESTED" --breakage-codes "$BRK" --emit-baseline > "$BLTMP" 2>/dev/null \
         && [ -s "$BLTMP" ] && jq -e 'type == "array"' "$BLTMP" >/dev/null 2>&1 \
         && mv -f "$BLTMP" "$BLPATH"; then
        LACUNAS="$LACUNAS
  - $ID: catraca CRIADA agora ($(jq -r 'length' "$BLPATH" 2>/dev/null) defeito(s) preexistente(s) de HEAD passam a ser TOLERADOS, e sao reportados a cada execucao). Este turno FOI julgado contra ela. A lacuna declarada nao e o julgamento: e a TOLERANCIA recem-concedida, que nenhum humano revisou. Revise $BLPATH, ou apague-o para recriar."
        # REJULGA CONTRA O BASELINE RECEM-CRIADO, nunca `RC=0` por decreto. Forcar zero aqui
        # fazia a PRIMEIRA parada passar sempre - inclusive quando a quebra era do proprio turno,
        # que e o oposto do que a catraca existe para fazer. O baseline vem do estado ANTERIOR;
        # se o defeito nao esta nele, ele e novo e continua bloqueando.
        BL="$(cat "$BLPATH" 2>/dev/null)"
        TMPERR2="$(mktemp "${TMPDIR:-/tmp}/tollens-delta.XXXXXX")" || TMPERR2=/dev/null
        VER="$(python3 "$LD" --raw "$RAW" --map "$MAPA" --strip-prefix "$ROOT/" \
                 --hunks "$HUNKS" --baseline "$BL" --nested-roots "$NESTED" \
                 --breakage-codes "$BRK" 2>"$TMPERR2")"; RC=$?
        OUT="$VER
$(cat "$TMPERR2" 2>/dev/null)"
        [ "$TMPERR2" != /dev/null ] && rm -f "$TMPERR2"
        [ -n "${SEEDDIR:-}" ] && rm -rf "$SEEDDIR"
      else
        [ -n "${BLTMP:-}" ] && rm -f "$BLTMP"
        [ -n "${SEEDDIR:-}" ] && rm -rf "$SEEDDIR"
        LACUNAS="$LACUNAS
  - $ID: NAO foi possivel semear o baseline de quebra - o turno segue julgado SEM catraca, e quebra preexistente continua bloqueando. Nada foi gravado."
      fi
    fi
  elif [ "$(jq -r '.per_file // false' "$a")" = "true" ]; then
    # G_VAZIO (per_file): um adaptador per_file so examina os arquivos de CHANGED que ainda
    # existem no disco (`[ -f "$ROOT/$f" ] || continue`). Se apagar, renomear-com-conteudo-
    # divergente ou deixar um symlink quebrado faz TODOS os arquivos casados desaparecerem, o
    # laco nunca roda, RC fica no valor inicial 0, e o adaptador caia no ramo de APROVADO sem
    # examinar nada. Um laco que nao roda nao e observacao de sucesso - e ausencia de
    # observacao. EXAMINADOS conta unidades REALMENTE processadas; zero decide o veredito,
    # nao o RC (que nunca saiu do valor de inicializacao).
    RC=0; OUT=""; EXAMINADOS=0
    while IFS= read -r ext; do
      [ -z "$ext" ] && continue
      while IFS= read -r f; do
        [ -f "$ROOT/$f" ] || continue
        EXAMINADOS=$((EXAMINADOS + 1))
        O="$(cd "$ROOT" && timeout "$TMO" "$CMD" "${ARGS[@]}" "$f" 2>&1)" || { RC=1; OUT="$OUT
$O"; }
      done < <(printf '%s\n' "$CHANGED" | grep -- "${ext}\$" || true)
    done < <(jq -r '.extensions[]? // empty' "$a")
    if [ "$EXAMINADOS" -eq 0 ]; then
      # NAO e FALHA: um commit que so apaga arquivo e legitimo, e "reprovado" mentiria sobre a
      # causa. E LACUNA: o estado correto e "nao verifiquei isto", nomeando a razao.
      LACUNAS="$LACUNAS
  - $ID: nenhum arquivo casado com as extensoes de $ECO segue presente no disco (apagado, renomeado ou symlink quebrado) - zero unidades examinadas"
      continue
    fi
  else
    # G_VAZIO (repositorio inteiro): o mesmo defeito tem uma segunda forma. Um adaptador NAO
    # per_file roda sobre a ARVORE (o `.` de `exec.args`), nao sobre CHANGED - por isso apagar
    # UM arquivo normalmente nao esvazia o ecossistema inteiro. Mas quando o arquivo apagado
    # era o ULTIMO do ecossistema, a ferramenta roda sobre uma arvore vazia daquela linguagem.
    # Medido: `ruff check .` numa arvore sem nenhum `.py` imprime "No Python files found" e
    # sai 0 - aprovacao sobre nada. A deteccao NAO depende do texto de cada ferramenta (por
    # ferramenta seria fragil: `go vet`/`cargo fmt` erram com RC!=0 no mesmo cenario, ruff nao) -
    # conta arquivos do ecossistema presentes na ARVORE ATUAL (rastreados + untracked nao
    # ignorados), a mesma fonte que decide o que este gate considera "existir". So se aplica a
    # adaptador que DECLARA extensoes: o comando aprovado de `.claude/verify.json` (G8/G13-G15)
    # nao declara `extensions` - e um comando de repositorio inteiro sem escopo por tipo de
    # arquivo, e tratar "sem extensoes declaradas" como "zero unidades" o desligaria sempre.
    NEXT="$(jq -r '.extensions // [] | length' "$a" 2>/dev/null || echo 0)"
    if [ "${NEXT:-0}" -gt 0 ]; then
      PRESENTES=0
      while IFS= read -r ext; do
        [ -z "$ext" ] && continue
        n="$(git -C "$ROOT" ls-files --cached --others --exclude-standard -- "*${ext}" 2>/dev/null | wc -l)"
        PRESENTES=$((PRESENTES + n))
      done < <(jq -r '.extensions[]? // empty' "$a")
      if [ "$PRESENTES" -eq 0 ]; then
        LACUNAS="$LACUNAS
  - $ID: nenhum arquivo do ecossistema $ECO existe mais na arvore - nada para '$CMD' examinar"
        continue
      fi
    fi
    OUT="$(cd "$ROOT" && timeout "$TMO" "$CMD" "${ARGS[@]}" 2>&1)"; RC=$?
  fi
  if [ "$RC" -eq 127 ]; then
    LACUNAS="$LACUNAS
  - $ID: binario interno ausente (exit 127)"; continue
  fi
  if [ "$RC" -ne 0 ]; then
    FALHAS="$FALHAS $ID"
    SAIDA="$SAIDA
--- $ID ($ECO) exit=$RC ---
$(printf '%s\n' "$OUT" | tail -12)"
  fi
done

# --- veredito conjuntivo ---
if [ -n "$FALHAS" ]; then
  registra "fail" "falharam:$FALHAS"
  reporta "GATE - VERIFICACAO FALHOU. O snapshot NAO e um candidato valido.
Verificadores aplicados:$ECOS
Reprovaram:$FALHAS
$SAIDA
---
Estado: NOT_VERIFIED. O sinal e externo - nao declare corrigido por auto-avaliacao.
Este hook nao certifica nada: mesmo passando, o veredito final e da CI sobre o SHA.$AVISO_REPO"
fi
if [ -n "$LACUNAS" ]; then
  registra "gap" "lacunas:$LACUNAS"
  reporta "GATE - LACUNA DE COBERTURA, nao falha de codigo.$LACUNAS
Nenhuma verificacao externa cobriu esses caminhos neste turno.
Estado: NAO VERIFICADO - declare a lacuna ao usuario. Nao diga verde nem vermelho.$AVISO_REPO"
fi
registra "pass" "verificadores:$ECOS"
# passou, mas ha comando do repo nao aprovado: avisar sem bloquear
[ -n "$AVISO_REPO" ] && aviso "GATE - verificadores genericos passaram.$AVISO_REPO"
exit 0
