import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Mutantes do mod (hooks/register.js e hooks/core.js). Opera SEMPRE numa copia temporaria (tempfile.mkdtemp,
# respeita TMPDIR); o repositorio nunca e alterado. Uma linha por mutante:
#   MORTO      a suite falhou (returncode != 0 e ao menos um caso reprovado)
#   SOBREVIVEU a suite passou
#   ERRO DE CARGA / ERRO SEM CASO REPROVADO: o mutante nao carrega ou a execucao falhou sem reprovar caso;
#              NAO conta como morto e entra no total de pendencias.
# Sai com o total de sobreviventes, ausentes e erros.
RAIZ = Path(__file__).resolve().parents[4]
PLUGIN = 'claude-plugins/plugins/tollens-router'
TESTE = 'tests/unit/router-mod.test.mjs'
R = PLUGIN + '/hooks/register.js'
C = PLUGIN + '/hooks/core.js'
MUTS = [
 ('R1 shadow aplica (escolherAplicacao sem aplicar)', R, "if (r.d.aplicar !== true || !ALIASES", "if (!ALIASES"),
 ('R2 nao remove ROTA', R, "chamada = { ...e, prompt: stripRota(e.prompt), model: alvo.model };", "chamada = { ...e, model: alvo.model };"),
 ('R3 spawn pode descer', R, "rankModelo(alvo.model) > rAtual", "rankModelo(alvo.model) !== rAtual"),
 ('R4 resume nao ignorado', R, "if (e.resume || e.fork ||", "if (e.fork ||"),
 ('R5 sentinela ignorada', R, "if (await $.fs.exists(PADRAO.sentinela) ||", "if (false && await $.fs.exists(PADRAO.sentinela) ||"),
 ('R5b sentinela da config sobrepoe a padrao', R, "if (await $.fs.exists(PADRAO.sentinela) || (cfg.sentinela !== PADRAO.sentinela && await $.fs.exists(cfg.sentinela)))", "if (await $.fs.exists(cfg.sentinela))"),
 ('R6 sem aparar', R, "const { history, aparado } = aparar(estado, chave);", "const { history, aparado } = { history: estado, aparado: false };"),
 ('R7 sem persistir', R, "if (JSON.stringify(estado) !== antes) await $.store.set(key, aparar(estado, chave).history);", ""),
 ('R8 ledger aceita texto livre', C, "const SEGURO_RE = /^[A-Za-z0-9._:-]{1,80}$/;", "const SEGURO_RE = /^[\\s\\S]*$/;"),
 ('R9 excecao propaga', R, "      await ledgerErro($, cfg, est, 'tool.call', ids, err);\n      return next(e);", "      throw err;"),
 ('R10 ledger sem fila', R, "const p = est[fila].then(fn);", "const p = fn();"),
 ('R11 nota em shadow', R, "if (r.d.aplicar) return { ...res, context", "if (true) return { ...res, context"),
 ('R13 teammate decidido de novo', R, "if (!e.workflow && est.decididos.has(e.tool_use_id)) return next(e);", ""),
 ('R14 chave crua no ledger', C, "c.chave.slice(0, 16) : null,", "c.chave : null,"),
 ('C1a politica vem do ambiente', R, "await lerPolitica($, cfg.politica)", "await lerPolitica($, (await $.env.get('TOLLENS_ROUTER_POLICY')) || cfg.politica)"),
 ('C1b ledger regrava arquivo alheio', R, "      if (!ehDoLedger(atual)) return;", ""),
 ('C1c rotacao sobre geracao alheia', R, "        if (!geracoes.every((g) => g !== null && ehDoLedger(g))) return erro();", ""),
 ('A1a managed ignorado', R, "if (modeloPermitido(r.d.model, r.managed)) return {", "if (true) return {"),
 ('A1b melhor permitido abaixo do pedido', C, "ALIASES.indexOf(c.model) >= piso)", "true)"),
 ('A1c aviso a cada chamada', R, "  if (est.avisos.has(tipo)) return;\n", ""),
 ('A2 efetivo nao gravado', R, "efetivo: rr.resolvedModel ?? null,", "efetivo: null,"),
 ('A3a ledger num arquivo so', R, "await hex16(sess)", "'x'"),
 ('A3b sessao nula persiste', R, "if (sess !== null && chave !== undefined && d.tier !== null)", "if (chave !== undefined && d.tier !== null)"),
 ('A4a falha de set propaga', R, "        reasons.push('persistencia_falhou');", "        throw new Error('x');"),
 ('A4b sem poda do store', R, "      await $.store.delete(`router.estado.${s}`);", "      void s;"),
 ('A5a texto solto conta', C, "const LINHA_ESTRUTURADA = /^(Estado", "const LINHA_ESTRUTURADA = /(Estado"),
 ('A5b status desconhecido (running) conta como falha', C, "typeof st === 'string' && STATUS_FALHA.includes(st)", "typeof st === 'string' && st !== 'completed' && st !== 'async_launched'"),
 ('A6a sem limite de 7 dias', C, " || reset - agoraMs > SEMANA_MS", ""),
 ('A6b leitura nao expira', C, "return idade >= 0 && idade <= RITMO_VALIDADE_MS ? ritmo.p : null;", "return ritmo.p;"),
 ('A6c percentual fora de faixa aceito', C, " || w.percentUsed < 0 || w.percentUsed > 100", ""),
 ('M1a evento nulo nao protegido', R, "    if (e === null || typeof e !== 'object') return next(e);\n    const ids = { tool_use_id: e.tool_use_id, subagentType: e.subagent_type };", "    const ids = { tool_use_id: e.tool_use_id, subagentType: e.subagent_type };"),
 ('M1b fork recebe model', R, "r.d.aplicar && typeof e.prompt === 'string' && !ehFork", "r.d.aplicar && typeof e.prompt === 'string'"),
 ('M1c papel sem normalizacao do motor', R, "const alvo = normalizarPapel(papel);", "const alvo = String(papel).toLowerCase();"),
 ('M2 sem ehDoLedger rigido (aceita qualquer JSON)', C, "plain(o) && Object.hasOwn(o, 'evento') && Object.keys(o).every((k) => CAMPOS_LEDGER.includes(k))", "plain(o)"),
 ('D1a fallback abaixo do piso do motor', R, " && nivelIdx(alt.tier) >= nivelIdx(r.d.floor)", ""),
 ('D1b strip da ROTA sem model aplicado', R, "        if (alvo !== null) {\n          chamada = { ...e, prompt: stripRota(e.prompt), model: alvo.model };", "        chamada = { ...e, prompt: stripRota(e.prompt) };\n        if (alvo !== null) {\n          chamada = { ...chamada, model: alvo.model };"),
 ('D1c managed_nega_piso sem aviso unico', R, "avisar($, est, semPiso ? 'managed_piso' : 'managed', e.tool_use_id", "avisar($, { ...est, avisos: new Set() }, semPiso ? 'managed_piso' : 'managed', e.tool_use_id"),
 ('D1d managed relido a cada decisao', R, "  if (c && agora >= c.ts && agora - c.ts < 30000) return c.valor;\n", ""),
 ('D1e cache do managed nunca expira', R, "agora >= c.ts && agora - c.ts < 30000", "agora >= c.ts"),
 ('D2 carimbo nao refrescado em sessao ativa', R, "if (atual && agora >= atual[1] && agora - atual[1] < 3600000) return;", "if (atual) return;"),
 ('D3 leitura que falha regrava vazio', R, "return existe === true ? null : '';", "return '';"),
 ('S1 revisor conta REPROVADO/REFUTADO', C, "(revisor ? LINHA_NAO_VERIFICADO : LINHA_ESTRUTURADA).test(texto)", "LINHA_ESTRUTURADA.test(texto)"),
 ('S2 linha NAO VERIFICADO nao conta para revisor', C, "const LINHA_NAO_VERIFICADO = /^(Estado|Veredito|Resultado):[ \\t]*(NAO VERIFICADO|N\\u00c3O VERIFICADO)/im;", "const LINHA_NAO_VERIFICADO = /^(Estado|Veredito|Resultado):[ \\t]*(ZZZ)/im;"),
 ('R4a1 carimbo nao refrescado em registrarFalha', R, "      await registrarSessao($, r.sess, await $.clock.now());", "      await 0;"),
 ('R4a2 carimbo so refrescado quando o estado muda', R, "if (JSON.stringify(estado) !== antes) await $.store.set(key, aparar(estado, chave).history);\n        await registrarSessao($, sess, agora);", "if (JSON.stringify(estado) !== antes) { await $.store.set(key, aparar(estado, chave).history);\n        await registrarSessao($, sess, agora); }"),
 ('R4b1 estado gravado depois do indice e das remocoes', R, "if (JSON.stringify(estado) !== antes) await $.store.set(key, aparar(estado, chave).history);\n        await registrarSessao($, sess, agora);", "await registrarSessao($, sess, agora);\n        if (JSON.stringify(estado) !== antes) await $.store.set(key, aparar(estado, chave).history);"),
 ('R4b2 falha de delete propaga', R, "    try {\n      await $.store.delete(`router.estado.${s}`);\n    } catch {\n      // estado orfao de sessao ja fora do indice\n    }", "    await $.store.delete(`router.estado.${s}`);"),
 ('R4c leitura vazia de arquivo existente regrava', R, "return existe === true && t === '' ? null : t;", "return t;"),
 ('R4d1 rotacao bloqueada sem registro de erro', R, "g !== null && ehDoLedger(g))) return erro();", "g !== null && ehDoLedger(g))) return;"),
 ('R4d2 lacuna entre geracoes duplica conteudo', R, "while (n < GERACOES && geracoes[n] !== '') n++;", "n = GERACOES;"),
 ('Y3 managed availableModels ignorado', C, "  if (Array.isArray(managed.available) && managed.available.length > 0 && !casa(managed.available)) return false;\n", ""),
 ('Y5 casamento exato em vez de por token', C, "lista.some((x) => tokens(x).includes(alias))", "lista.some((x) => typeof x === 'string' && x.toLowerCase() === alias)"),
 ('Y6 fork case-sensitive', R, "e.subagent_type.toLowerCase() === 'fork'", "e.subagent_type === 'fork'"),
]


def carrega(raiz):
    cod = ("await import(process.argv[1]); await import(process.argv[2]);")
    r = subprocess.run(['node', '--input-type=module', '-e', cod, (raiz / R).as_uri(), (raiz / C).as_uri()],
                       capture_output=True, text=True, timeout=60)
    return r.returncode == 0, r.stderr.strip().splitlines()[-1:] 

def roda(raiz):
    r = subprocess.run(['node', '--test', '--test-reporter=tap', TESTE], cwd=raiz, capture_output=True, text=True, timeout=180)
    m = re.search(r'^# fail (\d+)', r.stdout, re.M)
    return r.returncode, int(m.group(1)) if m else None

tmp = Path(tempfile.mkdtemp(prefix='router-mutantes-'))
pend = 0
try:
    (tmp / 'tests/unit').mkdir(parents=True)
    shutil.copy(RAIZ / TESTE, tmp / TESTE)
    shutil.copytree(RAIZ / PLUGIN, tmp / PLUGIN)
    for nome, f, a, b in MUTS:
        alvo = tmp / f
        orig = alvo.read_text(encoding='utf-8')
        if a not in orig:
            print('ALVO AUSENTE |', nome)
            pend += 1
            continue
        alvo.write_text(orig.replace(a, b, 1), encoding='utf-8')
        try:
            ok, msg = carrega(tmp)
            if not ok:
                print('ERRO DE CARGA (nao e morto) |', nome, msg)
                pend += 1
                continue
            rc, falhas = roda(tmp)
        finally:
            alvo.write_text(orig, encoding='utf-8')
        if rc != 0 and falhas:
            print('MORTO       |', nome)
        elif rc != 0:
            print('ERRO SEM CASO REPROVADO (nao e morto) |', nome)
            pend += 1
        else:
            print('SOBREVIVEU  |', nome)
            pend += 1
finally:
    shutil.rmtree(tmp, ignore_errors=True)
print('total', len(MUTS), 'sobreviventes/ausentes/erros', pend)
sys.exit(1 if pend else 0)
