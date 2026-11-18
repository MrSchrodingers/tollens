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
//   C1  caminhos fixos: TOLLENS_ROUTER_* no ambiente nao mudam nada; o ledger nunca regrava arquivo alheio
//   A1  managed nega o modelo: melhor permitido, sem baixar do pedido, aviso uma vez; A2 efetivo no ledger; A3 ledger por sessao
//   A4  store.set falho nao derruba, poda do store; A5 sinais so de formato documentado; A6 ritmo invalido/vencido
//   M1/M2 evento nulo, fork, normalizacao de papel do motor, chave hostil no ledger
// Os `aprovacao_medida` das politicas sao FIXTURES SINTETICAS; nao sao medicao.
import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { criarMod, register } from '../../claude-plugins/plugins/tollens-router/hooks/register.js';
import { aparar, derivarChave, estadoVazio, hex16, linhaDeLedger, sinalDeFalha } from '../../claude-plugins/plugins/tollens-router/hooks/core.js';
import { validatePolicy } from '../../claude-plugins/plugins/tollens-router/engine.mjs';

const DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../claude-plugins/plugins/tollens-router');
const SHIPPED = JSON.parse(readFileSync(path.join(DIR, 'router-policy.json'), 'utf8'));
const NOW = Date.parse('2026-11-16T00:00:00Z');
const DIA = 86400000;
const TIERS = ['T0', 'T1', 'T2', 'T3', 'T4'];
const POL = '/root-fake/router-policy.json';
const LEDDIR = '/home-fake/.claude/logs';
const MAN = '/root-fake/managed-settings.json';
const LINHA0 = '{"evento":"tool.call","ts":null}';
const ledPath = async (sid = 'sess-1') => `${LEDDIR}/router-ledger-${await hex16(sid)}.jsonl`;
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
// `real: true` carrega o `register` instalado (caminhos fixos); o padrao usa `criarMod` com injecao.
function mundo({ pol, sentinela = false, cfg = {}, env = {}, agora = NOW, falha = {}, managed, sid = 'sess-1', real = false } = {}) {
  const arq = new Map();
  const st = new Map();
  const eventos = [];
  const avisos = [];
  let relogio = agora;
  if (pol !== undefined) arq.set(real ? '/etc/claude-code/router-policy.json' : POL, typeof pol === 'string' ? pol : JSON.stringify(pol));
  if (managed !== undefined) arq.set(real ? '/etc/claude-code/managed-settings.json' : MAN, typeof managed === 'string' ? managed : JSON.stringify(managed));
  if (sentinela === true) arq.set(SENT_PADRAO, '');
  else if (typeof sentinela === 'string') arq.set(sentinela, '');
  const ambiente = { HOME: '/home-fake', ...env };
  const quebra = (nome) => { if (falha[nome]) throw new Error(`CANARIO-ERRO-${nome}`); };
  const $ = {
    clock: { now: async () => { quebra('clock'); return typeof falha.agora === 'number' || falha.agora === 'x' ? falha.agora : relogio; } },
    env: { get: async (n) => ambiente[n] },
    fs: {
      read: async (p) => { await new Promise((r) => setImmediate(r)); if (!arq.has(p)) throw new Error('ENOENT'); return arq.get(p); },
      write: async (p, t) => { await new Promise((r) => setImmediate(r)); eventos.push(`fs.write:${p}`); arq.set(p, t); },
      exists: async (p) => { quebra('exists'); return arq.has(p); },
    },
    session: { id: async () => sid },
    store: {
      get: async (k) => { quebra('store'); return st.has(k) ? clone(st.get(k)) : undefined; },
      set: async (k, v) => { quebra('set'); eventos.push('store.set'); st.set(k, clone(v)); },
      delete: async (k) => { eventos.push(`store.delete:${k}`); st.delete(k); },
    },
    ui: { notice: (id, texto) => { avisos.push({ id, texto }); } },
  };
  const hooks = [];
  const reg = real ? register : criarMod({ politica: POL, managed: MAN, ledgerDir: LEDDIR, ...cfg });
  reg((ev, a, b) => { hooks.push({ ev, m: typeof a === 'function' ? null : a, fn: typeof a === 'function' ? a : b }); return { catch() {} }; });
  const ledger = (evento) => {
    const linhas = [];
    for (const [k, v] of arq) if (/\/router-ledger-[^/]*\.jsonl$/.test(k)) for (const l of v.split('\n').filter(Boolean)) linhas.push(JSON.parse(l));
    if (evento === '*') return linhas;
    return linhas.filter((l) => (evento ? l.evento === evento : l.evento === 'tool.call' || l.evento === 'agent.spawn'));
  };
  const textoLedger = () => [...arq].filter(([k]) => /router-ledger-/.test(k)).map(([, v]) => v).join('\n');
  return { $, arq, st, eventos, avisos, hooks, ledger, textoLedger, setAgora: (x) => { relogio = x; } };
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
    const bruto = w.textoLedger();
    assert.ok(!bruto.includes('CANARIO'), 'mensagem da excecao ou prompt vazou para o ledger');
    const linhas = w.ledger();
    assert.equal(linhas.length, 1);
    assert.match(linhas[0].erro, /^excecao/);
  }
});

// ------------------------------------------------------------------ I4

test('I4 ledger sem prompt, descricao, resultado, ficha.t nem tipo livre (canario), em shadow e enforce', async () => {
  const campos = ['ts', 'evento', 'session_id', 'tool_use_id', 'agent_type', 'role', 'chave', 'ficha', 'floor', 'tier_base', 'tier',
    'pedido', 'aplicado', 'permitido', 'mode', 'modo_efetivo', 'pace', 'capped', 'subida_concedida', 'reasons', 'efetivo', 'usados', 'sinal', 'erro'];
  for (const modo of ['shadow', 'enforce']) {
    const w = mundo({ pol: politica(modo) });
    const e = chamada({
      subagent_type: 'CANARIO-TIPO livre', description: 'CANARIO-DESC-7731',
      prompt: `${ROTA(3, 'medio', 'nao', 'CANARIO-T')}\nCANARIO-PROMPT-7731 deploy do /etc/senha`,
    });
    await agent(w, e, { result: {}, text: 'CANARIO-RES-7731 NAO VERIFICADO' });
    const bruto = w.textoLedger();
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

test('I6 sentinela de root vence enforce: chamada intacta, nada persistido; a sentinela da config de teste tambem vale', async () => {
  for (const sentinela of [true, '/outro/router-off']) {
    const w = mundo({ pol: politica('enforce'), sentinela, cfg: typeof sentinela === 'string' ? { sentinela } : {} });
    const e = chamada({ subagent_type: 'revisor-codigo', model: 'haiku' });
    const { recebido } = await agent(w, e);
    assert.deepEqual(recebido, e);
    assert.ok(!w.eventos.includes('store.set'));
    assert.deepEqual(w.ledger()[0].reasons, ['sentinela_off']);
    assert.equal(w.ledger()[0].mode, 'off');
  }
  // a config de teste nao desarma a sentinela padrao
  const w = mundo({ pol: politica('enforce'), sentinela: true, cfg: { sentinela: '/nao/existe' } });
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

test('I8 agent.spawn de workflow: define model acima do da variavel haiku (sem tocar o ambiente) so em enforce, so para cima; ignora resume, fork e subagente comum', async () => {
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
    for (const [res, cod] of [[{ result: {}, text: 'Resumo\nEstado: NAO VERIFICADO' }, 'linha_estruturada'], [{ isError: true, result: {}, text: 'cortado' }, 'erro_ferramenta']]) {
      const r = await agent(w, e, res);
      assert.equal(r.chamadasNext, 1, 're-executou');
      assert.deepEqual(r.saida.context ?? [], avisa ? ['router: sinal de falha; a proxima tentativa desta tarefa sobe um nivel'] : []);
      assert.equal(w.ledger('resultado').at(-1).sinal, cod);
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
  const L = await ledPath();
  const grande = `${LINHA0}\n${'a'.repeat(2097153)}\n`;
  r.arq.set(L, grande);
  r.arq.set(`${L}.1`, `${LINHA0}\nG1\n`);
  r.arq.set(`${L}.2`, `${LINHA0}\nG2\n`);
  await agent(r, chamada({}));
  assert.equal(r.arq.get(`${L}.1`), grande);
  assert.equal(r.arq.get(`${L}.2`), `${LINHA0}\nG1\n`);
  assert.equal(r.arq.get(`${L}.3`), `${LINHA0}\nG2\n`);
  assert.equal(r.ledger().filter((l) => l.evento !== null && l.reasons).length >= 1, true);
});

// ------------------------------------------------------------------ rodada 2

test('C1 modulo instalado: variaveis TOLLENS_ROUTER_* no ambiente nao mudam politica, sentinela nem ledger', async () => {
  const env = { TOLLENS_ROUTER_POLICY: '/evil/politica.json', TOLLENS_ROUTER_SENTINEL: '/evil/sentinela', TOLLENS_ROUTER_LEDGER: '/home-fake/.bashrc' };
  // politica fixa ausente: o modulo real nao le a do ambiente e nada e alterado
  const w = mundo({ real: true, env });
  w.arq.set('/evil/politica.json', JSON.stringify(politica('enforce')));
  const e = chamada({ subagent_type: 'revisor-codigo', model: 'haiku' });
  assert.deepEqual((await agent(w, e)).recebido, e);
  assert.ok(![...w.arq.keys()].some((k) => k.includes('.bashrc') && k !== '/home-fake/.bashrc'), 'escreveu no caminho do ambiente');
  assert.ok(![...w.eventos].includes('fs.write:/home-fake/.bashrc'));
  for (const k of w.arq.keys()) if (w.eventos.includes(`fs.write:${k}`)) assert.match(k, /^\/home-fake\/\.claude\/logs\/router-ledger-[0-9a-f]{16}\.jsonl$/);
  // politica fixa presente em enforce: aplica; o ambiente nao a desarma
  const w2 = mundo({ real: true, env, pol: politica('enforce') });
  assert.equal((await agent(w2, e)).recebido.model, 'opus');
});

test('C1 ledger nunca regrava arquivo alheio: nem o do proprio nome, nem as geracoes na rotacao', async () => {
  const alheio = '# ~/.bashrc\nexport PATH=$PATH:/x\n';
  const L = await ledPath();
  for (const outro of [alheio, '{"name":"pacote"}\n', '{"evento":"x","campo_alheio":1}\n']) {
    const w = mundo({ pol: politica('shadow') });
    w.arq.set(L, outro);
    await agent(w, chamada({}));
    assert.equal(w.arq.get(L), outro);
  }
  const r = mundo({ pol: politica('shadow') });
  r.arq.set(L, `${LINHA0}\n${'a'.repeat(2097153)}\n`);
  r.arq.set(`${L}.2`, alheio);
  await agent(r, chamada({}));
  assert.equal(r.arq.get(`${L}.2`), alheio);
  assert.ok(!r.arq.has(`${L}.1`) && !r.arq.has(`${L}.3`), 'rotacionou sobre arquivo alheio');
});

test('A1 managed nega o modelo: fallback so se atinge o piso do motor; sem nivel permitido a altura nada e aplicado; ilegivel nao restringe', async () => {
  const managed = { availableModels: ['sonnet', 'haiku'], deniedModels: ['opus', 'fable'] };
  // piso T3 (revisor-codigo, opus): o melhor permitido (sonnet/high, T2) fica ABAIXO do piso -> nada e aplicado
  const w = mundo({ pol: politica('enforce'), managed });
  const e = chamada({ subagent_type: 'revisor-codigo', model: 'haiku' });
  const a = await agent(w, e);
  assert.deepEqual(a.recebido, e, 'aplicou abaixo do piso do motor');
  const l = w.ledger()[0];
  assert.equal(l.pedido.model, 'opus');
  assert.equal(l.aplicado.model, null);
  assert.deepEqual([l.permitido.model, l.permitido.effort], ['sonnet', 'high']);
  assert.ok(l.reasons.includes('managed_nega_piso') && !l.reasons.includes('managed_nega_modelo'));
  await agent(w, chamada({ subagent_type: 'revisor-codigo', model: 'haiku' }));
  assert.equal(w.avisos.length, 1);
  // sem piso de papel (T4 por ficha): o melhor permitido (T2) atinge o piso (T0) e e aplicado
  const w1 = mundo({ pol: politica('enforce'), managed });
  const alto = chamada({ prompt: `${ROTA(5, 'alto', 'nao')}\ncorpo neutro`, model: 'haiku' });
  const r1 = await agent(w1, alto);
  assert.deepEqual([r1.recebido.model, r1.recebido.effort], ['sonnet', 'high']);
  assert.ok(w1.ledger()[0].reasons.includes('managed_nega_modelo'));
  // o orquestrador pediu opus: o model dele nao e rebaixado
  const w2 = mundo({ pol: politica('enforce'), managed });
  const pedido = chamada({ prompt: `${ROTA(5, 'alto', 'nao')}\ncorpo neutro`, model: 'opus' });
  assert.equal((await agent(w2, pedido)).recebido.model, 'opus');
  // agent.spawn de workflow: com piso T3 nada muda; sem piso sobe so ate o permitido
  const wf = { tool_use_id: 'toolu_wfm', prompt: 'p', description: 'revisar', subagentType: 'revisor-codigo', provider: {}, parentModel: 'claude-opus-4', background: true, fork: false, workflow: { runId: 'wf_1', agentIndex: 1 } };
  const env = { CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL: 'haiku' };
  assert.deepEqual(await spawn(mundo({ pol: politica('enforce'), managed, env }), wf), wf);
  const wf2 = { ...wf, subagentType: 'general-purpose', description: 'item alto', prompt: `${ROTA(5, 'alto', 'nao')}\ncorpo` };
  assert.equal((await spawn(mundo({ pol: politica('enforce'), managed, env }), wf2)).model, 'sonnet');
  // managed ilegivel ou ausente: falha aberta, sem restricao conhecida
  for (const m of ['{nao json', undefined]) {
    const w4 = mundo({ pol: politica('enforce'), managed: m });
    assert.equal((await agent(w4, chamada({ subagent_type: 'revisor-codigo' }))).recebido.model, 'opus');
  }
});

test('D1b managed lido no maximo a cada 30 s: mudanca dentro da janela nao vale, depois vale', async () => {
  const w = mundo({ pol: politica('enforce'), managed: {} });
  const rev = () => chamada({ subagent_type: 'revisor-codigo', model: 'haiku' });
  assert.equal((await agent(w, rev())).recebido.model, 'opus');
  w.arq.set(MAN, JSON.stringify({ deniedModels: ['opus'] }));
  w.setAgora(NOW + 10000);
  assert.equal((await agent(w, rev())).recebido.model, 'opus', 'releu dentro da janela');
  w.setAgora(NOW + 31000);
  assert.equal((await agent(w, rev())).recebido.model, 'haiku', 'nao releu depois da janela');
});

test('A2 efetivo: linha `efetivo` ligada ao tool_use_id com resolvedModel e modelsUsed; sem o campo, null', async () => {
  const w = mundo({ pol: politica('shadow') });
  const e = chamada({ tool_use_id: 'toolu_ef' });
  await agent(w, e, { result: { resolvedModel: 'claude-sonnet-5-5', modelsUsed: ['claude-sonnet-5-5', 'claude-haiku-4-5'] }, text: 'ok' });
  await agent(w, chamada({ tool_use_id: 'toolu_ef2' }), { result: {}, text: 'ok' });
  const ef = w.ledger('efetivo');
  assert.deepEqual([ef[0].tool_use_id, ef[0].efetivo, ef[0].usados], ['toolu_ef', 'claude-sonnet-5-5', ['claude-sonnet-5-5', 'claude-haiku-4-5']]);
  assert.deepEqual([ef[1].tool_use_id, ef[1].efetivo], ['toolu_ef2', null]);
});

test('A3 ledger por sessao (nome com 16 hex do sha256 do session_id); sem session_id nao persiste nada e registra', async () => {
  const a = mundo({ pol: politica('shadow'), sid: 'sess-1' });
  const b = mundo({ pol: politica('shadow'), sid: 'sess-2' });
  await agent(a, chamada({}));
  await agent(b, chamada({}));
  assert.ok(a.arq.has(await ledPath('sess-1')) && b.arq.has(await ledPath('sess-2')));
  assert.notEqual(await ledPath('sess-1'), await ledPath('sess-2'));
  for (const sid of [null, '']) {
    const w = mundo({ pol: politica('shadow'), sid });
    await agent(w, chamada({}));
    assert.ok(!w.eventos.includes('store.set'), 'gravou em chave compartilhada');
    assert.ok(![...w.st.keys()].length);
    assert.ok(w.ledger()[0].reasons.includes('sem_sessao_id'));
  }
});

test('A4 falha de store.set nao derruba o roteamento (aplica, registra, avisa uma vez); o store guarda so as ultimas 50 sessoes e expira 14 dias', async () => {
  const w = mundo({ pol: politica('enforce'), falha: { set: true } });
  const e = chamada({ subagent_type: 'revisor-codigo', model: 'haiku' });
  assert.equal((await agent(w, e)).recebido.model, 'opus');
  await agent(w, chamada({ subagent_type: 'revisor-codigo', model: 'haiku' }));
  assert.ok(w.ledger()[0].reasons.includes('persistencia_falhou'));
  assert.equal(w.avisos.length, 1);
  const p = mundo({ pol: politica('shadow'), sid: 'atual' });
  const indice = [];
  for (let i = 0; i < 60; i++) { indice.push([`s${i}`, NOW - (60 - i) * 60000]); p.st.set(`router.estado.s${i}`, estadoVazio()); }
  indice.push(['velha', NOW - 15 * DIA]);
  p.st.set('router.estado.velha', estadoVazio());
  p.st.set('router.indice', indice);
  await agent(p, chamada({}));
  const restantes = [...p.st.keys()].filter((k) => k.startsWith('router.estado.'));
  assert.ok(restantes.length <= 50, `${restantes.length} sessoes no store`);
  assert.ok(restantes.includes('router.estado.atual') && !restantes.includes('router.estado.velha') && !restantes.includes('router.estado.s0'));
});

test('A5 sinais de falha: so campos documentados e linha estruturada; texto solto nao conta (corpus)', () => {
  const nega = [
    { result: {}, text: 'RISCOS: NAO VERIFICADO: carga real' },
    { result: {}, text: 'segue o Estado: NAO VERIFICADO do item anterior' },
    { result: {}, text: 'o teste que falhou antes agora passa' },
    { result: {}, text: 'nada refutado; o contrato reprovado antes foi corrigido' },
    { result: { stop_reason: 'max_tokens' }, text: 'fim' },
    { result: { status: 'async_launched' }, text: 'lancado' },
    { result: { status: 'running' }, text: 'em curso' },
    { result: { status: 'completed' }, text: 'Estado do repositorio: limpo' },
    { result: 'REFUTADO', text: '' },
    null,
  ];
  for (const r of nega) assert.equal(sinalDeFalha(r), null, JSON.stringify(r));
  const positivos = [
    [{ result: {}, text: 'Resumo\nEstado: NAO VERIFICADO' }, 'linha_estruturada'],
    [{ result: {}, text: 'veredito: REFUTADO' }, 'linha_estruturada'],
    [{ result: {}, text: 'x\nResultado: REPROVADO (3 falhas)' }, 'linha_estruturada'],
    [{ result: {}, text: 'Estado: NÃO VERIFICADO' }, 'linha_estruturada'],
    [{ isError: true, result: {}, text: '' }, 'erro_ferramenta'],
    [{ result: { status: 'failed' }, text: '' }, 'status_falha'],
  ];
  for (const [r, cod] of positivos) assert.equal(sinalDeFalha(r), cod);
});

test('A6 ritmo: leitura invalida (alem de 7 dias, passado, ausente, percentual fora de [0,100]) vale dentro; a leitura expira em 30 min', async () => {
  const w = mundo({ pol: politica('shadow') });
  const valida = (usado) => [{ kind: 'seven_day', percentUsed: usado, resetsAt: new Date(NOW + 0.7 * 7 * DIA).toISOString() }];
  const estado = async () => { await agent(w, chamada({})); return w.ledger().at(-1).pace.estado; };
  await medir(w, valida(80));
  assert.equal(await estado(), 'acima');
  const invalidas = [
    [{ kind: 'seven_day', percentUsed: 80, resetsAt: new Date(NOW + 8 * DIA).toISOString() }],
    [{ kind: 'seven_day', percentUsed: 80, resetsAt: new Date(NOW - 1000).toISOString() }],
    [{ kind: 'seven_day', percentUsed: 80 }],
    valida(120), valida(-5), valida(Number.NaN), valida('80'),
  ];
  for (const rl of invalidas) {
    await medir(w, valida(80));
    await medir(w, rl);
    assert.equal(await estado(), 'dentro', JSON.stringify(rl));
  }
  await medir(w, valida(80));
  w.setAgora(NOW + 31 * 60000);
  assert.equal(await estado(), 'dentro', 'leitura vencida ainda vale');
});

test('M1 evento nulo nao derruba; fork nao recebe model nem effort; papel de revisor usa a normalizacao do motor (homoglifo)', async () => {
  const w = mundo({ pol: politica('enforce') });
  for (const ev of ['tool.call', 'agent.spawn']) {
    const h = w.hooks.find((x) => x.ev === ev);
    assert.equal(await h.fn(w.$, null, async (x) => x), null);
  }
  const fork = chamada({ subagent_type: 'fork' });
  assert.deepEqual((await agent(w, fork)).recebido, fork);
  const hostil = chamada({ subagent_type: 'revisоr-codigo', description: 'critica por homoglifo' });
  await agent(w, hostil);
  assert.equal(w.st.get('router.estado.sess-1').chavesCriticas.length, 1);
});

test('M2 linha de ledger: chave hostil vira so 16 hex ou null; texto livre em modelo efetivo vira null', () => {
  const l = (c) => JSON.parse(linhaDeLedger(c));
  assert.equal(l({ chave: `${'a'.repeat(64)}`, evento: 'tool.call' }).chave, 'a'.repeat(16));
  assert.equal(l({ chave: 'CANARIO-descricao-livre', evento: 'tool.call' }).chave, null);
  assert.equal(l({ chave: `${'a'.repeat(63)} `, evento: 'tool.call' }).chave, null);
  assert.equal(l({ efetivo: 'texto do resultado com espacos', evento: 'efetivo' }).efetivo, null);
});

test('D2 sessao antiga mas ATIVA nao e podada: o carimbo e de atividade; so a inativa ha 14 dias sai', async () => {
  const w = mundo({ pol: politica('shadow'), sid: 'viva' });
  w.st.set('router.indice', [['viva', NOW - 15 * DIA], ['inativa', NOW - 15 * DIA], ['recente', NOW - 60000]]);
  w.st.set('router.estado.inativa', estadoVazio());
  w.st.set('router.estado.recente', estadoVazio());
  await agent(w, chamada({}));
  const indice = Object.fromEntries(w.st.get('router.indice'));
  assert.equal(indice.viva, NOW);
  assert.ok(w.st.has('router.estado.viva') && !w.st.has('router.estado.inativa') && w.st.has('router.estado.recente'));
});

test('D3 leitura do ledger que falha uma vez nao regrava o ledger da sessao com conteudo vazio', async () => {
  const w = mundo({ pol: politica('shadow') });
  const L = await ledPath();
  const antes = `${LINHA0}\n{"evento":"efetivo","ts":null,"tool_use_id":"toolu_hist"}\n`;
  w.arq.set(L, antes);
  const leitura = w.$.fs.read;
  let falhou = false;
  w.$.fs.read = async (p) => { if (p === L && !falhou) { falhou = true; throw new Error('EIO transitorio'); } return leitura(p); };
  await agent(w, chamada({}));
  assert.ok(w.arq.get(L).startsWith(antes), 'regravou o ledger apos erro de leitura (historico perdido)');
  assert.ok([...w.st.keys()].some((k) => k.startsWith('router.ledger_erro.')), 'erro nao registrado');
  await agent(w, chamada({ tool_use_id: 'toolu_d3b' }));
  assert.ok(w.arq.get(L).startsWith(antes) && w.ledger().some((l) => l.tool_use_id === 'toolu_d3b'), 'nao voltou a anexar');
});

test('A5b revisor/refutador/auditor: REPROVADO e REFUTADO do trabalho revisado nao contam; NAO VERIFICADO conta', async () => {
  const w = mundo({ pol: politica('shadow') });
  const rev = chamada({ subagent_type: 'refutador', description: 'refutar a tarefa' });
  await agent(w, rev, { result: {}, text: 'Veredito: REFUTADO\nResultado: REPROVADO' });
  assert.ok(!w.st.get('router.estado.sess-1')?.falhasPorChave || Object.keys(w.st.get('router.estado.sess-1').falhasPorChave).length === 0);
  await agent(w, rev, { result: {}, text: 'Estado: NAO VERIFICADO' });
  assert.equal(Object.keys(w.st.get('router.estado.sess-1').falhasPorChave).length, 1);
  const aut = chamada({ subagent_type: 'general-purpose', description: 'autor' });
  await agent(w, aut, { result: {}, text: 'Veredito: REPROVADO' });
  assert.equal(Object.keys(w.st.get('router.estado.sess-1').falhasPorChave).length, 2);
});

// ------------------------------------------------------------------ rodada 4

test('R4a carimbo de atividade refrescado em toda chamada ativa (estado inalterado; registrarFalha) e a escrita de outra sessao nao poda a viva', async () => {
  const chaveFixa = await derivarChave('general-purpose', 'tarefa fixa');
  const seed = { falhasPorChave: { [chaveFixa]: 1 }, subidasConcedidas: [chaveFixa], ordem: [chaveFixa], autorTierPorChave: { [chaveFixa]: 'T3' }, chavesCriticas: [] };
  const fixa = (id) => chamada({ tool_use_id: id, description: 'tarefa fixa', prompt: `${ROTA(3, 'medio', 'nao')}\nfaca` });
  // (1) chamada sem mudanca de estado
  const w = mundo({ pol: politica('shadow'), sid: 'viva' });
  w.st.set('router.indice', [['viva', NOW - 15 * DIA]]);
  w.st.set('router.estado.viva', seed);
  await agent(w, fixa('t1'));
  assert.equal(Object.fromEntries(w.st.get('router.indice')).viva, NOW, 'carimbo nao refrescado sem mudanca de estado');
  const o2 = mundo({ pol: politica('shadow'), sid: 'outra' });
  for (const k of ['get', 'set', 'delete']) o2.$.store[k] = w.$.store[k];
  await agent(o2, chamada({ description: 'outra tarefa' }));
  assert.ok(w.st.has('router.estado.viva'), 'escrita de outra sessao apagou o estado da sessao viva');
  // (2) falha do resultado: o relogio avanca durante a chamada; o carimbo (ainda valido no decidir) e refrescado em registrarFalha
  const f = mundo({ pol: politica('shadow'), sid: 'viva' });
  f.st.set('router.indice', [['viva', NOW - 30 * 60000]]);
  const h = f.hooks.find((x) => x.ev === 'tool.call');
  await h.fn(f.$, clone(fixa('t2')), async () => { f.setAgora(NOW + 2 * 3600000); return { result: {}, text: 'Estado: NAO VERIFICADO' }; });
  assert.equal(Object.fromEntries(f.st.get('router.indice')).viva, NOW + 2 * 3600000, 'registrarFalha nao refrescou o carimbo');
});

test('R4b falha de store.delete na poda nao impede a persistencia do estado da chamada atual; gravacoes precedem as remocoes', async () => {
  const w = mundo({ pol: politica('shadow'), sid: 'atual' });
  const indice = [];
  for (let i = 0; i < 55; i++) { indice.push([`s${i}`, NOW - (60 - i) * 60000]); w.st.set(`router.estado.s${i}`, estadoVazio()); }
  w.st.set('router.indice', indice);
  const apagar = w.$.store.delete;
  w.$.store.delete = async (k) => { await apagar(k); throw new Error('EIO delete'); };
  await agent(w, chamada({ description: 'chamada atual' }));
  assert.ok(w.st.has('router.estado.atual'), 'estado da chamada atual nao persistido');
  assert.ok(Object.fromEntries(w.st.get('router.indice')).atual === NOW);
  assert.ok(!w.ledger()[0].reasons.includes('persistencia_falhou'), 'falha de delete virou falha de persistencia');
  assert.ok(w.eventos.filter((x) => x.startsWith('store.delete:')).length >= 5, 'uma falha de delete interrompeu as demais remocoes');
  const primeiraRemocao = w.eventos.findIndex((x) => x.startsWith('store.delete:'));
  assert.ok(primeiraRemocao !== -1 && w.eventos.lastIndexOf('store.set') < primeiraRemocao, 'remocao antes da gravacao');
});

test('R4c ledger: leitura que devolve vazio de arquivo existente (escrita em curso) nao e regravada; registra erro e volta a anexar', async () => {
  const w = mundo({ pol: politica('shadow') });
  const L = await ledPath();
  const antes = `${LINHA0}\n{"evento":"efetivo","ts":null,"tool_use_id":"toolu_hist"}\n`;
  w.arq.set(L, antes);
  const leitura = w.$.fs.read;
  let vazio = true;
  w.$.fs.read = async (p) => { if (p === L && vazio) { vazio = false; return ''; } return leitura(p); };
  await agent(w, chamada({}));
  assert.ok(w.arq.get(L).startsWith(antes), 'regravou o ledger apos leitura vazia (historico perdido)');
  assert.ok([...w.st.keys()].some((k) => k.startsWith('router.ledger_erro.')), 'leitura vazia nao registrada');
  await agent(w, chamada({ tool_use_id: 'toolu_r4c' }));
  assert.ok(w.arq.get(L).startsWith(antes) && w.ledger().some((l) => l.tool_use_id === 'toolu_r4c'));
});

test('R4d rotacao: geracao alheia registra o erro; lacuna entre geracoes nao duplica conteudo nem sobrescreve geracao mais antiga', async () => {
  const L = await ledPath();
  const grande = `${LINHA0}\n${'a'.repeat(2097153)}\n`;
  const alheio = '# ~/.bashrc\nexport X=1\n';
  const bloq = mundo({ pol: politica('shadow') });
  bloq.arq.set(L, grande);
  bloq.arq.set(`${L}.2`, alheio);
  await agent(bloq, chamada({}));
  assert.equal(bloq.arq.get(L), grande);
  assert.ok([...bloq.st.keys()].some((k) => k.startsWith('router.ledger_erro.')), 'rotacao bloqueada sem registro');
  const G1 = `${LINHA0}\nG1\n`;
  const G2 = `${LINHA0}\nG2\n`;
  const G3 = `${LINHA0}\nG3\n`;
  for (const [ger, esperado] of [
    [{ 2: G2 }, { 1: grande, 2: G2 }], // .1 ausente: .2 nao desce para .3
    [{ 1: G1, 3: G3 }, { 1: grande, 2: G1, 3: G3 }], // .2 ausente: .3 permanece
  ]) {
    const w = mundo({ pol: politica('shadow') });
    w.arq.set(L, grande);
    for (const [g, t] of Object.entries(ger)) w.arq.set(`${L}.${g}`, t);
    await agent(w, chamada({}));
    for (const g of [1, 2, 3]) assert.equal(w.arq.get(`${L}.${g}`), esperado[g], `geracao .${g}`);
  }
});

test('R4e managed: availableModels sozinho nega, token em deniedModels nega o alias, e o fork case-insensitive nao recebe model', async () => {
  for (const managed of [{ availableModels: ['sonnet', 'haiku'] }, { deniedModels: ['claude-opus-5'] }]) {
    const w = mundo({ pol: politica('enforce'), managed });
    const e = chamada({ subagent_type: 'revisor-codigo', model: 'haiku' });
    const { recebido } = await agent(w, e);
    assert.deepEqual(recebido, e, JSON.stringify(managed));
    assert.ok(w.ledger()[0].reasons.includes('managed_nega_piso'), JSON.stringify(managed));
  }
  for (const tipo of ['Fork', 'FORK']) {
    const e = chamada({ subagent_type: tipo, model: 'haiku' });
    assert.deepEqual((await agent(mundo({ pol: politica('enforce') }), e)).recebido, e, tipo);
  }
});
