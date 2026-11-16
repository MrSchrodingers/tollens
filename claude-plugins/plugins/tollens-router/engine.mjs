// Motor de decisao do roteador interno de modelos (R1). Modulo PURO: sem relogio, sem I/O, sem
// aleatoriedade e sem dependencia externa. O tempo (`input.now`) e o ritmo (`input.pace`) entram
// como argumento. A ligacao ao Claude Code (hooks, ledger, sentinela de root) e a fatia R2.
//
// Contrato:
//   decide(input, policy) -> { tier, model, effort, floor, reasons, capped, mode, aplicar }
//   parseRota(prompt)     -> { ok:true, ficha } | { ok:false, motivo: 'ausente' | 'ficha_invalida' }
//   stripRota(prompt)     -> prompt sem a linha `@@ROTA` inicial
//   validatePolicy(policy, { now }) -> { ok:true } | { ok:true, degradaPara:'shadow' } | { ok:false, erros }
//
// Invariantes: tier >= piso; o piso so sobe; o modelo vem sempre da allowlist da politica e nunca
// e fable; a ficha e o texto do prompt so podem ELEVAR o nivel; politica invalida => modo off.

const TIER_NAMES = ['T0', 'T1', 'T2', 'T3', 'T4'];
const TOPO = TIER_NAMES.length - 1;
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];
const MODES = ['off', 'shadow', 'enforce'];
const RISCOS = ['trivial', 'normal', 'medio', 'alto'];
const VERIFICABILIDADES = ['sim', 'parcial', 'nao'];
const ESTADOS_RITMO = ['abaixo', 'dentro', 'acima'];
const COMPLEXIDADES = ['1', '2', '3', '4', '5'];

export const CAMPOS_OBRIGATORIOS = [
  'schema_version', 'version', 'mode', 'valid_until', 'model_allowlist', 'tiers',
  'ficha_tiers', 'role_floors', 'reviewer_roles', 'risk_surface', 'size', 'pace',
  'escalation', 'quality',
];

const MAX_LINHA_BYTES = 2048;
const MAX_TOKEN_CAMINHO = 512;
const PREFIXO_ROTA = /^@@ROTA(?:[ \t]|$)/;
const CHAVE_RE = /^[A-Za-z0-9._:-]{1,64}$/;
const INSTANTE_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const ALIAS_RE = /^[a-z0-9][a-z0-9._-]{0,63}$/;
const CHARSET_CAMINHO_RE = /^[A-Za-z0-9_.~/-]+$/;
const EXTENSAO_RE = /\.[A-Za-z0-9]{1,8}$/;
const FABLE_RE = /fable/i;

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);
const own = (o, k) => isObj(o) && Object.hasOwn(o, k);
const tierIdx = (t) => (typeof t === 'string' ? TIER_NAMES.indexOf(t) : -1);

// ---------------------------------------------------------------- ficha

function primeiraLinha(texto) {
  const nl = texto.indexOf('\n');
  let linha = nl < 0 ? texto : texto.slice(0, nl);
  if (linha.endsWith('\r')) linha = linha.slice(0, -1);
  return linha;
}

const invalida = () => ({ ok: false, motivo: 'ficha_invalida' });
const ausente = () => ({ ok: false, motivo: 'ausente' });

function validateFicha(obj) {
  if (!isObj(obj)) return invalida();
  const chaves = Object.keys(obj);
  if (chaves.length !== 4 || !['c', 'r', 'v', 't'].every((k) => chaves.includes(k))) return invalida();
  const { c, r, v, t } = obj;
  if (typeof c !== 'number' || !Number.isInteger(c) || c < 1 || c > 5) return invalida();
  if (!RISCOS.includes(r) || !VERIFICABILIDADES.includes(v)) return invalida();
  if (typeof t !== 'string' || !CHAVE_RE.test(t)) return invalida();
  return { ok: true, ficha: { c, r, v, t } };
}

export function parseRota(prompt) {
  if (typeof prompt !== 'string') return ausente();
  const linha = primeiraLinha(prompt);
  if (!PREFIXO_ROTA.test(linha)) return ausente();
  if (linha.length > MAX_LINHA_BYTES || new TextEncoder().encode(linha).length > MAX_LINHA_BYTES) return invalida();
  let obj;
  try {
    obj = JSON.parse(linha.slice('@@ROTA'.length));
  } catch {
    return invalida();
  }
  return validateFicha(obj);
}

export function stripRota(prompt) {
  if (typeof prompt !== 'string') return '';
  if (!PREFIXO_ROTA.test(primeiraLinha(prompt))) return prompt;
  const nl = prompt.indexOf('\n');
  return nl < 0 ? '' : prompt.slice(nl + 1);
}

// `input.ficha` ausente: le a primeira linha do prompt. Presente: e o retorno de parseRota ou uma
// ficha crua; nos dois casos a ficha e validada de novo, entao um objeto montado a mao nao passa.
function resolverFicha(input) {
  const f = input.ficha;
  if (f === undefined || f === null) return parseRota(input.prompt);
  if (isObj(f) && typeof f.ok === 'boolean') {
    if (f.ok) return validateFicha(f.ficha);
    return f.motivo === 'ausente' ? ausente() : invalida();
  }
  return validateFicha(f);
}

// ---------------------------------------------------------------- texto do prompt

function tokens(texto) {
  return texto.normalize('NFD').replace(/\p{M}+/gu, '').toLowerCase().match(/[\p{L}\p{N}]+/gu) ?? [];
}

function temSuperficieDeRisco(texto, palavras) {
  const alvo = ` ${tokens(texto).join(' ')} `;
  return palavras.some((p) => {
    const norm = tokens(p).join(' ');
    return norm !== '' && alvo.includes(` ${norm} `);
  });
}

function pareceCaminho(tok) {
  if (!tok.includes('/') || !CHARSET_CAMINHO_RE.test(tok) || !/[A-Za-z0-9]/.test(tok)) return false;
  if (tok.startsWith('/') || tok.startsWith('~') || tok.startsWith('./') || tok.startsWith('../')) return true;
  if (EXTENSAO_RE.test(tok)) return true;
  return tok.split('/').length - 1 >= 2;
}

// Conta caminhos DISTINTOS e para ao passar do limiar: o custo fica limitado pelo prompt, linear.
function contaCaminhos(texto, limite) {
  const vistos = new Set();
  for (const tok of texto.split(/[\s"'`()[\]<>,;]+/)) {
    if (tok.length < 3 || tok.length > MAX_TOKEN_CAMINHO || !pareceCaminho(tok)) continue;
    vistos.add(tok);
    if (vistos.size > limite) break;
  }
  return vistos.size;
}

// ---------------------------------------------------------------- politica

function instante(now) {
  if (typeof now === 'number') return Number.isFinite(now) ? now : NaN;
  if (now instanceof Date) return now.getTime();
  if (typeof now === 'string') return Date.parse(now);
  return NaN;
}

// 'sem_relogio' e 'vencida' degradam; politica vigente devolve null.
function situacaoDeValidade(validUntil, now) {
  const agora = instante(now);
  if (Number.isNaN(agora)) return 'sem_relogio';
  return agora >= Date.parse(validUntil) ? 'vencida' : null;
}

function exato(obj, esperadas, caminho, erros) {
  if (!isObj(obj)) {
    erros.push(`${caminho}: nao e objeto`);
    return false;
  }
  for (const k of esperadas) if (!Object.hasOwn(obj, k)) erros.push(`${caminho}.${k}: ausente`);
  for (const k of Object.keys(obj)) if (!esperadas.includes(k)) erros.push(`${caminho}.${k}: chave nao prevista`);
  return true;
}

const ehNumeroEm = (x, min, max) => typeof x === 'number' && Number.isFinite(x) && x >= min && x <= max;
const ehInteiroEm = (x, min, max) => ehNumeroEm(x, min, max) && Number.isInteger(x);
const ehTexto = (x, max) => typeof x === 'string' && x.length >= 1 && x.length <= max;

function validarLimiar(l, caminho, erros) {
  if (!exato(l, ['acima_de', 'piso'], caminho, erros)) return;
  if (!ehInteiroEm(l.acima_de, 1, Number.MAX_SAFE_INTEGER)) erros.push(`${caminho}.acima_de: inteiro >= 1`);
  if (tierIdx(l.piso) < 0) erros.push(`${caminho}.piso: nivel invalido`);
}

export function validatePolicy(policy, opts) {
  const erros = [];
  if (!exato(policy, CAMPOS_OBRIGATORIOS, 'politica', erros)) return { ok: false, erros };

  if (policy.schema_version !== 1) erros.push('schema_version: deve ser 1');
  if (!ehTexto(policy.version, 64)) erros.push('version: texto de 1 a 64');
  if (!MODES.includes(policy.mode)) erros.push('mode: off|shadow|enforce');
  if (typeof policy.valid_until !== 'string' || !INSTANTE_RE.test(policy.valid_until)
    || Number.isNaN(Date.parse(policy.valid_until))) erros.push('valid_until: instante UTC AAAA-MM-DDTHH:MM:SSZ');

  const allow = policy.model_allowlist;
  if (!Array.isArray(allow) || allow.length === 0) {
    erros.push('model_allowlist: lista nao vazia');
  } else {
    for (const m of allow) {
      if (typeof m !== 'string' || !ALIAS_RE.test(m) || FABLE_RE.test(m)) erros.push('model_allowlist: alias invalido ou fable');
    }
  }
  const allowOk = Array.isArray(allow) ? allow : [];

  if (exato(policy.tiers, TIER_NAMES, 'tiers', erros)) {
    for (const t of TIER_NAMES) {
      const x = policy.tiers[t];
      if (!exato(x, ['model', 'effort'], `tiers.${t}`, erros)) continue;
      if (typeof x.model !== 'string' || !allowOk.includes(x.model) || FABLE_RE.test(x.model)) {
        erros.push(`tiers.${t}.model: fora da allowlist ou fable`);
      }
      if (!EFFORTS.includes(x.effort)) erros.push(`tiers.${t}.effort: invalido`);
    }
  }

  if (exato(policy.ficha_tiers, ['complexidade', 'risco'], 'ficha_tiers', erros)) {
    const { complexidade, risco } = policy.ficha_tiers;
    if (exato(complexidade, COMPLEXIDADES, 'ficha_tiers.complexidade', erros)) {
      for (const k of COMPLEXIDADES) if (tierIdx(complexidade[k]) < 0) erros.push(`ficha_tiers.complexidade.${k}: nivel invalido`);
    }
    if (exato(risco, RISCOS, 'ficha_tiers.risco', erros)) {
      for (const k of RISCOS) if (tierIdx(risco[k]) < 0) erros.push(`ficha_tiers.risco.${k}: nivel invalido`);
    }
  }

  if (!isObj(policy.role_floors)) {
    erros.push('role_floors: nao e objeto');
  } else {
    for (const [k, v] of Object.entries(policy.role_floors)) {
      if (!ehTexto(k, 64) || tierIdx(v) < 0) erros.push(`role_floors.${k}: nivel invalido`);
    }
  }
  if (!Array.isArray(policy.reviewer_roles) || !policy.reviewer_roles.every((r) => ehTexto(r, 64))) {
    erros.push('reviewer_roles: lista de textos');
  }

  if (exato(policy.risk_surface, ['piso', 'words'], 'risk_surface', erros)) {
    if (tierIdx(policy.risk_surface.piso) < 0) erros.push('risk_surface.piso: nivel invalido');
    const w = policy.risk_surface.words;
    if (!Array.isArray(w) || w.length === 0 || !w.every((x) => ehTexto(x, 64) && tokens(x).length > 0)) {
      erros.push('risk_surface.words: lista nao vazia de palavras');
    }
  }

  if (exato(policy.size, ['prompt_chars', 'caminhos'], 'size', erros)) {
    validarLimiar(policy.size.prompt_chars, 'size.prompt_chars', erros);
    validarLimiar(policy.size.caminhos, 'size.caminhos', erros);
  }

  if (exato(policy.pace, ['abaixo_de', 'acima_de'], 'pace', erros)) {
    const { abaixo_de: a, acima_de: b } = policy.pace;
    if (!ehNumeroEm(a, -1000, 1000) || !ehNumeroEm(b, -1000, 1000) || !(a < b)) erros.push('pace: abaixo_de < acima_de, numeros finitos');
  }

  if (exato(policy.escalation, ['max_por_fluxo'], 'escalation', erros)) {
    if (!ehInteiroEm(policy.escalation.max_por_fluxo, 0, 1000)) erros.push('escalation.max_por_fluxo: inteiro 0..1000');
  }

  if (exato(policy.quality, ['piso_aprovacao', 'por_nivel'], 'quality', erros)) {
    const { piso_aprovacao: piso, por_nivel: porNivel } = policy.quality;
    if (exato(piso, ['default', 'por_papel'], 'quality.piso_aprovacao', erros)) {
      if (!ehNumeroEm(piso.default, 0, 1)) erros.push('quality.piso_aprovacao.default: numero 0..1');
      if (!isObj(piso.por_papel) || !Object.values(piso.por_papel).every((x) => ehNumeroEm(x, 0, 1))) {
        erros.push('quality.piso_aprovacao.por_papel: objeto de numeros 0..1');
      }
    }
    if (exato(porNivel, TIER_NAMES, 'quality.por_nivel', erros)) {
      for (const t of TIER_NAMES) {
        const q = porNivel[t];
        const c = `quality.por_nivel.${t}`;
        if (!exato(q, ['aprovacao_medida', 'n', 'fonte'], c, erros)) continue;
        const semAprov = q.aprovacao_medida === null;
        if (!semAprov && !ehNumeroEm(q.aprovacao_medida, 0, 1)) erros.push(`${c}.aprovacao_medida: null ou numero 0..1`);
        if (q.n !== null && !ehInteiroEm(q.n, 1, Number.MAX_SAFE_INTEGER)) erros.push(`${c}.n: null ou inteiro >= 1`);
        if (semAprov !== (q.n === null)) erros.push(`${c}: aprovacao_medida e n sao ambos null ou ambos preenchidos`);
        if (!ehTexto(q.fonte, 400)) erros.push(`${c}.fonte: texto de 1 a 400`);
      }
    }
  }

  if (erros.length > 0) return { ok: false, erros };
  return situacaoDeValidade(policy.valid_until, opts?.now) ? { ok: true, degradaPara: 'shadow' } : { ok: true };
}

// ---------------------------------------------------------------- decisao

function semDecisao() {
  return { tier: null, model: null, effort: null, floor: null, reasons: ['politica_invalida'], capped: false, mode: 'off', aplicar: false };
}

function exigenciaDeAprovacao(policy, nomes) {
  const { default: padrao, por_papel: porPapel } = policy.quality.piso_aprovacao;
  let exigida = padrao;
  for (const n of nomes) if (own(porPapel, n)) exigida = Math.max(exigida, porPapel[n]);
  return exigida;
}

function causaDeInelegibilidade(policy, nomes, idx) {
  const q = policy.quality.por_nivel[TIER_NAMES[idx]];
  if (q.aprovacao_medida === null) return 'nivel_nao_medido';
  return q.aprovacao_medida >= exigenciaDeAprovacao(policy, nomes) ? null : 'abaixo_do_piso_de_qualidade';
}

export function decide(input, policy) {
  const inp = isObj(input) ? input : {};
  const validade = validatePolicy(policy, { now: inp.now });
  if (!validade.ok) return semDecisao();

  const reasons = [];
  const add = (r) => { if (!reasons.includes(r)) reasons.push(r); };

  let mode = policy.mode;
  if (validade.degradaPara) {
    add(situacaoDeValidade(policy.valid_until, inp.now) === 'vencida' ? 'politica_vencida' : 'sem_relogio');
    if (mode !== 'off') mode = validade.degradaPara;
  }

  const rota = resolverFicha(inp);
  const ficha = rota.ok ? rota.ficha : null;
  if (!rota.ok) add(rota.motivo === 'ausente' ? 'sem_ficha' : 'ficha_invalida');
  const chave = ficha ? ficha.t : null;

  const role = typeof inp.role === 'string' ? inp.role : '';
  const sub = typeof inp.subagentType === 'string' ? inp.subagentType : '';
  const nomes = [role, sub];
  const texto = stripRota(typeof inp.prompt === 'string' ? inp.prompt : '');
  const hist = isObj(inp.history) ? inp.history : {};
  const falhasPorChave = isObj(hist.falhasPorChave) ? hist.falhasPorChave : {};
  const autorPorChave = isObj(hist.autorTierPorChave) ? hist.autorTierPorChave : {};

  // Piso: so sobe. Cada componente e um nivel e uma razao.
  let floor = 0;
  const subir = (idx, razao) => {
    if (idx > floor) floor = idx;
    if (idx >= 0) add(razao);
  };
  for (const n of nomes) if (own(policy.role_floors, n)) subir(tierIdx(policy.role_floors[n]), `piso_papel:${n}`);
  if (temSuperficieDeRisco(texto, policy.risk_surface.words)) subir(tierIdx(policy.risk_surface.piso), 'piso_superficie_de_risco');
  const { prompt_chars: tamanho, caminhos } = policy.size;
  if (texto.length > tamanho.acima_de) subir(tierIdx(tamanho.piso), 'piso_tamanho');
  if (contaCaminhos(texto, caminhos.acima_de) > caminhos.acima_de) subir(tierIdx(caminhos.piso), 'piso_caminhos');
  if (chave !== null && nomes.some((n) => policy.reviewer_roles.includes(n)) && own(autorPorChave, chave)) {
    const autor = tierIdx(autorPorChave[chave]);
    if (autor >= 0) subir(autor, 'revisor_nao_abaixo_do_autor');
  }

  const daFicha = ficha
    ? Math.max(tierIdx(policy.ficha_tiers.complexidade[String(ficha.c)]), tierIdx(policy.ficha_tiers.risco[ficha.r]))
    : 0;
  if (ficha && daFicha < floor) add('ficha_abaixo_do_piso');
  let tier = Math.max(daFicha, floor);

  // Tarefa repetida: uma subida por chave (sem laco) e no maximo max_por_fluxo chaves subidas.
  let capped = false;
  const falhas = chave !== null && own(falhasPorChave, chave) ? falhasPorChave[chave] : 0;
  const repetida = typeof falhas === 'number' && falhas >= 1;
  if (repetida) {
    const chavesEmFalha = Object.values(falhasPorChave).filter((n) => typeof n === 'number' && n >= 1).length;
    if (chavesEmFalha > policy.escalation.max_por_fluxo) {
      capped = true;
      add('teto_por_fluxo');
    } else {
      if (tier >= TOPO || falhas >= 2) capped = true;
      tier = Math.min(TOPO, tier + 1);
      floor = Math.min(TOPO, floor + 1);
      add('repeticao');
    }
  }

  // Ritmo: acima da margem desce um nivel onde v=sim, sem passar do piso, do nivel elegivel por
  // qualidade e sem descer tarefa que ja falhou; abaixo, sobe um nivel onde v=nao.
  const estado = isObj(inp.pace) && ESTADOS_RITMO.includes(inp.pace.estado) ? inp.pace.estado : 'dentro';
  if (estado === 'acima' && ficha && ficha.v === 'sim' && !repetida) {
    const alvo = tier - 1;
    if (alvo >= floor && alvo >= 0 && causaDeInelegibilidade(policy, nomes, alvo) === null) {
      tier = alvo;
      add('ritmo_desce');
    }
  } else if (estado === 'abaixo' && ficha && ficha.v === 'nao' && tier < TOPO) {
    tier += 1;
    add('ritmo_sobe');
  }

  // Qualidade: nivel nao medido, ou medido abaixo do piso de aprovacao, nao e elegivel; vale o de cima.
  for (let causa = causaDeInelegibilidade(policy, nomes, tier); causa !== null && tier < TOPO;
    causa = causaDeInelegibilidade(policy, nomes, tier)) {
    add(causa);
    tier += 1;
  }
  if (causaDeInelegibilidade(policy, nomes, tier) !== null) add('sem_nivel_elegivel');

  const cfg = policy.tiers[TIER_NAMES[tier]];
  return {
    tier: TIER_NAMES[tier],
    model: cfg.model,
    effort: cfg.effort,
    floor: TIER_NAMES[floor],
    reasons,
    capped,
    mode,
    aplicar: mode === 'enforce',
  };
}
