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
// Leitura descartada (null): sem janela seven_day, percentUsed fora de [0,100] ou nao finito, resetsAt
// ausente, ilegivel, no passado ou alem de 7 dias.
export function calcularRitmo(rateLimits, agoraMs) {
  if (!Array.isArray(rateLimits)) return null;
  const w = rateLimits.find((r) => plain(r) && r.kind === 'seven_day');
  if (!w || typeof w.percentUsed !== 'number' || !Number.isFinite(w.percentUsed) || w.percentUsed < 0 || w.percentUsed > 100) return null;
  if (typeof w.resetsAt !== 'string') return null;
  const reset = Date.parse(w.resetsAt);
  if (!Number.isFinite(reset) || !Number.isFinite(agoraMs) || reset <= agoraMs || reset - agoraMs > SEMANA_MS) return null;
  const decorrida = 1 - (reset - agoraMs) / SEMANA_MS;
  return w.percentUsed / 100 - decorrida;
}

export const RITMO_VALIDADE_MS = 30 * 60000;
// Leitura vigente: medida ha no maximo 30 min (e nao no futuro); senao `dentro`.
export function ritmoVigente(ritmo, agoraMs) {
  if (!plain(ritmo) || typeof ritmo.p !== 'number' || typeof ritmo.ts !== 'number') return null;
  const idade = agoraMs - ritmo.ts;
  return idade >= 0 && idade <= RITMO_VALIDADE_MS ? ritmo.p : null;
}

export function estadoDoRitmo(p, policy) {
  if (typeof p !== 'number' || !Number.isFinite(p) || !plain(policy) || !plain(policy.pace)) return 'dentro';
  const { abaixo_de: a, acima_de: b } = policy.pace;
  if (typeof a === 'number' && p < a) return 'abaixo';
  if (typeof b === 'number' && p > b) return 'acima';
  return 'dentro';
}

// Sinais de falha pelo RESULTADO do Agent, so de formato documentado: `isError` do resultado, `status`
// do registro do Agent (`completed` e `async_launched` sao normais) e linha ESTRUTURADA no inicio de
// linha. Texto solto no meio de uma frase nao conta. Devolve so um codigo, nunca texto.
const LINHA_ESTRUTURADA = /^(Estado|Veredito|Resultado):[ \t]*(NAO VERIFICADO|N\u00c3O VERIFICADO|REFUTADO|REPROVADO)/im;
export function sinalDeFalha(res) {
  if (!plain(res)) return null;
  if (res.isError === true) return 'erro_ferramenta';
  const st = plain(res.result) ? res.result.status : undefined;
  if (typeof st === 'string' && st !== 'completed' && st !== 'async_launched') return 'status_nao_concluido';
  const texto = typeof res.text === 'string' ? res.text.slice(0, 200000) : '';
  return LINHA_ESTRUTURADA.test(texto) ? 'linha_estruturada' : null;
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
// Id de modelo como o Claude Code o escreve (`claude-sonnet-5-5[1m]`); texto livre vira null.
const MODELO_RE = /^[A-Za-z0-9._:\/@\[\]-]{1,80}$/;
const modeloSeguro = (s) => (typeof s === 'string' && MODELO_RE.test(s) ? s : null);
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
    evento: ['tool.call', 'agent.spawn', 'resultado', 'efetivo'].includes(c.evento) ? c.evento : null,
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
    efetivo: modeloSeguro(c.efetivo),
    usados: Array.isArray(c.usados) ? c.usados.map(modeloSeguro).filter((m) => m !== null).slice(0, 4) : [],
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

// Campos que uma linha do ledger pode ter. Um arquivo so e tratado como do ledger se a primeira linha for
// um objeto JSON com `evento` e so estes campos: o mod nunca anexa a (nem rotaciona sobre) arquivo alheio.
export const CAMPOS_LEDGER = ['ts', 'evento', 'session_id', 'tool_use_id', 'agent_type', 'role', 'chave', 'ficha', 'floor', 'tier_base',
  'tier', 'pedido', 'aplicado', 'mode', 'modo_efetivo', 'pace', 'capped', 'subida_concedida', 'reasons', 'efetivo', 'usados', 'sinal', 'erro'];
export function ehDoLedger(texto) {
  if (typeof texto !== 'string') return false;
  if (texto === '') return true;
  const linha = texto.slice(0, texto.indexOf('\n') === -1 ? texto.length : texto.indexOf('\n'));
  let o;
  try {
    o = JSON.parse(linha);
  } catch {
    return false;
  }
  return plain(o) && Object.hasOwn(o, 'evento') && Object.keys(o).every((k) => CAMPOS_LEDGER.includes(k));
}

export async function hex16(texto) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(String(texto)));
  return [...new Uint8Array(buf)].slice(0, 8).map((b) => b.toString(16).padStart(2, '0')).join('');
}

// ---------------------------------------------------------------- managed (somente leitura)

const tokens = (s) => (typeof s === 'string' ? s.toLowerCase().split(/[^a-z]+/) : []);
// `managed`: { available: string[]|null, denied: string[]|null } ou null (ilegivel: sem restricao conhecida).
export function modeloPermitido(alias, managed) {
  if (!plain(managed)) return true;
  const casa = (lista) => Array.isArray(lista) && lista.some((x) => tokens(x).includes(alias));
  if (casa(managed.denied)) return false;
  if (Array.isArray(managed.available) && managed.available.length > 0 && !casa(managed.available)) return false;
  return true;
}

export function lerManaged(texto) {
  try {
    const o = JSON.parse(texto);
    if (!plain(o)) return null;
    const lista = (v) => (Array.isArray(v) ? v.filter((x) => typeof x === 'string') : null);
    return { available: lista(o.availableModels), denied: lista(o.deniedModels) };
  } catch {
    return null;
  }
}

// Modelo a aplicar quando o desejado (decisao do motor) e negado pelo managed: o maior nivel EMITIVEL abaixo
// do decidido cujo modelo e permitido e que nao fica abaixo do pedido original do orquestrador. Sem
// candidato: null (a chamada fica como o orquestrador a fez).
export function melhorPermitido(policy, tierDecidido, original, managed) {
  const piso = Math.max(0, rankModelo(original));
  for (let t = TIERS.indexOf(tierDecidido) - 1; t >= 0; t--) {
    const c = plain(policy) && plain(policy.tiers) ? policy.tiers[TIERS[t]] : undefined;
    if (!plain(c) || c.emitivel === false || !ALIASES.includes(c.model)) continue;
    if (modeloPermitido(c.model, managed) && ALIASES.indexOf(c.model) >= piso) return { model: c.model, effort: c.effort, tier: TIERS[t] };
  }
  return null;
}

// ---------------------------------------------------------------- indice de sessoes no store

export const MAX_SESSOES = 50;
export const IDADE_MAX_MS = 14 * 86400000;
// Insere/atualiza a sessao e devolve { indice, remover }: sessoes com 14 dias ou mais e as mais antigas alem de 50.
export function podarSessoes(indice, sid, agoraMs) {
  const base = Array.isArray(indice) ? indice.filter((x) => Array.isArray(x) && typeof x[0] === 'string' && typeof x[1] === 'number' && x[0] !== sid) : [];
  base.sort((a, b) => a[1] - b[1]);
  base.push([sid, agoraMs]);
  const remover = [];
  const manter = [];
  for (const x of base) (x[0] !== sid && agoraMs - x[1] >= IDADE_MAX_MS ? remover : manter).push(x);
  while (manter.length > MAX_SESSOES) remover.push(manter.shift());
  return { indice: manter, remover: remover.map((x) => x[0]) };
}
