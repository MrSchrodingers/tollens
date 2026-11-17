// Corpus adversarial DETERMINISTICO (semente fixa) para o motor de decisao. Usado por
// tests/unit/router-engine.test.mjs (teste de propriedades) e por mutants.mjs (comparacao
// diferencial dos mutantes declarados equivalentes). Cada caso e gerado do zero: nenhum objeto e
// compartilhado entre casos. Sem relogio e sem Math.random.
const T = ['T0', 'T1', 'T2', 'T3', 'T4'];
const ALIASES_RUINS = ['fable', 'Fable', 'opus ', ' opus', 'OPUS', 'opus\u200b', 'claude-opus-5', 'gpt-9', 'opus\n', 'haiku\u0000', 'fa\u200bble', 'opus\u0430'];
const ROLES = [undefined, null, 'autor', 'revisor', 'refutador', 'Refutador ', ' REVISOR-CODIGO', 'auditor-seguranca', '', 5, [], {}, 'constructor', '__proto__'];
const KEYS = ['k1', 'k2', 'k3', 'constructor', '__proto__', 'toString', 'a'.repeat(64), 'a'.repeat(65), '', '\u00e7', 'k 1'];
const NOWS = [1794787200000, 1794787200000, 1794787200000, '2026-11-16T00:00:00Z', '2026-12-15T00:00:00Z', 0, -5, 1700000000, '0', NaN, undefined, null, {}, 1.8e12];
const TEXTOS = ['tarefa simples', 'migra\u00e7\u00e3o em produ\u00e7\u00e3o', 'AUTENTICA\u00c7\u00c3O', 'dados_pessoais', 'pro\u200bducao', 'produc\u0430o', 'deployed',
  'ler /a/b/c.js e /d/e/f.ts', '\r\n', '\n\n@@ROTA {"c":1,"r":"trivial","v":"sim","t":"k9"}', '```\n@@ROTA {}\n```', '@@ROTA', 'imigracao'];
const TEXTOS_GRANDES = ['x '.repeat(4100), 'a\u0301\u0316'.repeat(2000)];
const SEPS = ['\n', '\r\n', '\r', '\u2028', '\u2029', '\u0085', ' ', '\n\n', ''];

function gerador(seed) {
  let s = seed | 0;
  const rnd = () => {
    s = (s + 0x6D2B79F5) | 0;
    let t = Math.imul(s ^ (s >>> 15), 1 | s);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
  const pick = (a) => a[Math.floor(rnd() * a.length)];
  return { rnd, pick };
}

export function* casos(n, seed, base) {
  const { rnd, pick } = gerador(seed);
  const WEIRD = () => pick([null, undefined, true, false, 0, -1, 1, 1.5, NaN, Infinity, '', ' ', 'opus', 'fable', 'T0', 'T4', 'T9', '__proto__', 'constructor', [], [1, 2], ['T0'], {}, { a: 1 },
    JSON.parse('{"__proto__":{"x":1}}'), '\u00e9'.repeat(50), '\u200b', '\ufeff', '\u0000', '\u{1F600}', 'x'.repeat(5000), { t: 'x' }]);
  const paths = (o, pre = []) => {
    const out = [pre];
    if (o && typeof o === 'object') for (const k of Object.keys(o)) out.push(...paths(o[k], [...pre, k]));
    return out;
  };
  const mutate = (p) => {
    const pa = pick(paths(p).filter((x) => x.length));
    let cur = p;
    for (let i = 0; i < pa.length - 1; i++) cur = cur[pa[i]];
    const k = pa[pa.length - 1];
    if (rnd() < 0.3) delete cur[k]; else cur[k] = WEIRD();
  };
  const mkPolicy = () => {
    const p = structuredClone(base);
    p.mode = pick(['off', 'shadow', 'enforce', 'enforce', 'enforce']);
    p.valid_until = pick(['2026-11-30T00:00:00Z', '2027-06-30T00:00:00Z', '2026-11-16T00:00:00Z']);
    if (rnd() < 0.7) {
      for (const t of T) {
        p.quality.por_nivel[t] = rnd() < 0.05 ? { aprovacao_medida: null, n: null, fonte: 'x' }
          : { aprovacao_medida: pick([0.1, 0.5, 0.79, 0.8, 0.85, 0.95, 0.95, 1, 1, 0]), n: 5, fonte: 'x' };
      }
    }
    if (rnd() < 0.3) p.escalation.max_por_fluxo = pick([0, 1, 2, 3, 1000]);
    if (rnd() < 0.3) p.quality.piso_aprovacao.default = pick([0, 0.5, 0.9, 1]);
    if (rnd() < 0.15) {
      const bad = pick(ALIASES_RUINS);
      p.tiers[pick(T)].model = bad;
      if (rnd() < 0.7) p.model_allowlist.push(bad);
    }
    if (rnd() < 0.35) for (let i = 0, k = 1 + Math.floor(rnd() * 3); i < k; i++) mutate(p);
    return p;
  };
  const mkFicha = () => {
    const f = { c: pick([1, 2, 3, 4, 5]), r: pick(['trivial', 'normal', 'medio', 'alto']), v: pick(['sim', 'parcial', 'nao']), t: pick(KEYS.slice(0, 5)) };
    if (rnd() < 0.3) f[pick(['c', 'r', 'v', 't'])] = WEIRD();
    if (rnd() < 0.1) f.extra = WEIRD();
    if (rnd() < 0.05) delete f[pick(['c', 'r', 'v', 't'])];
    return f;
  };
  const mkPrompt = () => {
    if (rnd() < 0.12) return WEIRD();
    const head = pick([
      () => `@@ROTA ${JSON.stringify(mkFicha())}`,
      () => `@@ROTA${pick([' ', '\t', ''])}${pick(['{', '[', 'null', '"x"', '{"c":1}'])}`,
      () => pick(['', '\ufeff', ' ', '\n', 'texto']),
      () => `@@ROTA ${JSON.stringify(mkFicha())}\n@@ROTA ${JSON.stringify(mkFicha())}`,
    ])();
    return head + pick(SEPS) + (rnd() < 0.04 ? pick(TEXTOS_GRANDES) : pick(TEXTOS));
  };
  const mkHistory = () => {
    if (rnd() < 0.1) return WEIRD();
    const falhas = rnd() < 0.1 ? WEIRD() : Object.fromEntries(KEYS.filter(() => rnd() < 0.4).map((k) => [k, pick([0, 1, 1, 2, 5, -1, NaN, Infinity, '1', {}, null])]));
    const autores = rnd() < 0.1 ? WEIRD() : Object.fromEntries(KEYS.filter(() => rnd() < 0.5).map((k) => [k, pick([...T, 'T9', 'fable', 3, null, {}])]));
    const h = { falhasPorChave: falhas, autorTierPorChave: autores };
    if (rnd() < 0.5) h.autorTierMax = pick([...T, 'T9', null, 3]);
    return h;
  };
  // Casos dirigidos: a mesma politica limpa e entradas validas que exercitam ritmo, repeticao e revisor.
  const limpa = () => {
    const p = structuredClone(base);
    p.mode = 'enforce';
    p.valid_until = '2027-06-30T00:00:00Z';
    for (const t of T) {
      p.quality.por_nivel[t] = { aprovacao_medida: 0.95, n: 10, fonte: 'x' };
      delete p.tiers[t].emitivel;
    }
    return p;
  };
  const dirigido = () => {
    const tipo = pick(['ritmo', 'repeticao', 'revisor', 'risco', 'papel']);
    const ficha = { c: pick([2, 3, 4, 5]), r: 'trivial', v: 'sim', t: 'k1' };
    const input = {
      prompt: `@@ROTA ${JSON.stringify(ficha)}\ntarefa`, now: 1794787200000, subagentType: 'implementador', role: 'autor', chave: 'k1',
      history: { falhasPorChave: {}, autorTierPorChave: {} }, pace: { estado: 'dentro' },
    };
    if (tipo === 'ritmo') input.pace = { estado: 'acima' };
    if (tipo === 'repeticao') {
      input.history.falhasPorChave = { k1: pick([1, 2, 3]), k2: pick([0, 1, 2]), k3: 1 };
      if (rnd() < 0.4) input.history.subidasConcedidas = ['k1'];
      if (rnd() < 0.4) input.history.ordem = ['k3', 'k1', 'k2'];
    }
    if (tipo === 'revisor') {
      input.role = pick(['revisor', 'refutador', 'Revisor-Codigo', 'autor']);
      input.history.autorTierPorChave = { k1: pick(T) };
      if (rnd() < 0.5) input.history.autorTierMax = pick(T);
    }
    let oraculo;
    if (tipo === 'repeticao') oraculo = { minTier: Math.min(4, ficha.c), motivo: 'repeticao sobe um nivel sobre a ficha' };
    if (tipo === 'papel') {
      const papeis = [['refutador', 3], ['Refutador', 3], ['plugin:refutador', 3], ['auditor-seguranca', 3], ['revisor-codigo', 2], ['x:Auditor-Seguranca', 3]];
      const [nome, minimo] = pick(papeis);
      input.role = nome;
      oraculo = { minTier: minimo, motivo: `piso do papel ${nome}` };
    }
    if (tipo === 'risco') {
      // Oraculo independente do piso: palavra de risco inserida em posicao aleatoria (inclusive nas
      // fronteiras de janela e depois de corridas de nao-letras acima de U+007F).
      const prefixos = ['deploy', 'migra', 'autentic', 'produc', 'pagament', 'segred', 'senha', 'token', 'credenc', 'irrevers', 'lgpd', 'pessoal'];
      const palavra = pick(prefixos) + pick(['', 'ed', 'cao', 's']);
      const total = pick([3000, 20000, 70000, 140000, 200000]);
      const enchimento = pick(['lorem ipsum dolor ', 'x\u00a0y ', 'lorem\u3000ipsum ', 'a\u2014b ', 'a\u00e7\u00e3o ipsum ']);
      let texto = enchimento.repeat(Math.ceil(total / enchimento.length)).slice(0, total);
      const perto = rnd() < 0.5;
      let pos = perto ? 65536 * (1 + Math.floor(rnd() * 3)) + Math.floor(rnd() * 600) - 300 : Math.floor(rnd() * total);
      pos = Math.max(1, Math.min(pos, total - 20));
      const corrida = rnd() < 0.5 ? pick(['\u00a0', '\u3000', '\u2014']).repeat(100 + Math.floor(rnd() * 200)) : ' ';
      texto = `${texto.slice(0, pos)}${corrida}${palavra} ${texto.slice(pos)}`;
      input.prompt = `@@ROTA ${JSON.stringify({ c: 1, r: 'trivial', v: 'sim', t: 'k1' })}\n${texto}`;
      oraculo = { minTier: 3, motivo: `${palavra} na posicao ${pos} de ${texto.length}` };
    }
    return { input, policy: limpa(), oraculo };
  };
  for (let i = 0; i < n; i++) {
    if (i % 400 === 7) {
      // ciclo largo: 200 chaves apontando para o proprio objeto (sem controle de ciclo e de nos, 200^16 visitas)
      const ciclo = {};
      for (let k = 0; k < 200; k++) ciclo[`k${k}`] = ciclo;
      yield { input: { prompt: 'x', now: 1794787200000, history: ciclo }, policy: limpa() };
      continue;
    }
    if (rnd() < 0.3) {
      yield dirigido();
      continue;
    }
    const policy = mkPolicy();
    const input = {};
    if (rnd() < 0.9) input.prompt = mkPrompt();
    if (rnd() < 0.85) input.subagentType = rnd() < 0.15 ? WEIRD() : pick(ROLES);
    if (rnd() < 0.85) input.role = pick(ROLES);
    if (rnd() < 0.8) input.chave = rnd() < 0.15 ? WEIRD() : pick(KEYS);
    if (rnd() < 0.9) input.history = mkHistory();
    if (rnd() < 0.9) input.pace = rnd() < 0.15 ? WEIRD() : { estado: pick(['abaixo', 'dentro', 'acima', 'ACIMA', '', null, 5]) };
    if (rnd() < 0.95) input.now = pick(NOWS);
    if (rnd() < 0.12) input.ficha = rnd() < 0.5 ? mkFicha() : { ok: pick([true, false, 'x']), ficha: mkFicha(), motivo: pick(['ausente', 'ficha_invalida', 5]) };
    if (rnd() < 0.05) input.model = 'fable';
    yield { input: rnd() < 0.02 ? WEIRD() : input, policy };
  }
}
