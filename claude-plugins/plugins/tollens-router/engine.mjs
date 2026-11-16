// Motor de decisao do roteador interno de modelos (R1). Modulo PURO: sem relogio, sem I/O, sem
// aleatoriedade e sem dependencia externa. O tempo (`input.now`, ms inteiros ou ISO estrito) e o
// ritmo (`input.pace`) entram como argumento. A ligacao ao Claude Code (hooks, ledger, sentinela de
// root) e a fatia R2. O contrato para o mod esta em CONTRATO.md.
//
//   decide(input, policy) -> { tier, model, effort, floor, tier_base, estado_nivel, reasons, capped,
//                              mode, modo_efetivo, aplicar }
//   parseRota(prompt)     -> { ok:true, ficha } | { ok:false, motivo: 'ausente' | 'ficha_invalida' }
//   stripRota(prompt)     -> prompt sem a linha `@@ROTA` inicial e o seu terminador
//   validatePolicy(policy, { now }) -> { ok:true } | { ok:true, degradaPara:'shadow' } | { ok:false, erros }
//
// Invariantes: tier >= piso; o piso so sobe; o modelo vem sempre do conjunto {haiku, sonnet, opus}
// declarado na politica e nunca e fable; a ficha e o texto do prompt so podem ELEVAR o nivel;
// politica invalida => modo off; nada e aplicado fora de enforce nem com nivel sem medicao.

const TIER_NAMES = ['T0', 'T1', 'T2', 'T3', 'T4'];
const TOPO = TIER_NAMES.length - 1;
const ALIAS_PERMITIDOS = ['haiku', 'sonnet', 'opus']; // em ordem de custo crescente
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']; // em ordem de custo crescente
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
export const CAMPOS_OPCIONAIS = ['limites'];

const MAX_LINHA_BYTES = 2048;
const MAX_TOKEN_CAMINHO = 512;
const MAX_TOKEN_TEXTO = 64;
const MAX_PALAVRAS = 256;
const MAX_CHAVE = 256;
const PROMPT_MAX_PADRAO = 65536;
const AGORA_MIN = 1.6e12;
const AGORA_MAX = 4.1e12;
const HORIZONTE_MS = 400 * 86400000;
const TERMINADOR_RE = /[\r\n\u2028\u2029\u0085]/;
const PREFIXO_ROTA = /^@@ROTA(?:[ \t]|$)/;
const CHAVE_RE = /^[A-Za-z0-9._:-]{1,64}$/;
const INSTANTE_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const AGORA_ISO_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.(\d{1,3}))?Z$/;
const CHARSET_CAMINHO_RE = /^[A-Za-z0-9_.~/-]+$/;
const EXTENSAO_RE = /\.[A-Za-z0-9]{1,8}$/;
const TRECHO_RE = /[\p{L}\p{N}\p{M}\p{Cf}]+/gu;
const FORMATO_E_MARCAS_RE = /[\p{Cf}\p{M}]+/gu;
const MARCAS_RE = /\p{M}+/gu;
const TEM_LETRA_OU_DIGITO_RE = /[\p{L}\p{N}]/u;

// Homoglifos cirilicos e gregos comuns, ja em minuscula, dobrados para latino. Fora deste mapa
// nao ha cobertura.
const DOBRA = new Map(Object.entries({
  '\u0430': 'a', '\u0432': 'b', '\u0435': 'e', '\u043a': 'k', '\u043c': 'm', '\u043d': 'h', '\u043e': 'o', '\u0440': 'p',
  '\u0441': 'c', '\u0442': 't', '\u0443': 'y', '\u0445': 'x', '\u0455': 's', '\u0456': 'i', '\u0458': 'j', '\u0475': 'v',
  '\u04bb': 'h', '\u0501': 'd', '\u051b': 'q', '\u051d': 'w',
  '\u03b1': 'a', '\u03b2': 'b', '\u03b5': 'e', '\u03b7': 'n', '\u03b9': 'i', '\u03ba': 'k', '\u03bd': 'v', '\u03bf': 'o',
  '\u03c1': 'p', '\u03c4': 't', '\u03c5': 'u', '\u03c7': 'x', '\u03c9': 'w',
}));

const isObj = (x) => x !== null && typeof x === 'object' && !Array.isArray(x);
const own = (o, k) => isObj(o) && Object.hasOwn(o, k);
const tierIdx = (t) => (typeof t === 'string' ? TIER_NAMES.indexOf(t) : -1);
const denso = (a) => Array.isArray(a) && Object.keys(a).length === a.length;
const papel = (s) => (typeof s === 'string' && s.length <= 128 ? s.trim().replace(/\s+/g, ' ').toLowerCase() : '');

function valorDoPapel(mapa, nome) {
  if (nome === '' || !isObj(mapa)) return undefined;
  for (const [k, v] of Object.entries(mapa)) if (papel(k) === nome) return v;
  return undefined;
}

// ---------------------------------------------------------------- ficha

// A primeira linha termina no primeiro de CR, LF, U+2028, U+2029, U+0085 ou no fim do texto;
// CRLF e um terminador so. `resto` e o indice onde o texto depois do terminador comeca.
function primeiraLinha(texto) {
  const m = TERMINADOR_RE.exec(texto);
  if (!m) return { linha: texto, resto: texto.length, terminado: false };
  const fim = m[0] === '\r' && texto[m.index + 1] === '\n' ? m.index + 2 : m.index + 1;
  return { linha: texto.slice(0, m.index), resto: fim, terminado: true };
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
  const { linha } = primeiraLinha(prompt);
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

// Remove SO a linha da ficha e o seu terminador; o resto passa byte a byte. Uma linha `@@ROTA` sem
// terminador que nao seja uma ficha valida e texto do usuario e fica.
export function stripRota(prompt) {
  if (typeof prompt !== 'string') return '';
  const { linha, resto, terminado } = primeiraLinha(prompt);
  if (!PREFIXO_ROTA.test(linha)) return prompt;
  if (!terminado && !parseRota(prompt).ok) return prompt;
  return prompt.slice(resto);
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

// Cada trecho de letras, digitos, marcas e caracteres de formato e limpo ANTES do corte de
// comprimento (zero-width e marcas nao empurram o texto util para fora), cortado em 64 e so entao
// normalizado: o custo de NFKC/NFD fica limitado por trecho.
function normalizarTrecho(bruto) {
  const limpo = bruto.replace(FORMATO_E_MARCAS_RE, '').slice(0, MAX_TOKEN_TEXTO);
  let saida = '';
  for (const ch of limpo.normalize('NFKC').toLowerCase()) saida += DOBRA.get(ch) ?? ch;
  return saida.normalize('NFD').replace(MARCAS_RE, '');
}

function tokens(texto) {
  const cache = new Map();
  const norm = (bruto) => {
    let n = cache.get(bruto);
    if (n === undefined) {
      n = normalizarTrecho(bruto);
      cache.set(bruto, n);
    }
    return n;
  };
  return Array.from(texto.matchAll(TRECHO_RE), (m) => norm(m[0])).filter((t) => t !== '');
}

function recortar(texto, limite) {
  if (texto.length <= limite) return texto;
  const metade = Math.floor(limite / 2);
  return `${texto.slice(0, metade)} ${texto.slice(-metade)}`;
}

// Prefixo de palavra em fronteira inicial; `-` e `_` separam palavras. Sem fronteira final.
function temSuperficieDeRisco(analise, palavras) {
  const alvo = ` ${tokens(analise).join(' ')} `;
  return palavras.some((p) => {
    const norm = tokens(p).join(' ');
    return norm !== '' && alvo.includes(` ${norm}`);
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

// ---------------------------------------------------------------- relogio e politica

// ISO estrito com ida e volta: recusa dia inexistente (31 de fevereiro) e hora 24.
function instanteIso(texto, re) {
  if (typeof texto !== 'string') return NaN;
  const m = re.exec(texto);
  if (!m) return NaN;
  const t = Date.parse(texto);
  if (Number.isNaN(t)) return NaN;
  const canonico = `${texto.slice(0, 19)}.${(m[1] ?? '').padEnd(3, '0')}Z`;
  return new Date(t).toISOString() === canonico ? t : NaN;
}

// `now` valido: ms inteiros ou ISO estrito, em [1.6e12, 4.1e12]. Segundos, zero, negativo, texto
// numerico e Date nao valem.
function agoraMs(now) {
  const ms = typeof now === 'number' ? now : instanteIso(now, AGORA_ISO_RE);
  return Number.isInteger(ms) && ms >= AGORA_MIN && ms <= AGORA_MAX ? ms : NaN;
}

// 'sem_relogio_valido' e 'vencida' degradam; politica vigente devolve null.
function situacaoDeValidade(validUntil, now) {
  const agora = agoraMs(now);
  if (Number.isNaN(agora)) return 'sem_relogio_valido';
  return agora >= Date.parse(validUntil) ? 'vencida' : null;
}

function exato(obj, esperadas, caminho, erros, opcionais = []) {
  if (!isObj(obj)) {
    erros.push(`${caminho}: nao e objeto`);
    return false;
  }
  for (const k of esperadas) if (!Object.hasOwn(obj, k)) erros.push(`${caminho}.${k}: ausente`);
  for (const k of Object.keys(obj)) if (!esperadas.includes(k) && !opcionais.includes(k)) erros.push(`${caminho}.${k}: chave nao prevista`);
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

const algumNivelNaoMedido = (policy) => TIER_NAMES.some((t) => policy.quality.por_nivel[t].aprovacao_medida === null);

export function validatePolicy(policy, opts) {
  const erros = [];
  if (!exato(policy, CAMPOS_OBRIGATORIOS, 'politica', erros, CAMPOS_OPCIONAIS)) return { ok: false, erros };

  if (policy.schema_version !== 1) erros.push('schema_version: deve ser 1');
  if (!ehTexto(policy.version, 64)) erros.push('version: texto de 1 a 64');
  if (!MODES.includes(policy.mode)) erros.push('mode: off|shadow|enforce');
  const validUntil = instanteIso(policy.valid_until, INSTANTE_RE);
  if (Number.isNaN(validUntil)) erros.push('valid_until: instante UTC AAAA-MM-DDTHH:MM:SSZ valido');
  const agora = agoraMs(opts?.now);
  if (validUntil - agora > HORIZONTE_MS) { // NaN em qualquer lado: comparacao falsa, sem horizonte a conferir
    erros.push('valid_until: alem de 400 dias a frente de now');
  }

  const allow = policy.model_allowlist;
  if (!denso(allow) || allow.length === 0) {
    erros.push('model_allowlist: lista densa nao vazia');
  } else {
    for (const m of allow) if (!ALIAS_PERMITIDOS.includes(m)) erros.push('model_allowlist: alias fora de haiku, sonnet, opus');
  }
  const allowOk = denso(allow) ? allow : [];

  if (exato(policy.tiers, TIER_NAMES, 'tiers', erros)) {
    let anterior = -1;
    for (const t of TIER_NAMES) {
      const x = policy.tiers[t];
      if (!exato(x, ['model', 'effort'], `tiers.${t}`, erros)) continue;
      const modelo = ALIAS_PERMITIDOS.indexOf(x.model);
      const esforco = EFFORTS.indexOf(x.effort);
      if (modelo < 0 || !allowOk.includes(x.model)) erros.push(`tiers.${t}.model: fora da allowlist ou de haiku, sonnet, opus`);
      if (esforco < 0) erros.push(`tiers.${t}.effort: invalido`);
      if (modelo >= 0 && esforco >= 0) {
        const custo = modelo * EFFORTS.length + esforco;
        if (custo < anterior) erros.push(`tiers.${t}: custo decrescente em relacao ao nivel anterior`);
        anterior = custo;
      }
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
  if (!denso(policy.reviewer_roles) || policy.reviewer_roles.length === 0 || !policy.reviewer_roles.every((r) => ehTexto(r, 64))) {
    erros.push('reviewer_roles: lista densa nao vazia de textos');
  } else {
    for (const r of policy.reviewer_roles) {
      const piso = valorDoPapel(policy.role_floors, papel(r));
      if (piso !== undefined && tierIdx(piso) < 2) erros.push(`role_floors.${r}: papel revisor com piso abaixo de T2`);
    }
  }

  if (exato(policy.risk_surface, ['piso', 'words', 'nota'], 'risk_surface', erros)) {
    if (tierIdx(policy.risk_surface.piso) < 0) erros.push('risk_surface.piso: nivel invalido');
    const w = policy.risk_surface.words;
    if (!denso(w) || w.length === 0 || w.length > MAX_PALAVRAS || !w.every((x) => ehTexto(x, 64) && TEM_LETRA_OU_DIGITO_RE.test(x))) {
      erros.push('risk_surface.words: lista densa de 1 a 256 palavras');
    }
    if (!ehTexto(policy.risk_surface.nota, 400)) erros.push('risk_surface.nota: texto de 1 a 400');
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

  if (Object.hasOwn(policy, 'limites') && exato(policy.limites, ['prompt_max_bytes'], 'limites', erros)) {
    if (!ehInteiroEm(policy.limites.prompt_max_bytes, 1024, 4194304)) erros.push('limites.prompt_max_bytes: inteiro 1024..4194304');
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
  const degrada = situacaoDeValidade(policy.valid_until, opts?.now) !== null
    || (policy.mode === 'enforce' && algumNivelNaoMedido(policy));
  return degrada ? { ok: true, degradaPara: 'shadow' } : { ok: true };
}

// ---------------------------------------------------------------- decisao

function semDecisao() {
  return {
    tier: null, model: null, effort: null, floor: null, tier_base: null, estado_nivel: null,
    reasons: ['politica_invalida'], capped: false, mode: 'off', modo_efetivo: 'off', aplicar: false,
  };
}

function exigenciaDeAprovacao(policy, nomes) {
  const { default: padrao, por_papel: porPapel } = policy.quality.piso_aprovacao;
  let exigida = padrao;
  for (const n of nomes) {
    const v = valorDoPapel(porPapel, n);
    if (typeof v === 'number') exigida = Math.max(exigida, v);
  }
  return exigida;
}

// medido_ok: aprovacao >= piso do papel; reprovado: medida abaixo do piso (inelegivel);
// nao_medido: null (desconhecido, nao colapsa para outro nivel).
function estadoDoNivel(policy, nomes, idx) {
  const q = policy.quality.por_nivel[TIER_NAMES[idx]];
  if (q.aprovacao_medida === null) return 'nao_medido';
  return q.aprovacao_medida >= exigenciaDeAprovacao(policy, nomes) ? 'medido_ok' : 'reprovado';
}

// Subida por falha: chave com 2 ou mais falhas ja subiu e continua subida (o teto nunca desfaz uma
// concessao). Chaves com exatamente 1 falha sao NOVAS subidas: cabem `max_por_fluxo` menos as ja
// concedidas, em ordem de nome (deterministico, sem memoria do engine).
function concedeSubida(falhasPorChave, chave, falhas, max) {
  if (falhas >= 2) return true;
  let concedidas = 0;
  let novasAntes = 0;
  for (const [k, n] of Object.entries(falhasPorChave)) {
    if (typeof n !== 'number') continue;
    if (n >= 2) concedidas++;
    else if (n >= 1 && k < chave) novasAntes++;
  }
  return novasAntes < max - concedidas;
}

export function decide(input, policy) {
  const inp = isObj(input) ? input : {};
  const validade = validatePolicy(policy, { now: inp.now });
  if (!validade.ok) return semDecisao();

  const reasons = [];
  const add = (r) => { if (!reasons.includes(r)) reasons.push(r); };

  let mode = policy.mode;
  if (validade.degradaPara) {
    const situacao = situacaoDeValidade(policy.valid_until, inp.now);
    if (situacao === 'vencida') add('politica_vencida');
    if (situacao === 'sem_relogio_valido') add('sem_relogio_valido');
    if (policy.mode === 'enforce' && algumNivelNaoMedido(policy)) add('nivel_nao_medido');
    if (mode !== 'off') mode = validade.degradaPara;
  }

  const rota = resolverFicha(inp);
  const ficha = rota.ok ? rota.ficha : null;
  if (!rota.ok) add(rota.motivo === 'ausente' ? 'sem_ficha' : 'ficha_invalida');
  const chave = typeof inp.chave === 'string' && inp.chave.length <= MAX_CHAVE ? inp.chave : null;

  const nomes = [papel(inp.role), papel(inp.subagentType)];
  const revisores = new Set(policy.reviewer_roles.map(papel));
  const texto = stripRota(typeof inp.prompt === 'string' ? inp.prompt : '');
  const limite = own(policy, 'limites') ? policy.limites.prompt_max_bytes : PROMPT_MAX_PADRAO;
  const analise = recortar(texto, limite);
  if (analise !== texto) add('prompt_truncado');
  const hist = isObj(inp.history) ? inp.history : {};
  const falhasPorChave = isObj(hist.falhasPorChave) ? hist.falhasPorChave : {};
  const autorPorChave = isObj(hist.autorTierPorChave) ? hist.autorTierPorChave : {};

  // Piso: so sobe. Cada componente e um nivel e uma razao.
  let floor = 0;
  const subir = (idx, razao) => {
    if (idx > floor) floor = idx;
    if (idx >= 0) add(razao);
  };
  for (const n of nomes) {
    const v = valorDoPapel(policy.role_floors, n);
    if (v !== undefined) subir(tierIdx(v), `piso_papel:${n}`);
  }
  if (temSuperficieDeRisco(analise, policy.risk_surface.words)) subir(tierIdx(policy.risk_surface.piso), 'piso_superficie_de_risco');
  const { prompt_chars: tamanho, caminhos } = policy.size;
  if (texto.length > tamanho.acima_de) subir(tierIdx(tamanho.piso), 'piso_tamanho');
  if (contaCaminhos(analise, caminhos.acima_de) > caminhos.acima_de) subir(tierIdx(caminhos.piso), 'piso_caminhos');
  if (nomes.some((n) => revisores.has(n))) {
    // Autor da MESMA chave, quando conhecido; senao o maior autor do fluxo.
    let autor = chave !== null && own(autorPorChave, chave) ? tierIdx(autorPorChave[chave]) : -1;
    if (autor < 0 && own(hist, 'autorTierMax')) autor = tierIdx(hist.autorTierMax);
    if (autor >= 0) subir(autor, 'revisor_nao_abaixo_do_autor');
  }

  const daFicha = ficha
    ? Math.max(tierIdx(policy.ficha_tiers.complexidade[String(ficha.c)]), tierIdx(policy.ficha_tiers.risco[ficha.r]))
    : 0;
  if (ficha && daFicha < floor) add('ficha_abaixo_do_piso');
  let tier = Math.max(daFicha, floor);

  // Tarefa repetida: uma subida por chave (sem laco); o teto por fluxo so impede subidas novas.
  let capped = false;
  const falhas = chave !== null && own(falhasPorChave, chave) ? falhasPorChave[chave] : 0;
  const repetida = typeof falhas === 'number' && falhas >= 1;
  if (repetida) {
    if (concedeSubida(falhasPorChave, chave, falhas, policy.escalation.max_por_fluxo)) {
      if (tier >= TOPO || falhas >= 2) capped = true;
      tier = Math.min(TOPO, tier + 1);
      floor = Math.min(TOPO, floor + 1);
      add('repeticao');
    } else {
      capped = true;
      add('teto_por_fluxo');
    }
  }
  const tierBase = tier;

  // Ritmo: acima da margem desce um nivel onde v=sim, sem passar do piso, so para nivel medido e
  // aprovado e sem descer tarefa que ja falhou; abaixo, sobe um nivel onde v=nao.
  const estado = isObj(inp.pace) && ESTADOS_RITMO.includes(inp.pace.estado) ? inp.pace.estado : 'dentro';
  if (estado === 'acima' && ficha && ficha.v === 'sim' && !repetida) {
    const alvo = tier - 1;
    if (alvo >= floor && estadoDoNivel(policy, nomes, alvo) === 'medido_ok') {
      tier = alvo;
      add('ritmo_desce');
    }
  } else if (estado === 'abaixo' && ficha && ficha.v === 'nao' && tier < TOPO) {
    tier += 1;
    add('ritmo_sobe');
  }

  // Qualidade: nivel reprovado e inelegivel, sobe ate o primeiro que nao seja reprovado. Nivel nao
  // medido fica como esta (sem colapsar para o de cima). Sem nenhum elegivel, devolve o nivel base
  // e nada e aplicado.
  while (tier <= TOPO && estadoDoNivel(policy, nomes, tier) === 'reprovado') {
    add('abaixo_do_piso_de_qualidade');
    tier += 1;
  }
  const semElegivel = tier > TOPO;
  if (semElegivel) {
    add('sem_nivel_elegivel');
    tier = tierBase;
  }
  const estadoNivel = estadoDoNivel(policy, nomes, tier);
  if (estadoNivel === 'nao_medido') add('nivel_nao_medido');

  const modoEfetivo = mode === 'enforce' && semElegivel ? 'shadow' : mode;
  const cfg = policy.tiers[TIER_NAMES[tier]];
  return {
    tier: TIER_NAMES[tier],
    model: cfg.model,
    effort: cfg.effort,
    floor: TIER_NAMES[floor],
    tier_base: TIER_NAMES[tierBase],
    estado_nivel: estadoNivel,
    reasons,
    capped,
    mode,
    modo_efetivo: modoEfetivo,
    aplicar: modoEfetivo === 'enforce',
  };
}
