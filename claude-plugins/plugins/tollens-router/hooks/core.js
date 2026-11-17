// Funcoes puras do mod tollens-router (R2). Sem `$`, sem I/O, sem relogio: o analisador estatico do
// Claude Code so aceita `$` em register.js. Protocolo: claude-plugins/plugins/tollens-router/CONTRATO.md.

export const MAX_HISTORY = 1000;
export const MAX_CHAVE_HEX = 64;
export const ALIASES = ['haiku', 'sonnet', 'opus'];
const TIERS = ['T0', 'T1', 'T2', 'T3', 'T4'];
const SEMANA_MS = 7 * 86400000;

const plain = (o) => o !== null && typeof o === 'object' && !Array.isArray(o);
const tierIdx = (t) => TIERS.indexOf(t);

// (a) sha256 hex dos primeiros 200 caracteres do texto normalizado de `subagentType\ndescricao`.
export async function derivarChave(subagentType, descricao) {
  const st = typeof subagentType === 'string' ? subagentType : '';
  const ds = typeof descricao === 'string' ? descricao : '';
  if (st === '' && ds === '') return undefined;
  const base = `${st}\n${ds}`.normalize('NFKC').toLowerCase().replace(/\s+/g, ' ').trim().slice(0, 200);
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(base));
  return [...new Uint8Array(buf)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

// Estado persistido por fluxo (sessao). Sempre dado puro.
export function estadoVazio() {
  return { falhasPorChave: {}, subidasConcedidas: [], ordem: [], autorTierPorChave: {}, chavesCriticas: [] };
}

export function normalizarEstado(raw) {
  const e = estadoVazio();
  if (!plain(raw)) return e;
  if (plain(raw.falhasPorChave)) {
    for (const [k, v] of Object.entries(raw.falhasPorChave)) if (Number.isInteger(v) && v >= 1) e.falhasPorChave[k] = v;
  }
  if (plain(raw.autorTierPorChave)) {
    for (const [k, v] of Object.entries(raw.autorTierPorChave)) if (tierIdx(v) >= 0) e.autorTierPorChave[k] = v;
  }
  for (const campo of ['subidasConcedidas', 'ordem', 'chavesCriticas']) {
    if (Array.isArray(raw[campo])) {
      const vistos = new Set();
      for (const k of raw[campo]) if (typeof k === 'string' && k.length >= 1 && k.length <= 256 && !vistos.has(k)) { vistos.add(k); e[campo].push(k); }
    }
  }
  return e;
}

// (c) aparar TODAS as estruturas a no maximo MAX_HISTORY entradas, preservando a chave atual e as
// chaves de subidasConcedidas. Devolve { history, aparado } (aparado: algo foi cortado).
export function aparar(estado, chave, max = MAX_HISTORY) {
  let aparado = false;
  const h = estadoVazio();

  const lista = (src, obrigatorias) => {
    const fixas = [...new Set(obrigatorias.filter((k) => src.includes(k)))].slice(0, max);
    const fx = new Set(fixas);
    const resto = src.filter((k) => !fx.has(k));
    // preserva a ordem original; quando falta lugar, descarta as MAIS ANTIGAS do que nao e obrigatorio
    const cabem = Math.max(0, max - fixas.length);
    if (resto.length > cabem) aparado = true;
    const mantidas = new Set([...fx, ...resto.slice(resto.length - cabem)]);
    return src.filter((k) => mantidas.has(k));
  };
  h.subidasConcedidas = lista(estado.subidasConcedidas, chave === undefined ? [] : [chave]);
  h.ordem = lista(estado.ordem, chave === undefined ? [] : [chave]);
  h.chavesCriticas = lista(estado.chavesCriticas, chave === undefined ? [] : [chave]);

  const mapa = (src, ordenaPorValor) => {
    const chaves = Object.keys(src);
    if (chaves.length <= max) return { ...src };
    aparado = true;
    const atual = chave !== undefined && Object.hasOwn(src, chave) ? [chave] : [];
    const demais = chaves.filter((k) => k !== chave);
    if (ordenaPorValor) demais.sort((a, b) => src[b] - src[a]);
    else demais.reverse(); // mais recentes primeiro (ordem de insercao)
    const saida = {};
    for (const k of [...atual, ...demais].slice(0, max)) saida[k] = src[k];
    return saida;
  };
  h.falhasPorChave = mapa(estado.falhasPorChave, true);
  h.autorTierPorChave = mapa(estado.autorTierPorChave, false);
  return { history: h, aparado };
}

export function autorTierMax(estado) {
  let m = -1;
  for (const t of Object.values(estado.autorTierPorChave)) if (tierIdx(t) > m) m = tierIdx(t);
  return m >= 0 ? TIERS[m] : undefined;
}

// (f) p = percentual semanal usado menos fracao decorrida da semana, ambos em [0,1].
export function calcularRitmo(rateLimits, agoraMs) {
  if (!Array.isArray(rateLimits)) return null;
  const w = rateLimits.find((r) => plain(r) && r.kind === 'seven_day');
  if (!w || typeof w.percentUsed !== 'number' || !Number.isFinite(w.percentUsed)) return null;
  if (typeof w.resetsAt !== 'string') return null;
  const reset = Date.parse(w.resetsAt);
  if (!Number.isFinite(reset) || !Number.isFinite(agoraMs) || reset <= agoraMs) return null;
  const decorrida = Math.min(1, Math.max(0, 1 - (reset - agoraMs) / SEMANA_MS));
  const usado = Math.min(1, Math.max(0, w.percentUsed / 100));
  return usado - decorrida;
}

export function estadoDoRitmo(p, policy) {
  if (typeof p !== 'number' || !Number.isFinite(p) || !plain(policy) || !plain(policy.pace)) return 'dentro';
  const { abaixo_de: a, acima_de: b } = policy.pace;
  if (typeof a === 'number' && p < a) return 'abaixo';
  if (typeof b === 'number' && p > b) return 'acima';
  return 'dentro';
}

// Sinais de falha pelo RESULTADO do Agent. Heuristica; devolve so um codigo, nunca texto.
const SINAIS = [
  [/n[aã]o verificado/i, 'nao_verificado'],
  [/\brefutado\b/i, 'refutado'],
  [/\bfalhou\b/i, 'falhou'],
  [/contrato reprovado/i, 'contrato_reprovado'],
];
export function sinalDeFalha(res) {
  if (!plain(res)) return null;
  const r = plain(res.result) ? res.result : {};
  const stop = r.stop_reason ?? r.stopReason ?? res.stop_reason ?? res.stopReason;
  if (stop === 'max_tokens' || stop === 'refusal') return `stop_${stop}`;
  const texto = typeof res.text === 'string' ? res.text : typeof res.result === 'string' ? res.result : '';
  for (const [re, cod] of SINAIS) if (re.test(texto.slice(0, 200000))) return cod;
  return null;
}

export const NOTA_FALHA = 'router: sinal de falha; a proxima tentativa desta tarefa sobe um nivel';

// Familia do modelo: haiku < sonnet < opus; -1 desconhecida (nunca e alterada).
export function rankModelo(m) {
  if (typeof m !== 'string') return -1;
  const t = m.toLowerCase().match(/haiku|sonnet|opus|fable/);
  if (!t || t[0] === 'fable') return -1;
  return ALIASES.indexOf(t[0]);
}

// ---------------------------------------------------------------- ledger (decisao, nunca conteudo)

const SEGURO_RE = /^[A-Za-z0-9._:-]{1,80}$/;
const seguro = (s, padrao = null) => (typeof s === 'string' && SEGURO_RE.test(s) ? s : padrao);
const ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/;

// Ultimo segmento do namespace `plugin:nome`, restrito ao charset seguro (texto livre vira null).
export function papelSeguro(subagentType) {
  if (typeof subagentType !== 'string') return null;
  const seg = subagentType.split(':').pop();
  return seguro(seg);
}

export function linhaDeLedger(c) {
  const f = plain(c.ficha) ? c.ficha : null;
  const ficha = f ? {
    c: ['1', '2', '3', '4', '5'].includes(String(f.c)) ? Number(f.c) : null,
    r: ['trivial', 'normal', 'medio', 'alto'].includes(f.r) ? f.r : null,
    v: ['sim', 'parcial', 'nao'].includes(f.v) ? f.v : null,
  } : null;
  const alias = (m) => (ALIASES.includes(m) ? m : null);
  const efforts = ['low', 'medium', 'high', 'xhigh', 'max'];
  const num = (n) => (typeof n === 'number' && Number.isFinite(n) ? Math.round(n * 1000) / 1000 : null);
  const obj = {
    ts: typeof c.ts === 'string' && ISO_RE.test(c.ts) ? c.ts : null,
    evento: ['tool.call', 'agent.spawn', 'resultado'].includes(c.evento) ? c.evento : null,
    session_id: seguro(c.session_id),
    tool_use_id: seguro(c.tool_use_id),
    agent_type: papelSeguro(c.agent_type),
    role: papelSeguro(c.role),
    chave: typeof c.chave === 'string' && /^[0-9a-f]{64}$/.test(c.chave) ? c.chave.slice(0, 16) : null,
    ficha,
    floor: TIERS.includes(c.floor) ? c.floor : null,
    tier_base: TIERS.includes(c.tier_base) ? c.tier_base : null,
    tier: TIERS.includes(c.tier) ? c.tier : null,
    pedido: { model: alias(c.pedido && c.pedido.model), effort: efforts.includes(c.pedido && c.pedido.effort) ? c.pedido.effort : null },
    aplicado: { model: alias(c.aplicado && c.aplicado.model), effort: efforts.includes(c.aplicado && c.aplicado.effort) ? c.aplicado.effort : null },
    mode: ['off', 'shadow', 'enforce'].includes(c.mode) ? c.mode : null,
    modo_efetivo: ['off', 'shadow', 'enforce'].includes(c.modo_efetivo) ? c.modo_efetivo : null,
    pace: c.pace && ['abaixo', 'dentro', 'acima'].includes(c.pace.estado) ? { estado: c.pace.estado, p: num(c.pace.p) } : null,
    capped: c.capped === true,
    subida_concedida: c.subida_concedida === true,
    reasons: Array.isArray(c.reasons) ? c.reasons.map((r) => seguro(r)).filter((r) => r !== null).slice(0, 40) : [],
    sinal: seguro(c.sinal),
    erro: seguro(c.erro),
  };
  // U+2028 e U+2029 saem escapados: o arquivo e uma linha por registro.
  return JSON.stringify(obj).split('\u2028').join('\\u2028').split('\u2029').join('\\u2029');
}

export function nomeDoErro(err) {
  const n = err && typeof err === 'object' && typeof err.name === 'string' ? err.name : 'Erro';
  return seguro(`excecao:${n}`.slice(0, 80), 'excecao');
}
