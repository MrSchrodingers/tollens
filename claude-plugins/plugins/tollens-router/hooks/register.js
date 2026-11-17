// Mod tollens-router (R2): liga o motor puro (../engine.mjs) ao Claude Code. Protocolo e limites em
// CONTRATO.md. Todo uso de `$` fica neste arquivo (o analisador estatico nao segue `$` para outros).
//
// Modos (da politica): `shadow` e `off` NAO alteram a chamada; so `enforce` aplica model e effort.
// Falha aberta: qualquer excecao deixa a chamada inalterada e grava uma linha de erro sem conteudo.
import { decide, parseRota, stripRota } from '../engine.mjs';
import {
  ALIASES, NOTA_FALHA, aparar, autorTierMax, calcularRitmo, derivarChave, estadoDoRitmo, linhaDeLedger,
  nomeDoErro, normalizarEstado, rankModelo, sinalDeFalha,
} from './core.js';

const POLITICA_PADRAO = '/etc/claude-code/router-policy.json';
const SENTINELA_PADRAO = '/etc/claude-code/router-off';
const ROTACAO_BYTES = 2097152;
const GERACOES = 3;
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];

// Estado de processo (reiniciado a cada reload): ultimo ritmo medido e chamadas ja decididas.
let ritmo = null;
const decididos = new Set();
let filaEstado = Promise.resolve();
let filaLedger = Promise.resolve();

function serializarEstado(fn) {
  const p = filaEstado.then(fn);
  filaEstado = p.then(() => undefined, () => undefined);
  return p;
}

function serializarLedger(fn) {
  const p = filaLedger.then(fn);
  filaLedger = p.then(() => undefined, () => undefined);
  return p;
}

function lembrar(id) {
  if (typeof id !== 'string' || id === '') return;
  decididos.add(id);
  if (decididos.size > 500) decididos.delete(decididos.values().next().value);
}

async function caminhos($) {
  const politica = await $.env.get('TOLLENS_ROUTER_POLICY');
  const sentinela = await $.env.get('TOLLENS_ROUTER_SENTINEL');
  const ledger = await $.env.get('TOLLENS_ROUTER_LEDGER');
  const home = await $.env.get('HOME');
  return {
    politica: politica || POLITICA_PADRAO,
    sentinela: sentinela || null,
    ledger: ledger || (home ? `${home}/.claude/logs/router-ledger.jsonl` : null),
  };
}

async function lerPolitica($, caminho) {
  let texto;
  try {
    texto = await $.fs.read(caminho);
  } catch {
    return { policy: null, motivo: 'politica_ausente' };
  }
  if (typeof texto !== 'string' || texto.length > 1048576) return { policy: null, motivo: 'politica_ilegivel' };
  try {
    return { policy: JSON.parse(texto), motivo: null };
  } catch {
    return { policy: null, motivo: 'politica_ilegivel' };
  }
}

// Ledger JSONL append-only; rotacao em 3 geracoes (.1 mais nova). Nunca lanca.
async function gravarLedger($, cfg, linha) {
  if (!cfg || !cfg.ledger) return;
  await serializarLedger(async () => {
    try {
      let atual = '';
      try {
        atual = await $.fs.read(cfg.ledger);
      } catch {
        atual = '';
      }
      if (typeof atual !== 'string') atual = '';
      if (atual.length > ROTACAO_BYTES) {
        for (let g = GERACOES; g >= 2; g--) {
          let src = '';
          try {
            src = await $.fs.read(`${cfg.ledger}.${g - 1}`);
          } catch {
            src = '';
          }
          if (typeof src === 'string' && src !== '') await $.fs.write(`${cfg.ledger}.${g}`, src);
        }
        await $.fs.write(`${cfg.ledger}.1`, atual);
        atual = '';
      }
      await $.fs.write(cfg.ledger, `${atual}${linha}\n`);
    } catch {
      // sem ledger nao ha o que registrar; a chamada segue
    }
  });
}

async function ledgerErro($, evento, ids, err) {
  try {
    const cfg = await caminhos($);
    let ts = null;
    try {
      ts = new Date(await $.clock.now()).toISOString();
    } catch {
      ts = null;
    }
    let sess = null;
    try {
      sess = await $.session.id();
    } catch {
      sess = null;
    }
    await gravarLedger($, cfg, linhaDeLedger({
      ts, evento, session_id: sess, tool_use_id: ids.tool_use_id, agent_type: ids.subagentType,
      role: ids.subagentType, erro: nomeDoErro(err),
    }));
  } catch {
    // nada mais a fazer: a chamada segue inalterada
  }
}

const ehRevisor = (policy, papel) => {
  const alvo = typeof papel === 'string' ? papel.split(':').pop().trim().toLowerCase() : '';
  return Array.isArray(policy && policy.reviewer_roles) && policy.reviewer_roles.some((r) => typeof r === 'string' && r.trim().toLowerCase() === alvo);
};

// Decide uma delegacao. Persiste o estado ANTES de devolver (protocolo d), em qualquer modo.
async function decidir($, c) {
  const cfg = await caminhos($);
  const agora = await $.clock.now();
  const sess = await $.session.id();
  const base = {
    ts: new Date(agora).toISOString(), evento: c.evento, session_id: sess, tool_use_id: c.tool_use_id,
    agent_type: c.subagentType, role: c.subagentType,
  };
  const sentinelas = [SENTINELA_PADRAO];
  if (cfg.sentinela && cfg.sentinela !== SENTINELA_PADRAO) sentinelas.push(cfg.sentinela);
  for (const s of sentinelas) {
    if (await $.fs.exists(s)) {
      return { cfg, off: true, linha: { ...base, mode: 'off', modo_efetivo: 'off', reasons: ['sentinela_off'] } };
    }
  }
  const { policy, motivo } = await lerPolitica($, cfg.politica);
  const chave = await derivarChave(c.subagentType, c.descricao);
  const estadoRitmo = estadoDoRitmo(ritmo ? ritmo.p : null, policy);

  return serializarEstado(async () => {
    const key = `router.estado.${sess}`;
    const estado = normalizarEstado(await $.store.get(key));
    const { history, aparado } = aparar(estado, chave);
    const max = autorTierMax(estado);
    if (max !== undefined) history.autorTierMax = max;
    const entrada = {
      now: agora, prompt: typeof c.prompt === 'string' ? c.prompt : '', subagentType: typeof c.subagentType === 'string' ? c.subagentType : '',
      role: typeof c.subagentType === 'string' ? c.subagentType : '', history, pace: { estado: estadoRitmo },
    };
    if (chave !== undefined) entrada.chave = chave;
    const d = decide(JSON.parse(JSON.stringify(entrada)), policy);
    const reasons = [...d.reasons];
    if (motivo) reasons.push(motivo);
    if (aparado) reasons.push('history_aparado');

    if (chave !== undefined && d.tier !== null) {
      const antes = JSON.stringify(estado);
      if (d.subida_concedida && !estado.subidasConcedidas.includes(chave)) estado.subidasConcedidas.push(chave);
      if (!ehRevisor(policy, c.subagentType)) estado.autorTierPorChave[chave] = d.tier;
      const critica = reasons.includes('piso_superficie_de_risco') || ehRevisor(policy, c.subagentType);
      if (critica && !estado.chavesCriticas.includes(chave)) estado.chavesCriticas.push(chave);
      if (JSON.stringify(estado) !== antes) await $.store.set(key, aparar(estado, chave).history);
    }
    const pace = { estado: estadoRitmo, p: ritmo ? ritmo.p : null };
    return { cfg, off: false, policy, d, reasons, chave, base, pace, sess };
  });
}

function linhaDaDecisao(r, aplicado, extra) {
  const f = extra && extra.ficha ? extra.ficha : null;
  return {
    ...r.base, chave: r.chave, ficha: f, floor: r.d.floor, tier_base: r.d.tier_base, tier: r.d.tier,
    pedido: { model: r.d.model, effort: r.d.effort }, aplicado, mode: r.d.mode, modo_efetivo: r.d.modo_efetivo,
    pace: r.pace, capped: r.d.capped, subida_concedida: r.d.subida_concedida, reasons: r.reasons,
    ...(extra && extra.sinal ? { sinal: extra.sinal } : {}),
  };
}

function modeloAplicavel(r) {
  const al = r.policy && Array.isArray(r.policy.model_allowlist) ? r.policy.model_allowlist : [];
  return r.d.aplicar === true && ALIASES.includes(r.d.model) && al.includes(r.d.model);
}

async function registrarFalha($, r) {
  return serializarEstado(async () => {
    const key = `router.estado.${r.sess}`;
    const estado = normalizarEstado(await $.store.get(key));
    estado.falhasPorChave[r.chave] = (estado.falhasPorChave[r.chave] || 0) + 1;
    if (!estado.ordem.includes(r.chave)) estado.ordem.push(r.chave);
    await $.store.set(key, aparar(estado, r.chave).history);
  });
}

function fichaDe(prompt) {
  const p = parseRota(prompt);
  return p.ok ? { c: p.ficha.c, r: p.ficha.r, v: p.ficha.v } : null;
}

export function register(on) {
  on('tool.call', { tool: ['Agent', 'Task'] }, async ($, e, next) => {
    const ids = { tool_use_id: e.tool_use_id, subagentType: e.subagent_type };
    let r;
    try {
      r = await decidir($, { evento: 'tool.call', subagentType: e.subagent_type, descricao: e.description, prompt: e.prompt, tool_use_id: e.tool_use_id });
    } catch (err) {
      await ledgerErro($, 'tool.call', ids, err);
      return next(e);
    }
    if (r.off) {
      await gravarLedger($, r.cfg, linhaDeLedger(r.linha));
      return next(e);
    }
    lembrar(e.tool_use_id);
    let chamada = e;
    let aplicado = null;
    try {
      if (r.d.aplicar && typeof e.prompt === 'string') {
        if (modeloAplicavel(r)) {
          const efetivo = EFFORTS.includes(r.d.effort) ? r.d.effort : undefined;
          chamada = { ...e, model: r.d.model, prompt: stripRota(e.prompt) };
          if (efetivo !== undefined) chamada.effort = efetivo;
          aplicado = { model: r.d.model, effort: efetivo ?? null };
        } else {
          r.reasons.push('modelo_fora_da_allowlist');
        }
      }
      await gravarLedger($, r.cfg, linhaDeLedger(linhaDaDecisao(r, aplicado, { ficha: fichaDe(e.prompt) })));
    } catch (err) {
      await ledgerErro($, 'tool.call', ids, err);
      chamada = e;
    }
    const res = await next(chamada);
    try {
      const sinal = sinalDeFalha(res);
      if (sinal && r.chave !== undefined) {
        await registrarFalha($, r);
        await gravarLedger($, r.cfg, linhaDeLedger({ ...r.base, evento: 'resultado', chave: r.chave, tier: r.d.tier, mode: r.d.mode, modo_efetivo: r.d.modo_efetivo, sinal }));
        if (r.d.aplicar) return { ...res, context: [...(Array.isArray(res.context) ? res.context : []), NOTA_FALHA] };
      }
    } catch (err) {
      await ledgerErro($, 'tool.call', ids, err);
    }
    return res;
  });

  on('agent.spawn', async ($, e, next) => {
    // Subagente comum e fork: decididos no tool.call. Aqui so workflow, teammate (sem tool.call
    // anterior) e retomada (ignorada: so pode ser recusada).
    if (e.resume || e.fork || !(e.workflow || e.isTeammate)) return next(e);
    if (!e.workflow && decididos.has(e.tool_use_id)) return next(e);
    const ids = { tool_use_id: e.tool_use_id, subagentType: e.subagentType };
    let r;
    try {
      r = await decidir($, { evento: 'agent.spawn', subagentType: e.subagentType, descricao: e.description, prompt: e.prompt, tool_use_id: e.tool_use_id });
    } catch (err) {
      await ledgerErro($, 'agent.spawn', ids, err);
      return next(e);
    }
    if (r.off) {
      await gravarLedger($, r.cfg, linhaDeLedger(r.linha));
      return next(e);
    }
    let chamada = e;
    let aplicado = null;
    try {
      if (modeloAplicavel(r)) {
        const envModelo = await $.env.get('CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL');
        const atual = e.model ?? envModelo ?? e.parentModel;
        const rAtual = rankModelo(atual);
        // so SOBE: baseline desconhecido (fable, id fora da familia) nunca e tocado
        if (rAtual >= 0 && rankModelo(r.d.model) > rAtual) {
          chamada = { ...e, model: r.d.model };
          aplicado = { model: r.d.model, effort: null };
        }
      }
      await gravarLedger($, r.cfg, linhaDeLedger(linhaDaDecisao(r, aplicado, {})));
    } catch (err) {
      await ledgerErro($, 'agent.spawn', ids, err);
      chamada = e;
    }
    return next(chamada);
  });

  on('session.measure', async ($, e, next) => {
    try {
      const agora = await $.clock.now();
      const p = calcularRitmo(e.rateLimits, agora);
      ritmo = p === null ? null : { p, ts: agora };
    } catch {
      ritmo = null;
    }
    return next(e);
  });
}
