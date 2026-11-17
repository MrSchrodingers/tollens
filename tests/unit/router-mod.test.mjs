// Suite do MOD tollens-router (R2): hooks/register.js ligado a um `$` simulado, sem sessao real.
// `claude plugin test` NAO roda onde allowManagedHooksOnly esta ativo (os modulos de hooks ficam
// desligados); este harness carrega register.js com um `on` e um `$` de memoria. Nao prova o carregamento
// real pelo Claude Code: isso e NAO VERIFICADO aqui.
// Invariantes protegidos (nomes do prompt de delegacao):
//   I1  shadow e off nao alteram a chamada (comparacao profunda entrada x saida)
//   I2  enforce nunca escolhe modelo fora da allowlist nem fable
//   I3  excecao interna nao altera a chamada e deixa erro sem conteudo
//   I4  o ledger nunca contem prompt, descricao nem resultado (canario)
//   I5  persistencia antes de aplicar, em qualquer modo, e subida pegajosa entre chamadas
//   I6  a sentinela de root vence qualquer modo
//   I7  @@ROTA so e removida em enforce e so a primeira linha
//   I8  agent.spawn de workflow sobrepoe a variavel haiku so em enforce e so para cima
//   I9  history aparado antes de decide (1000+ chaves nao degrada, chave atual preservada)
//   I10 o ritmo so desce onde a ficha permite (v sim, acima do piso)
//   L1  sinal de falha registra por chave, nao re-executa e so avisa em enforce
//   L2  ledger: chamadas paralelas nao perdem linha; rotacao em 3 geracoes
// Os `aprovacao_medida` das politicas sao FIXTURES SINTETICAS; nao sao medicao.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { register } from '../../claude-plugins/plugins/tollens-router/hooks/register.js';
import { aparar, derivarChave, estadoVazio } from '../../claude-plugins/plugins/tollens-router/hooks/core.js';
import { validatePolicy } from '../../claude-plugins/plugins/tollens-router/engine.mjs';

const DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../claude-plugins/plugins/tollens-router');
const SHIPPED = JSON.parse(readFileSync(path.join(DIR, 'router-policy.json'), 'utf8'));
const NOW = Date.parse('2026-11-16T00:00:00Z');
const DIA = 86400000;
const TIERS = ['T0', 'T1', 'T2', 'T3', 'T4'];
const POL = '/root-fake/router-policy.json';
const LED = '/home-fake/.claude/logs/router-ledger.jsonl';
const SENT_PADRAO = '/etc/claude-code/router-off';
const clone = (o) => JSON.parse(JSON.stringify(o));
const ROTA = (c, r, v, t = 'tarefa-x') => `@@ROTA ${JSON.stringify({ c, r, v, t })}`;

function deepFreeze(o) {
  if (o && typeof o === 'object' && !Object.isFrozen(o)) {
    Object.freeze(o);
    for (const k of Object.keys(o)) deepFreeze(o[k]);
  }
  return o;
}

function politica(modo, mutate) {
  const p = clone(SHIPPED);
  p.mode = modo;
  p.valid_until = '2027-06-30T00:00:00Z';
  for (const t of TIERS) {
    p.quality.por_nivel[t] = { aprovacao_medida: 0.95, n: 10, fonte: 'fixture sintetica de teste' };
    delete p.tiers[t].emitivel;
  }
  if (mutate) mutate(p);
  assert.equal(validatePolicy(p, { now: NOW }).ok, true, 'fixture de politica invalida');
  return p;
}

// Mundo simulado: arquivos, store, relogio, env e o registro de eventos (ordem das chamadas).
function mundo({ pol, sentinela = false, env = {}, agora = NOW, falha = {} } = {}) {
  const arq = new Map();
  const st = new Map();
  const eventos = [];
  if (pol !== undefined) arq.set(POL, typeof pol === 'string' ? pol : JSON.stringify(pol));
  if (sentinela === true) arq.set(SENT_PADRAO, '');
  else if (typeof sentinela === 'string') arq.set(sentinela, '');
  const ambiente = { TOLLENS_ROUTER_POLICY: POL, TOLLENS_ROUTER_LEDGER: LED, HOME: '/home-fake', ...env };
  const quebra = (nome) => { if (falha[nome]) throw new Error(`CANARIO-ERRO-${nome}`); };
  const $ = {
    clock: { now: async () => { quebra('clock'); return typeof falha.agora === 'number' || falha.agora === 'x' ? falha.agora : agora; } },
    env: { get: async (n) => ambiente[n] },
    fs: {
      read: async (p) => { await new Promise((r) => setImmediate(r)); if (!arq.has(p)) throw new Error('ENOENT'); return arq.get(p); },
      write: async (p, t) => { await new Promise((r) => setImmediate(r)); eventos.push(`fs.write:${p === LED ? 'ledger' : p}`); arq.set(p, t); },
      exists: async (p) => { quebra('exists'); return arq.has(p); },
    },
    session: { id: async () => 'sess-1' },
    store: {
      get: async (k) => { quebra('store'); return st.has(k) ? clone(st.get(k)) : undefined; },
      set: async (k, v) => { eventos.push('store.set'); st.set(k, clone(v)); },
    },
  };
  const hooks = [];
  register((ev, a, b) => { hooks.push({ ev, m: typeof a === 'function' ? null : a, fn: typeof a === 'function' ? a : b }); return { catch() {} }; });
  return { $, arq, st, eventos, hooks, ledger: () => (arq.get(LED) || '').split('\n').filter(Boolean).map((l) => JSON.parse(l)) };
}

async function agent(w, e, resultado = { result: {}, text: 'concluido' }) {
  const h = w.hooks.find((x) => x.ev === 'tool.call' && x.m.tool.includes(e.tool));
  let recebido;
  let chamadasNext = 0;
  const next = async (x) => { w.eventos.push('next'); chamadasNext++; recebido = x; return clone(resultado); };
  const saida = await h.fn(w.$, deepFreeze(clone(e)), next);
  return { saida, recebido, chamadasNext };
}

async function spawn(w, e) {
  const h = w.hooks.find((x) => x.ev === 'agent.spawn');
  let recebido;
  const next = async (x) => { w.eventos.push('next'); recebido = x; return { model: x.model ?? 'inherit' }; };
  await h.fn(w.$, deepFreeze(clone(e)), next);
  return recebido;
}

async function medir(w, rateLimits) {
  const h = w.hooks.find((x) => x.ev === 'session.measure');
  await h.fn(w.$, deepFreeze({ context: {}, rateLimits, changed: ['rateLimits'] }), async (x) => ({ changed: x.changed }));
}

let seq = 0;
const chamada = (over = {}) => ({
  tool: 'Agent', tool_use_id: `toolu_${++seq}`, subagent_type: 'general-purpose', description: 'refatorar modulo x',
  prompt: `${ROTA(3, 'medio', 'nao')}\nfaca isto no repositorio`, ...over,
});

// ------------------------------------------------------------------ I1

test('I1 shadow, off, politica vencida/ausente/ilegivel/sem medicao: a chamada chega ao next intacta', async () => {
  const casos = [
    ['shadow', politica('shadow')],
    ['off', politica('off')],
    ['enforce vencida', politica('enforce', (p) => { p.valid_until = '2026-11-01T00:00:00Z'; })],
    ['enforce sem medicao (politica entregue)', (() => { const p = clone(SHIPPED); p.mode = 'enforce'; return p; })()],
    ['ausente', undefined],
    ['ilegivel', '{nao e json'],
    ['invalida', { schema_version: 1 }],
  ];
  for (const [nome, pol] of casos) {
    const w = mundo({ pol });
    const e = chamada({ model: 'haiku', effort: 'low' });
    const { recebido, saida } = await agent(w, e);
    assert.deepEqual(recebido, e, `${nome}: chamada alterada`);
    assert.deepEqual(saida, { result: {}, text: 'concluido' }, `${nome}: resultado alterado`);
  }
});

// ------------------------------------------------------------------ I2

test('I2 enforce: model e effort vem da allowlist da politica, nunca fable, mesmo com model hostil na chamada', async () => {
  const pol = politica('enforce', (p) => { p.model_allowlist = ['sonnet', 'opus']; p.tiers.T0 = { model: 'sonnet', effort: 'low' }; p.tiers.T1 = { model: 'sonnet', effort: 'medium' }; });
  const entradas = [
    ['general-purpose', ROTA(1, 'trivial', 'sim'), 'fable'],
    ['general-purpose', ROTA(5, 'alto', 'nao'), 'fable'],
    ['revisor-codigo', ROTA(2, 'normal', 'sim'), 'claude-fable-5'],
    ['plugin:refutador', 'sem ficha, tocar em deploy e senha', 'FABLE'],
    ['general-purpose', '@@ROTA {"c":9,"r":"x","v":"y","t":"fable"}', 'fable'],
  ];
  for (const [tipo, linha, modelo] of entradas) {
    const w = mundo({ pol });
    const { recebido } = await agent(w, chamada({ subagent_type: tipo, prompt: `${linha}\ncorpo`, model: modelo }));
    assert.ok(pol.model_allowlist.includes(recebido.model), `modelo fora da allowlist: ${recebido.model}`);
    assert.ok(!/fable/i.test(recebido.model));
    assert.ok(['low', 'medium', 'high'].includes(recebido.effort));
    assert.ok(recebido.model !== 'haiku');
  }
});

// ------------------------------------------------------------------ I3

test('I3 excecao interna: chamada intacta e linha de erro sem conteudo', async () => {
  for (const falha of [{ store: true }, { exists: true }, { clock: true }, { agora: 'x' }]) {
    const w = mundo({ pol: politica('enforce'), falha });
    const e = chamada({ prompt: `${ROTA(2, 'normal', 'sim')}\nCANARIO-PROMPT-I3` });
    const { recebido } = await agent(w, e);
    assert.deepEqual(recebido, e, `${JSON.stringify(falha)}: chamada alterada`);
    const bruto = w.arq.get(LED) || '';
    assert.ok(!bruto.includes('CANARIO'), 'mensagem da excecao ou prompt vazou para o ledger');
    const linhas = w.ledger();
    assert.equal(linhas.length, 1);
    assert.match(linhas[0].erro, /^excecao/);
  }
});

// ------------------------------------------------------------------ I4

test('I4 ledger sem prompt, descricao, resultado, ficha.t nem tipo livre (canario), em shadow e enforce', async () => {
  const campos = ['ts', 'evento', 'session_id', 'tool_use_id', 'agent_type', 'role', 'chave', 'ficha', 'floor', 'tier_base', 'tier',
    'pedido', 'aplicado', 'mode', 'modo_efetivo', 'pace', 'capped', 'subida_concedida', 'reasons', 'sinal', 'erro'];
  for (const modo of ['shadow', 'enforce']) {
    const w = mundo({ pol: politica(modo) });
    const e = chamada({
      subagent_type: 'CANARIO-TIPO livre', description: 'CANARIO-DESC-7731',
      prompt: `${ROTA(3, 'medio', 'nao', 'CANARIO-T')}\nCANARIO-PROMPT-7731 deploy do /etc/senha`,
    });
    await agent(w, e, { result: {}, text: 'CANARIO-RES-7731 NAO VERIFICADO' });
    const bruto = w.arq.get(LED);
    assert.ok(bruto && !bruto.includes('CANARIO'), `canario no ledger (${modo})`);
    for (const l of w.ledger()) for (const k of Object.keys(l)) assert.ok(campos.includes(k), `campo fora da lista: ${k}`);
    for (const [k, v] of w.st) assert.ok(!JSON.stringify(v).includes('CANARIO'), `canario no store ${k}`);
  }
});

// ------------------------------------------------------------------ I5

test('I5 persistencia antes de aplicar (shadow e enforce) e subida pegajosa entre chamadas', async () => {
  for (const modo of ['shadow', 'enforce']) {
    const base = chamada({ subagent_type: 'general-purpose', description: 'tarefa pegajosa', prompt: `${ROTA(2, 'normal', 'sim')}\nfaca` });
    const chave = await derivarChave(base.subagent_type, base.description);
    const limpo = mundo({ pol: politica(modo) });
    await agent(limpo, base);
    const tierLimpo = limpo.ledger()[0].tier;

    const w = mundo({ pol: politica(modo) });
    w.st.set('router.estado.sess-1', { ...estadoVazio(), falhasPorChave: { [chave]: 1 }, ordem: [chave] });
    await agent(w, base);
    const l1 = w.ledger()[0];
    assert.equal(l1.subida_concedida, true);
    assert.ok(TIERS.indexOf(l1.tier) > TIERS.indexOf(tierLimpo), 'sem subida por repeticao');
    assert.ok(w.eventos.indexOf('store.set') !== -1 && w.eventos.indexOf('store.set') < w.eventos.indexOf('next'), 'persistiu depois de aplicar');
    assert.ok(w.st.get('router.estado.sess-1').subidasConcedidas.includes(chave));

    // a falha some do historico (outro fluxo de leitura); a concessao persistida continua valendo
    const salvo = clone(w.st.get('router.estado.sess-1'));
    salvo.falhasPorChave = {};
    salvo.ordem = [];
    w.st.set('router.estado.sess-1', salvo);
    await agent(w, { ...base, tool_use_id: 'toolu_p2' });
    const l2 = w.ledger()[1];
    assert.ok(TIERS.indexOf(l2.tier) >= TIERS.indexOf(l1.tier), 'a subida recuou');
  }
});

// ------------------------------------------------------------------ I6

test('I6 sentinela de root vence enforce: chamada intacta, nada persistido; vale tambem a sentinela da variavel', async () => {
  for (const sentinela of [true, '/outro/router-off']) {
    const w = mundo({ pol: politica('enforce'), sentinela, env: typeof sentinela === 'string' ? { TOLLENS_ROUTER_SENTINEL: sentinela } : {} });
    const e = chamada({ subagent_type: 'revisor-codigo', model: 'haiku' });
    const { recebido } = await agent(w, e);
    assert.deepEqual(recebido, e);
    assert.ok(!w.eventos.includes('store.set'));
    assert.deepEqual(w.ledger()[0].reasons, ['sentinela_off']);
    assert.equal(w.ledger()[0].mode, 'off');
  }
  // a variavel de teste nao desarma a sentinela padrao
  const w = mundo({ pol: politica('enforce'), sentinela: true, env: { TOLLENS_ROUTER_SENTINEL: '/nao/existe' } });
  const e = chamada({});
  assert.deepEqual((await agent(w, e)).recebido, e);
});

// ------------------------------------------------------------------ I7

test('I7 @@ROTA: removida so em enforce e so a primeira linha; no meio do prompt nada muda', async () => {
  const corpo = `intro\n${ROTA(1, 'trivial', 'sim', 'meio')}\nfim`;
  const primeira = `${ROTA(4, 'alto', 'nao')}\n${ROTA(1, 'trivial', 'sim', 'segunda')}\nresto`;
  for (const modo of ['shadow', 'enforce']) {
    const w = mundo({ pol: politica(modo) });
    const a = await agent(w, chamada({ prompt: primeira }));
    if (modo === 'shadow') assert.equal(a.recebido.prompt, primeira);
    else assert.equal(a.recebido.prompt, `${ROTA(1, 'trivial', 'sim', 'segunda')}\nresto`);
    const b = await agent(w, chamada({ prompt: corpo }));
    assert.equal(b.recebido.prompt, corpo);
  }
});

// ------------------------------------------------------------------ I8

test('I8 agent.spawn de workflow: sobrepoe a variavel haiku so em enforce, so para cima; ignora resume, fork e subagente comum', async () => {
  const wf = { tool_use_id: 'toolu_wf', prompt: 'p', description: 'revisar', subagentType: 'revisor-codigo', provider: {}, parentModel: 'claude-opus-4', background: true, fork: false, workflow: { runId: 'wf_1', agentIndex: 1 } };
  const env = { CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL: 'haiku' };
  const enf = mundo({ pol: politica('enforce'), env });
  assert.equal((await spawn(enf, wf)).model, 'opus');
  assert.equal(enf.ledger()[0].aplicado.model, 'opus');
  const sh = mundo({ pol: politica('shadow'), env });
  assert.deepEqual(await spawn(sh, wf), wf);
  // nao desce: o roteador pede sonnet, o script ja pede opus
  const alto = mundo({ pol: politica('enforce'), env });
  const trivial = { ...wf, subagentType: 'general-purpose', description: 'listar', prompt: ROTA(1, 'trivial', 'sim'), model: 'opus' };
  assert.deepEqual(await spawn(alto, trivial), trivial);
  // baseline desconhecido (fable) nunca e tocado
  const fb = { ...wf, model: 'fable' };
  assert.deepEqual(await spawn(mundo({ pol: politica('enforce'), env }), fb), fb);
  const { workflow: _omitido, ...comum } = wf;
  for (const e of [{ ...wf, resume: { agentId: 'a1' } }, { ...wf, fork: true }, comum]) {
    const w = mundo({ pol: politica('enforce'), env });
    assert.deepEqual(await spawn(w, e), e);
    assert.deepEqual(w.eventos.filter((x) => x === 'store.set'), []);
  }
});

test('I8b teammate ja decidido no tool.call nao e decidido de novo; sem tool.call anterior decide so o modelo', async () => {
  const w = mundo({ pol: politica('enforce') });
  const ag = chamada({ subagent_type: 'revisor-codigo', tool_use_id: 'toolu_tm', name: 'rev' });
  await agent(w, ag);
  const tm = { tool_use_id: 'toolu_tm', prompt: 'p', description: ag.description, subagentType: 'revisor-codigo', provider: {}, parentModel: 'sonnet', background: true, fork: false, isTeammate: true };
  assert.deepEqual(await spawn(w, tm), tm);
  const w2 = mundo({ pol: politica('enforce') });
  assert.equal((await spawn(w2, { ...tm, tool_use_id: 'toolu_tm2' })).model, 'opus');
});

// ------------------------------------------------------------------ I9

test('I9 history aparado: 1000+ chaves nao degradam e a chave atual e as concedidas sobrevivem', async () => {
  const base = chamada({ description: 'tarefa com historico enorme', prompt: `${ROTA(2, 'normal', 'sim')}\nfaca` });
  const chave = await derivarChave(base.subagent_type, base.description);
  const falhas = {};
  const autor = {};
  const ordem = [chave];
  for (let i = 0; i < 1500; i++) { falhas[`k${i}`] = 1; autor[`k${i}`] = 'T2'; if (i < 1199) ordem.push(`k${i}`); }
  falhas[chave] = 1;
  const estado = { falhasPorChave: falhas, autorTierPorChave: autor, ordem, subidasConcedidas: ['k7'], chavesCriticas: [] };
  const w = mundo({ pol: politica('shadow') });
  w.st.set('router.estado.sess-1', estado);
  const t0 = Date.now();
  await agent(w, base);
  assert.ok(Date.now() - t0 < 2000, 'decisao lenta com historico grande');
  const l = w.ledger()[0];
  assert.ok(!l.reasons.includes('history_truncado') && !l.reasons.includes('history_truncado_lista'));
  assert.ok(l.reasons.includes('history_aparado') && l.reasons.includes('repeticao'), JSON.stringify(l.reasons));
  const salvo = w.st.get('router.estado.sess-1');
  for (const campo of ['falhasPorChave', 'autorTierPorChave']) assert.ok(Object.keys(salvo[campo]).length <= 1000);
  assert.ok(salvo.ordem.length <= 1000);
  assert.ok(Object.hasOwn(salvo.falhasPorChave, chave));
  const { history } = aparar({ ...estadoVazio(), falhasPorChave: falhas, subidasConcedidas: ['k7', chave] }, chave);
  assert.ok(history.subidasConcedidas.includes('k7') && history.subidasConcedidas.includes(chave));
  assert.ok(Object.hasOwn(history.falhasPorChave, chave));
});

// ------------------------------------------------------------------ I10

test('I10 ritmo: acima so desce com v=sim e nunca abaixo do piso; abaixo so sobe com v=nao', async () => {
  const semana = (usado) => [{ kind: 'seven_day', percentUsed: usado, resetsAt: new Date(NOW + 0.7 * 7 * DIA).toISOString() }];
  const tierDe = async (w, tipo, v, c = 5, r = 'alto') => {
    await agent(w, chamada({ subagent_type: tipo, prompt: `${ROTA(c, r, v)}\ncorpo neutro` }));
    const ls = w.ledger();
    return ls[ls.length - 1];
  };
  const w = mundo({ pol: politica('shadow') });
  await medir(w, semana(10)); // base: p = 0.1 - 0.3 = -0.2 (abaixo)
  const abaixoNao = await tierDe(w, 'general-purpose', 'nao', 3, 'medio');
  const abaixoSim = await tierDe(w, 'general-purpose', 'sim', 3, 'medio');
  assert.equal(abaixoNao.pace.estado, 'abaixo');
  assert.ok(abaixoNao.reasons.includes('ritmo_sobe'));
  assert.ok(!abaixoSim.reasons.includes('ritmo_sobe'));
  await medir(w, semana(80)); // p = 0.5 (acima)
  const sim = await tierDe(w, 'general-purpose', 'sim');
  const nao = await tierDe(w, 'general-purpose', 'nao');
  const parcial = await tierDe(w, 'general-purpose', 'parcial');
  assert.equal(sim.pace.estado, 'acima');
  assert.ok(sim.reasons.includes('ritmo_desce') && TIERS.indexOf(sim.tier) === TIERS.indexOf(sim.tier_base) - 1);
  for (const x of [nao, parcial]) assert.ok(!x.reasons.includes('ritmo_desce') && x.tier === x.tier_base);
  const rev = await tierDe(w, 'revisor-codigo', 'sim', 4, 'alto');
  assert.ok(TIERS.indexOf(rev.tier) >= TIERS.indexOf(rev.floor), 'desceu abaixo do piso');
  await medir(w, []); // sem leitura: dentro
  assert.equal((await tierDe(w, 'general-purpose', 'sim')).pace.estado, 'dentro');
});

// ------------------------------------------------------------------ L1

test('L1 sinal de falha: registra por chave, nao re-executa, avisa so em enforce, e nao confunde resultado normal', async () => {
  for (const [modo, avisa] of [['shadow', false], ['enforce', true]]) {
    const w = mundo({ pol: politica(modo) });
    const e = chamada({ description: `tarefa ${modo}` });
    const chave = await derivarChave(e.subagent_type, e.description);
    const ok = await agent(w, e, { result: {}, text: 'tudo certo, testes verdes' });
    assert.equal(ok.chamadasNext, 1);
    assert.deepEqual(ok.saida.context, undefined);
    assert.ok(!(w.st.get('router.estado.sess-1') || {}).falhasPorChave?.[chave]);
    for (const [res, cod] of [[{ result: {}, text: 'Estado: NAO VERIFICADO' }, 'nao_verificado'], [{ result: { stop_reason: 'max_tokens' }, text: 'cortado' }, 'stop_max_tokens']]) {
      const r = await agent(w, e, res);
      assert.equal(r.chamadasNext, 1, 're-executou');
      assert.deepEqual(r.saida.context ?? [], avisa ? ['router: sinal de falha; a proxima tentativa desta tarefa sobe um nivel'] : []);
      assert.equal(w.ledger().at(-1).sinal, cod);
    }
    const salvo = w.st.get('router.estado.sess-1');
    assert.equal(salvo.falhasPorChave[chave], 2);
    assert.deepEqual(salvo.ordem, [chave]);
  }
});

// ------------------------------------------------------------------ L2

test('L2 ledger: 25 chamadas paralelas gravam 25 linhas; acima de 2 MiB rotaciona em 3 geracoes sem perder historico', async () => {
  const w = mundo({ pol: politica('shadow') });
  await Promise.all(Array.from({ length: 25 }, (_, i) => agent(w, chamada({ description: `paralela ${i}` }))));
  assert.equal(w.ledger().length, 25);
  const r = mundo({ pol: politica('shadow') });
  r.arq.set(LED, `${'a'.repeat(2097153)}\n`);
  r.arq.set(`${LED}.1`, 'G1\n');
  r.arq.set(`${LED}.2`, 'G2\n');
  await agent(r, chamada({}));
  assert.equal(r.arq.get(`${LED}.1`), `${'a'.repeat(2097153)}\n`);
  assert.equal(r.arq.get(`${LED}.2`), 'G1\n');
  assert.equal(r.arq.get(`${LED}.3`), 'G2\n');
  assert.equal(r.ledger().length, 1);
});
