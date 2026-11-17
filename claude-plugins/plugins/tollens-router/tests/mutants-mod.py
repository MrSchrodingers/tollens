# Mutantes do mod (hooks/register.js e hooks/core.js): rodar da raiz do repositorio. Uma linha por mutante
# (MORTO ou SOBREVIVEU); sai com o total de sobreviventes. Restaura o arquivo em qualquer caso.
import subprocess
R='claude-plugins/plugins/tollens-router/hooks/register.js'
C='claude-plugins/plugins/tollens-router/hooks/core.js'
muts=[
 ('R1 shadow aplica (escolherAplicacao sem aplicar)', R, "if (r.d.aplicar !== true || !ALIASES", "if (!ALIASES"),
 ('R2 nao remove ROTA', R, "chamada = { ...e, prompt: stripRota(e.prompt) };", "chamada = { ...e };"),
 ('R3 spawn pode descer', R, "rankModelo(alvo.model) > rAtual", "rankModelo(alvo.model) !== rAtual"),
 ('R4 resume nao ignorado', R, "if (e.resume || e.fork ||", "if (e.fork ||"),
 ('R5 sentinela ignorada', R, "if (await $.fs.exists(PADRAO.sentinela) ||", "if (false && await $.fs.exists(PADRAO.sentinela) ||"),
 ('R5b sentinela da config sobrepoe a padrao', R, "if (await $.fs.exists(PADRAO.sentinela) || (cfg.sentinela !== PADRAO.sentinela && await $.fs.exists(cfg.sentinela)))", "if (await $.fs.exists(cfg.sentinela))"),
 ('R6 sem aparar', R, "const { history, aparado } = aparar(estado, chave);", "const { history, aparado } = { history: estado, aparado: false };"),
 ('R7 sem persistir', R, "          await $.store.set(key, aparar(estado, chave).history);", ""),
 ('R8 ledger aceita texto livre', C, "const SEGURO_RE = /^[A-Za-z0-9._:-]{1,80}$/;", "const SEGURO_RE = /^[\\s\\S]*$/;"),
 ('R9 excecao propaga', R, "      await ledgerErro($, cfg, est, 'tool.call', ids, err);\n      return next(e);", "      throw err;"),
 ('R10 ledger sem fila', R, "const p = est[fila].then(fn);", "const p = fn();"),
 ('R11 nota em shadow', R, "if (r.d.aplicar) return { ...res, context", "if (true) return { ...res, context"),
 ('R12 spawn aplica em shadow', R, "if (r.d.aplicar !== true || !ALIASES", "if (false || !ALIASES"),
 ('R13 teammate decidido de novo', R, "if (!e.workflow && est.decididos.has(e.tool_use_id)) return next(e);", ""),
 ('R14 chave crua no ledger', C, "c.chave.slice(0, 16) : null,", "c.chave : null,"),
 ('C1a politica vem do ambiente', R, "await lerPolitica($, cfg.politica)", "await lerPolitica($, (await $.env.get('TOLLENS_ROUTER_POLICY')) || cfg.politica)"),
 ('C1b ledger regrava arquivo alheio', R, "      if (!ehDoLedger(atual)) return;", ""),
 ('C1c rotacao sobre geracao alheia', R, "        if (!geracoes.every(ehDoLedger)) return;", ""),
 ('A1a managed ignorado', R, "if (modeloPermitido(r.d.model, r.managed)) return", "if (true) return"),
 ('A1b melhor permitido abaixo do pedido', C, "ALIASES.indexOf(c.model) >= piso)", "true)"),
 ('A1c aviso a cada chamada', R, "  if (est.avisos.has(tipo)) return;\n", ""),
 ('A2 efetivo nao gravado', R, "efetivo: rr.resolvedModel ?? null,", "efetivo: null,"),
 ('A3a ledger num arquivo so', R, "await hex16(sess)", "'x'"),
 ('A3b sessao nula persiste', R, "if (sess !== null && chave !== undefined && d.tier !== null)", "if (chave !== undefined && d.tier !== null)"),
 ('A4a falha de set propaga', R, "          reasons.push('persistencia_falhou');", "          throw new Error('x');"),
 ('A4b sem poda do store', R, "  for (const s of remover) await $.store.delete(`router.estado.${s}`);", ""),
 ('A5a texto solto conta', C, "const LINHA_ESTRUTURADA = /^(Estado", "const LINHA_ESTRUTURADA = /(Estado"),
 ('A5b async_launched e falha', C, " && st !== 'async_launched'", ""),
 ('A6a sem limite de 7 dias', C, " || reset - agoraMs > SEMANA_MS", ""),
 ('A6b leitura nao expira', C, "return idade >= 0 && idade <= RITMO_VALIDADE_MS ? ritmo.p : null;", "return ritmo.p;"),
 ('A6c percentual fora de faixa aceito', C, " || w.percentUsed < 0 || w.percentUsed > 100", ""),
 ('M1a evento nulo nao protegido', R, "    if (e === null || typeof e !== 'object') return next(e);\n    const ids = { tool_use_id: e.tool_use_id, subagentType: e.subagent_type };", "    const ids = { tool_use_id: e.tool_use_id, subagentType: e.subagent_type };"),
 ('M1b fork recebe model', R, "r.d.aplicar && typeof e.prompt === 'string' && !ehFork", "r.d.aplicar && typeof e.prompt === 'string'"),
 ('M1c papel sem normalizacao do motor', R, "const alvo = normalizarPapel(papel);", "const alvo = String(papel).toLowerCase();"),
 ('M2 sem ehDoLedger rigido (aceita qualquer JSON)', C, "plain(o) && Object.hasOwn(o, 'evento') && Object.keys(o).every((k) => CAMPOS_LEDGER.includes(k))", "plain(o)"),
]
sobrev=0
for nome,f,a,b in muts:
    orig=open(f,encoding='utf-8').read()
    if a not in orig: print('ALVO AUSENTE |',nome); sobrev+=1; continue
    open(f,'w',encoding='utf-8').write(orig.replace(a,b,1))
    try:
        r=subprocess.run(['node','--test','tests/unit/router-mod.test.mjs'],capture_output=True,text=True,timeout=180)
    finally:
        open(f,'w',encoding='utf-8').write(orig)
    print(('MORTO      | ' if r.returncode!=0 else 'SOBREVIVEU  | ')+nome)
    if r.returncode==0: sobrev+=1
print('total',len(muts),'sobreviventes/ausentes',sobrev)
