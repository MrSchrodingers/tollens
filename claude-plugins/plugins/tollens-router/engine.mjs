// Motor de decisao do roteador interno de modelos (R1). Modulo PURO: sem relogio, sem I/O, sem
// aleatoriedade e sem dependencia externa. O tempo (`input.now`, ms inteiros ou ISO estrito) e o
// ritmo (`input.pace`) entram como argumento. A ligacao ao Claude Code (hooks, ledger, sentinela de
// root) e a fatia R2. O contrato para o mod esta em CONTRATO.md.
//
//   decide(input, policy) -> { tier, model, effort, floor, tier_base, estado_nivel, reasons, capped,
//                              subida_concedida, mode, modo_efetivo, aplicar }
//   parseRota(prompt)     -> { ok:true, ficha } | { ok:false, motivo: 'ausente' | 'ficha_invalida' }
//   stripRota(prompt)     -> prompt sem a linha `@@ROTA` inicial e o seu terminador
//   validatePolicy(policy, { now }) -> { ok:true } | { ok:true, degradaPara:'shadow' } | { ok:false, erros }
//
// Invariantes: tier >= piso; o piso so sobe; o modelo vem sempre do conjunto {haiku, sonnet, opus}
// declarado na politica e nunca e fable; a ficha e o texto do prompt so podem ELEVAR o nivel;
// politica ou entrada que nao sejam dado puro => sem decisao; nada e aplicado fora de enforce nem
// com nivel emitivel sem medicao.

const TIER_NAMES = ['T0', 'T1', 'T2', 'T3', 'T4'];
const TOPO = TIER_NAMES.length - 1;
const ALIAS_PERMITIDOS = ['haiku', 'sonnet', 'opus']; // em ordem de custo crescente
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max']; // em ordem de custo crescente
const MODES = ['off', 'shadow', 'enforce'];
const RISCOS = ['trivial', 'normal', 'medio', 'alto'];
const VERIFICABILIDADES = ['sim', 'parcial', 'nao'];
const ESTADOS_RITMO = ['abaixo', 'dentro', 'acima'];
const COMPLEXIDADES = ['1', '2', '3', '4', '5'];
// Prefixos de risco que toda politica deve conter, e papeis que toda politica deve proteger.
const PREFIXOS_OBRIGATORIOS = ['deploy', 'migra', 'autentic', 'autoriz', 'auth', 'senha', 'password', 'token',
  'produc', 'pagament', 'segred', 'secret', 'credenc', 'irrevers', 'lgpd', 'pessoal'];
const PAPEIS_OBRIGATORIOS = [['refutador', 3], ['revisor-codigo', 2], ['auditor-seguranca', 3]];

export const CAMPOS_OBRIGATORIOS = [
  'schema_version', 'version', 'mode', 'valid_until', 'model_allowlist', 'tiers',
  'ficha_tiers', 'role_floors', 'reviewer_roles', 'risk_surface', 'size', 'pace',
  'escalation', 'quality',
];
export const CAMPOS_OPCIONAIS = ['limites'];

const MAX_LINHA_BYTES = 2048;
const MAX_TOKEN_CAMINHO = 512;
const MAX_PALAVRAS = 256;
const MAX_NOS = 100000;
const MAX_CHAVE = 256;
const MAX_HISTORY = 1000;
const MAX_CHAVES_POLITICA = 10000;
const MAX_PROFUNDIDADE = 16;
const PROMPT_MAX_PADRAO = 262144;
const PROMPT_MAX_TETO = 1048576;
const N_MINIMO_PADRAO = 8;
const AGORA_MIN = 1.6e12;
const AGORA_MAX = 4.1e12;
const HORIZONTE_MS = 400 * 86400000;
const VALID_UNTIL_TETO = Date.parse('2030-01-01T00:00:00Z'); // teto absoluto, vale sem relogio
const TERMINADOR_RE = /[\r\n\u2028\u2029\u0085]/;
const PREFIXO_ROTA = /^@@ROTA(?:[ \t]|$)/;
const CHAVE_RE = /^[A-Za-z0-9._:-]{1,64}$/;
const INSTANTE_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$/;
const CHARSET_CAMINHO_RE = /^[A-Za-z0-9_.~/-]+$/;
const EXTENSAO_RE = /\.[A-Za-z0-9]{1,8}$/;
const IGNORAVEL_RE = /[\p{Cf}\p{M}\p{Default_Ignorable_Code_Point}]+/gu;
// 28 pontos de codigo expandem mais de 4 no NFKC (U+FDFA expande 18x): 19 do BMP (ligaduras arabes e unidades
// katakana, sem letras latinas de palavra de risco), tratados aqui como separador, e 9 simbolos musicais
// astrais (U+1D160-1D164, U+1D1BD-1D1C0), NAO tratados. Medido: 256 KiB de simbolo musical custa cerca de
// 270 ms (6x o texto comum); sem o tratamento dos 19, U+FDFA custaria cerca de 2,6 s.
const EXPANSIVO_RE = /[\u3307\u3315\u3316\u3317\u3319\u331a\u3320\u332b\u332e\u3332\u3334\u3336\u3347\u334a\u3356\u33ae\u33af\ufdfa\ufdfb]/g;
const HOMOGLIFO_RE = /[\u0370-\u03ff\u0400-\u052f]/g;
const NAO_ALFANUM_RE = /[^\p{L}\p{N}]+/gu;
const NAO_ALFANUM_ASCII_RE = /[^a-z0-9]+/g;
const MARCAS_RE = /\p{M}+/gu;
const ASCII_RE = /^[\x00-\x7f]*$/;
const SEPARADOR_CAMINHO_RE = /[\s"'`()[\]<>,;]+/;

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

const dobrar = (texto) => texto.replace(HOMOGLIFO_RE, (c) => DOBRA.get(c) ?? c);

// Nome de papel: NFKC, sem caracteres de formato (zero-width, soft hyphen) e sem marcas combinantes,
// sem caixa, sem espacos extras e com homoglifos dobrados, como as palavras de risco. Um prefixo de
// namespace `plugin:nome` vale pelo ultimo segmento (so pode ELEVAR o piso).
const papel = (s) => {
  if (typeof s !== 'string' || s.length > 128) return '';
  const norm = dobrar(s.normalize('NFKC').replace(IGNORAVEL_RE, '').replace(/\s+/g, ' ').toLowerCase())
    .normalize('NFD').replace(MARCAS_RE, '');
  return norm.slice(norm.lastIndexOf(':') + 1).trim();
};

// Mapa de papeis normalizado UMA vez por objeto (as copias sao novas a cada decisao e nunca mudam);
// nomes que colidem depois de normalizados ficam com o maior valor.
const PAPEIS = new WeakMap();
function mapaDePapeis(mapa) {
  let m = PAPEIS.get(mapa);
  if (m === undefined) {
    m = new Map();
    const valor = (x) => (typeof x === 'number' ? x : tierIdx(x));
    for (const [k, v] of Object.entries(mapa)) {
      const n = papel(k);
      if (!m.has(n) || valor(v) > valor(m.get(n))) m.set(n, v);
    }
    PAPEIS.set(mapa, m);
  }
  return m;
}

function valorDoPapel(mapa, nome) {
  if (nome === '' || !isObj(mapa)) return undefined;
  return mapaDePapeis(mapa).get(nome);
}

// ---------------------------------------------------------------- dado puro

const IMPURO = Symbol('impuro');

// Copia estrutural para DADO PURO: null, booleano, numero, texto, lista e objeto simples (prototipo
// Object.prototype ou nulo). Recusa funcao, simbolo, bigint, getter ou setter, outro prototipo,
// ciclo e profundidade excessiva. Cada propriedade e lida UMA vez, pelo descritor, e tudo o que se
// valida depois e a copia: nao ha intervalo entre validar e usar. Um Proxy nao e detectavel, mas
// cai na mesma regra (so o descritor lido uma vez entra na copia). Dentro de `history` o excesso de
// entradas e cortado (marcado em ctx.truncado) em vez de recusado, mas a entrada da `chave` do
// chamador e buscada por acesso direto ANTES do corte e sempre mantida. Total de nos visitados
// limitado (um DAG compartilhado visitado como arvore cresce exponencialmente).
function copiar(v, profundidade, pilha, ctx, truncavel) {
  const t = typeof v;
  if (v === null || t === 'string' || t === 'number' || t === 'boolean' || t === 'undefined') return v;
  if (t !== 'object' || profundidade > MAX_PROFUNDIDADE || pilha.has(v) || ++ctx.nos > MAX_NOS) return IMPURO;
  const lista = Array.isArray(v);
  const proto = Object.getPrototypeOf(v);
  if (lista ? proto !== Array.prototype : proto !== Object.prototype && proto !== null) return IMPURO;
  let chaves = Object.keys(v);
  const teto = truncavel ? MAX_HISTORY : MAX_CHAVES_POLITICA;
  let extra = null;
  if (chaves.length > teto) {
    if (!truncavel) return IMPURO;
    ctx.truncado = true;
    if (lista) ctx.truncadoLista = true;
    if (ctx.chave !== undefined && lista && v.indexOf(ctx.chave) >= teto) extra = ctx.chave;
    if (ctx.chave !== undefined && !lista && Object.hasOwn(v, ctx.chave) && chaves.indexOf(ctx.chave) >= teto) extra = ctx.chave;
    chaves = chaves.slice(0, teto);
  }
  pilha.add(v);
  const saida = lista ? [] : {};
  if (lista) saida.length = Math.min(v.length, truncavel ? MAX_HISTORY : MAX_CHAVES_POLITICA);
  if (extra !== null) chaves.push(lista ? String(v.indexOf(extra)) : extra);
  for (const k of chaves) {
    if (truncavel && !lista && k.length > MAX_CHAVE) continue;
    const d = Object.getOwnPropertyDescriptor(v, k);
    if (d === undefined || !Object.hasOwn(d, 'value')) {
      pilha.delete(v);
      return IMPURO;
    }
    if (truncavel && lista && typeof d.value === 'string' && d.value.length > MAX_CHAVE) continue;
    const c = copiar(d.value, profundidade + 1, pilha, ctx, truncavel || (profundidade === 0 && k === 'history'));
    if (c === IMPURO) {
      pilha.delete(v);
      return IMPURO;
    }
    if (c !== undefined) Object.defineProperty(saida, k, { value: c, writable: true, enumerable: true, configurable: true });
  }
  pilha.delete(v);
  return saida;
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

// Texto de BUSCA do prompt inteiro (ate prompt_max_bytes), numa passada so e sem janelas: o resultado
// nao depende de onde o texto cai. NFKC (letras circuladas, largura total, ligaduras), sem ignoraveis
// (formato, marcas combinantes, Default_Ignorable como os preenchimentos de hangul), minuscula,
// homoglifos dobrados, sem acentos; tudo o que nao e letra ou digito vira um espaco, com um espaco
// no inicio e no fim. Texto so ASCII pula as etapas Unicode.
function paraBusca(texto) {
  if (ASCII_RE.test(texto)) return ` ${texto.toLowerCase().replace(NAO_ALFANUM_ASCII_RE, ' ')} `;
  let t = dobrar(texto.replace(IGNORAVEL_RE, '').replace(EXPANSIVO_RE, ' ').normalize('NFKC').toLowerCase()); // ignoraveis ANTES do NFKC: uma corrida longa de marcas tornaria a normalizacao quadratica
  if (!ASCII_RE.test(t)) t = t.normalize('NFD').replace(MARCAS_RE, '');
  return ` ${t.replace(NAO_ALFANUM_RE, ' ')} `;
}

const normalizarPalavra = (p) => paraBusca(p).trim();

// Palavras de risco da politica, normalizadas uma vez por decisao e reunidas numa regex so: prefixo
// de palavra em fronteira inicial, sem fronteira final (`-` e `_` separam palavras).
function prepararRisco(palavras) {
  const normais = [...new Set(palavras.map(normalizarPalavra))];
  return { normais, regex: new RegExp(` (?:${normais.join('|')})`) };
}

const temRisco = (texto, risco) => risco.regex.test(paraBusca(texto));

function pareceCaminho(tok) {
  if (!tok.includes('/') || !CHARSET_CAMINHO_RE.test(tok) || !/[A-Za-z0-9]/.test(tok)) return false;
  if (tok.startsWith('/') || tok.startsWith('~') || tok.startsWith('./') || tok.startsWith('../')) return true;
  if (EXTENSAO_RE.test(tok)) return true;
  return tok.split('/').length - 1 >= 2;
}

// Conta caminhos DISTINTOS e para ao passar do limiar.
function contaCaminhos(texto, limite) {
  const vistos = new Set();
  for (const tok of texto.split(SEPARADOR_CAMINHO_RE)) {
    if (tok.length < 3 || tok.length > MAX_TOKEN_CAMINHO || !pareceCaminho(tok)) continue;
    vistos.add(tok);
    if (vistos.size > limite) break;
  }
  return vistos.size;
}

// ---------------------------------------------------------------- relogio e politica

// ISO estrito (so para valid_until) com ida e volta: recusa dia inexistente (31 de fevereiro) e hora 24.
function instanteIso(texto) {
  if (typeof texto !== 'string' || !INSTANTE_RE.test(texto)) return NaN;
  const t = Date.parse(texto);
  if (Number.isNaN(t)) return NaN;
  return new Date(t).toISOString() === `${texto.slice(0, 19)}.000Z` ? t : NaN;
}

// `now` valido: ms inteiros em [1.6e12, 4.1e12]. Segundos, zero, negativo, texto (inclusive ISO) e
// Date nao valem.
const agoraMs = (now) => (Number.isInteger(now) && now >= AGORA_MIN && now <= AGORA_MAX ? now : NaN);

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
}

const limiteDe = (policy, nome, padrao) => (own(policy.limites, nome) ? policy.limites[nome] : padrao);
const emitivel = (policy, idx) => policy.tiers[TIER_NAMES[idx]].emitivel !== false;

// medido_ok: aprovacao >= piso do papel com n >= limites.n_minimo; reprovado: medida abaixo do piso
// (inelegivel); nao_medido: sem medicao ou com n insuficiente (desconhecido, nao colapsa).
function estadoDoNivel(policy, nomes, idx) {
  const q = policy.quality.por_nivel[TIER_NAMES[idx]];
  if (!(q.n >= limiteDe(policy, 'n_minimo', N_MINIMO_PADRAO))) return 'nao_medido'; // n nulo (sem medicao) tambem cai aqui
  return q.aprovacao_medida >= exigenciaDeAprovacao(policy, nomes) ? 'medido_ok' : 'reprovado';
}

// enforce so vale com todos os niveis EMITIVEIS medidos.
const algumEmitivelNaoMedido = (policy) => TIER_NAMES.some((t, i) => emitivel(policy, i) && estadoDoNivel(policy, [], i) === 'nao_medido');

function validarCopia(policy, opts) {
  const erros = [];
  if (!exato(policy, CAMPOS_OBRIGATORIOS, 'politica', erros, CAMPOS_OPCIONAIS)) return { ok: false, erros };

  if (policy.schema_version !== 1) erros.push('schema_version: deve ser 1');
  if (!ehTexto(policy.version, 64)) erros.push('version: texto de 1 a 64');
  if (!MODES.includes(policy.mode)) erros.push('mode: off|shadow|enforce');
  const validUntil = instanteIso(policy.valid_until);
  if (Number.isNaN(validUntil)) erros.push('valid_until: instante UTC AAAA-MM-DDTHH:MM:SSZ valido');
  const agora = agoraMs(opts?.now);
  if (validUntil - agora > HORIZONTE_MS) { // NaN em qualquer lado: comparacao falsa, sem horizonte a conferir
    erros.push('valid_until: alem de 400 dias a frente de now');
  }
  if (validUntil > VALID_UNTIL_TETO) erros.push('valid_until: alem do teto absoluto de 2030-01-01');

  const allow = policy.model_allowlist;
  if (!denso(allow) || allow.length === 0) {
    erros.push('model_allowlist: lista densa nao vazia');
  } else {
    for (const m of allow) if (!ALIAS_PERMITIDOS.includes(m)) erros.push('model_allowlist: alias fora de haiku, sonnet, opus');
  }
  const allowOk = denso(allow) ? allow : [];

  if (exato(policy.tiers, TIER_NAMES, 'tiers', erros)) {
    let anterior = -1;
    let algumEmitivel = false;
    for (const t of TIER_NAMES) {
      const x = policy.tiers[t];
      if (!exato(x, ['model', 'effort'], `tiers.${t}`, erros, ['emitivel'])) continue;
      const modelo = ALIAS_PERMITIDOS.indexOf(x.model);
      const esforco = EFFORTS.indexOf(x.effort);
      if (modelo < 0 || !allowOk.includes(x.model)) erros.push(`tiers.${t}.model: fora da allowlist ou de haiku, sonnet, opus`);
      if (esforco < 0) erros.push(`tiers.${t}.effort: invalido`);
      if (Object.hasOwn(x, 'emitivel') && typeof x.emitivel !== 'boolean') erros.push(`tiers.${t}.emitivel: booleano`);
      if (x.emitivel !== false) algumEmitivel = true;
      if (modelo >= 0 && esforco >= 0) {
        const custo = modelo * EFFORTS.length + esforco;
        if (custo <= anterior) erros.push(`tiers.${t}: custo nao estritamente crescente em relacao ao nivel anterior`);
        anterior = custo;
      }
    }
    if (!algumEmitivel) erros.push('tiers: nenhum nivel emitivel');
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
    for (const [nome, minimo] of PAPEIS_OBRIGATORIOS) {
      if (tierIdx(valorDoPapel(policy.role_floors, nome)) < minimo) erros.push(`role_floors.${nome}: obrigatorio com piso >= ${TIER_NAMES[minimo]}`);
    }
  }
  if (!denso(policy.reviewer_roles) || policy.reviewer_roles.length === 0 || !policy.reviewer_roles.every((r) => ehTexto(r, 64))) {
    erros.push('reviewer_roles: lista densa nao vazia de textos');
  } else {
    for (const r of policy.reviewer_roles) {
      const piso = valorDoPapel(policy.role_floors, papel(r));
      if (tierIdx(piso) < 2) erros.push(`role_floors.${r}: papel revisor sem piso em role_floors ou com piso abaixo de T2`);
    }
  }

  if (exato(policy.risk_surface, ['piso', 'words', 'nota'], 'risk_surface', erros)) {
    if (tierIdx(policy.risk_surface.piso) < 3) erros.push('risk_surface.piso: nivel T3 ou acima');
    const w = policy.risk_surface.words;
    if (!denso(w) || w.length === 0 || w.length > MAX_PALAVRAS || !w.every((x) => ehTexto(x, 64))) {
      erros.push('risk_surface.words: lista densa de 1 a 256 palavras');
    } else {
      const normais = new Set(w.map(normalizarPalavra));
      for (const n of normais) if (n.length < 3) erros.push('risk_surface.words: palavra que normaliza para menos de 3 caracteres');
      for (const p of PREFIXOS_OBRIGATORIOS) if (!normais.has(p)) erros.push(`risk_surface.words: prefixo obrigatorio ausente: ${p}`);
    }
    if (!ehTexto(policy.risk_surface.nota, 400)) erros.push('risk_surface.nota: texto de 1 a 400');
  }

  if (exato(policy.size, ['prompt_chars', 'caminhos', 'acima_do_teto'], 'size', erros)) {
    validarLimiar(policy.size.prompt_chars, 'size.prompt_chars', erros);
    validarLimiar(policy.size.caminhos, 'size.caminhos', erros);
    if (tierIdx(policy.size.caminhos?.piso) < 2) erros.push('size.caminhos.piso: T2 ou acima');
    if (tierIdx(policy.size.prompt_chars?.piso) < 2) erros.push('size.prompt_chars.piso: T2 ou acima');
    if (exato(policy.size.acima_do_teto, ['piso'], 'size.acima_do_teto', erros)
      && tierIdx(policy.size.acima_do_teto.piso) < Math.max(3, tierIdx(policy.risk_surface?.piso), tierIdx(policy.size.caminhos?.piso))) {
      erros.push('size.acima_do_teto.piso: T3 ou acima, e nunca abaixo do piso de risco nem de size.caminhos.piso (o texto depois do teto nao e varrido)');
    }
  }

  if (exato(policy.pace, ['abaixo_de', 'acima_de'], 'pace', erros)) {
    const { abaixo_de: a, acima_de: b } = policy.pace;
    if (!ehNumeroEm(a, -1000, 1000) || !ehNumeroEm(b, -1000, 1000) || !(a < b)) erros.push('pace: abaixo_de < acima_de, numeros finitos');
  }

  if (exato(policy.escalation, ['max_por_fluxo'], 'escalation', erros)) {
    if (!ehInteiroEm(policy.escalation.max_por_fluxo, 0, 1000)) erros.push('escalation.max_por_fluxo: inteiro 0..1000');
  }

  if (Object.hasOwn(policy, 'limites') && exato(policy.limites, [], 'limites', erros, ['prompt_max_bytes', 'n_minimo'])) {
    const { prompt_max_bytes: teto, n_minimo: nMin } = policy.limites;
    if (teto !== undefined && !ehInteiroEm(teto, 1024, PROMPT_MAX_TETO)) erros.push('limites.prompt_max_bytes: inteiro 1024..1048576');
    if (nMin !== undefined && !ehInteiroEm(nMin, 1, 1000)) erros.push('limites.n_minimo: inteiro 1..1000');
  }

  if (exato(policy.quality, ['piso_aprovacao', 'por_nivel'], 'quality', erros)) {
    const { piso_aprovacao: piso, por_nivel: porNivel } = policy.quality;
    if (exato(piso, ['default', 'por_papel'], 'quality.piso_aprovacao', erros)) {
      if (!ehNumeroEm(piso.default, 0.5, 1)) erros.push('quality.piso_aprovacao.default: numero 0.5..1');
      if (!isObj(piso.por_papel) || !Object.values(piso.por_papel).every((x) => ehNumeroEm(x, ehNumeroEm(piso.default, 0.5, 1) ? piso.default : 0.5, 1))) {
        erros.push('quality.piso_aprovacao.por_papel: objeto de numeros entre o default e 1');
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
    || (policy.mode === 'enforce' && algumEmitivelNaoMedido(policy));
  return degrada ? { ok: true, degradaPara: 'shadow' } : { ok: true };
}

export function validatePolicy(policy, opts) {
  let copia;
  try {
    copia = copiar(policy, 0, new Set(), { truncado: false, nos: 0 }, false);
  } catch {
    return { ok: false, erros: ['politica: leitura falhou (Proxy que lanca ou revogado)'] };
  }
  // IMPURO (simbolo) nao e objeto: validarCopia o recusa.
  return validarCopia(copia, opts);
}

// ---------------------------------------------------------------- decisao

function semDecisao(motivo) {
  return {
    tier: null, model: null, effort: null, floor: null, tier_base: null, estado_nivel: null,
    reasons: [motivo], capped: false, subida_concedida: false, mode: 'off', modo_efetivo: 'off', aplicar: false,
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

const listaDeTextos = (x) => (Array.isArray(x) ? x.filter((k) => typeof k === 'string') : []);

// Subida por falha. Teto de NOVAS concessoes por fluxo: `escalation.max_por_fluxo` menos as chaves de
// as registradas em `history.subidasConcedidas` (que o mod persiste) sem 2 ou mais falhas. Uma chave que ja subiu continua subida (nunca
// revogada); uma chave com 2 ou mais falhas sobe uma vez sem consumir o teto (sem laco). Entre as
// novas (1 falha), a ordem e a temporal (`history.ordem`), depois chave critica (nome com palavra de
// risco ou listada em `history.chavesCriticas`), depois o nome. Historico truncado: sem nova concessao.
// Chave registrada em `subidasConcedidas` sobe sempre (com ou sem falha no historico) e nunca desce.
// O motor e funcao pura de um historico CONSISTENTE: o mod DEVE persistir `subidasConcedidas` antes
// de aplicar a decisao; com persistencia atrasada a concessao pode ser revogada (ver CONTRATO).
function concedeSubida(h, chave, falhas, max, criticaDe) {
  if (h.concedidas.has(chave) || falhas >= 2) return true;
  if (h.truncado) return false;
  const novas = [];
  for (const [k, n] of Object.entries(h.falhasPorChave)) {
    if (typeof n === 'number' && n >= 1 && n < 2 && !h.concedidas.has(k)) novas.push(k);
  }
  const posicao = (k) => (h.ordem.has(k) ? h.ordem.get(k) : Infinity);
  const antes = (a, b) => {
    if (posicao(a) !== posicao(b)) return posicao(a) < posicao(b);
    if (criticaDe(a) !== criticaDe(b)) return criticaDe(a);
    return a < b;
  };
  // Consumo do teto: registradas sem 2 ou mais falhas (as com 2 ou mais nunca consomem vaga).
  let consumo = 0;
  for (const k of h.concedidas) if (!(typeof h.falhasPorChave[k] === 'number' && h.falhasPorChave[k] >= 2)) consumo++;
  const vagas = max - consumo;
  let anteriores = 0;
  for (const k of novas) {
    if (k !== chave && antes(k, chave)) anteriores++;
    if (anteriores >= vagas) return false; // novas inclui `chave`: o laco sempre confere o limite
  }
  return true;
}

export function decide(input, policy) {
  let policyCopia;
  try {
    policyCopia = copiar(policy, 0, new Set(), { truncado: false, nos: 0 }, false); // IMPURO nao passa em validarCopia
  } catch {
    return semDecisao('politica_invalida'); // Proxy que lanca ou revogado
  }
  const ctx = { truncado: false, nos: 0, chave: undefined };
  let inp;
  try {
    if (isObj(input)) {
      const d = Object.getOwnPropertyDescriptor(input, 'chave');
      if (d !== undefined && typeof d.value === 'string' && d.value.length >= 1 && d.value.length <= MAX_CHAVE) ctx.chave = d.value;
      inp = copiar(input, 0, new Set(), ctx, false);
    } else {
      inp = {};
    }
  } catch {
    return semDecisao('entrada_invalida');
  }
  if (inp === IMPURO) return semDecisao('entrada_invalida');
  const validade = validarCopia(policyCopia, { now: inp.now });
  if (!validade.ok) return semDecisao('politica_invalida');

  const reasons = [];
  const add = (r) => { if (!reasons.includes(r)) reasons.push(r); };

  let mode = policyCopia.mode;
  if (validade.degradaPara) {
    const situacao = situacaoDeValidade(policyCopia.valid_until, inp.now);
    if (situacao === 'vencida') add('politica_vencida');
    if (situacao === 'sem_relogio_valido') add('sem_relogio_valido');
    if (policyCopia.mode === 'enforce' && algumEmitivelNaoMedido(policyCopia)) add('nivel_nao_medido');
    if (mode !== 'off') mode = validade.degradaPara;
  }

  const rota = resolverFicha(inp);
  const ficha = rota.ok ? rota.ficha : null;
  if (!rota.ok) add(rota.motivo === 'ausente' ? 'sem_ficha' : 'ficha_invalida');
  const chave = typeof inp.chave === 'string' && inp.chave.length >= 1 && inp.chave.length <= MAX_CHAVE ? inp.chave : null;
  if (chave === null) add('sem_chave');
  if (ctx.truncado) add('history_truncado');
  if (ctx.truncadoLista) add('history_truncado_lista');

  const nomes = [papel(inp.role), papel(inp.subagentType)];
  const revisores = new Set(policyCopia.reviewer_roles.map(papel));
  const bruto = typeof inp.prompt === 'string' ? inp.prompt : '';
  const texto = stripRota(bruto);
  const teto = limiteDe(policyCopia, 'prompt_max_bytes', PROMPT_MAX_PADRAO);
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
    const v = valorDoPapel(policyCopia.role_floors, n);
    if (v !== undefined) subir(tierIdx(v), `piso_papel:${n}`);
  }
  const { prompt_chars: tamanho, caminhos, acima_do_teto: acimaDoTeto } = policyCopia.size;
  if (texto.length > tamanho.acima_de) subir(tierIdx(tamanho.piso), 'piso_tamanho');
  if (texto.length > teto) {
    add('prompt_acima_do_teto');
    subir(tierIdx(acimaDoTeto.piso), 'piso_tamanho_acima_do_teto');
  }
  if (nomes.some((n) => revisores.has(n))) {
    // Autor da MESMA chave, quando conhecido; senao o maior autor do fluxo.
    let autor = chave !== null && own(autorPorChave, chave) ? tierIdx(autorPorChave[chave]) : -1;
    if (autor < 0 && own(hist, 'autorTierMax')) autor = tierIdx(hist.autorTierMax);
    if (autor >= 0) subir(autor, 'revisor_nao_abaixo_do_autor');
  }
  // O texto so e varrido para o que ainda pode elevar o piso (e ate o teto de prompt_max_bytes).
  const pisoRisco = tierIdx(policyCopia.risk_surface.piso);
  const pisoCaminhos = tierIdx(caminhos.piso);
  const queRisco = pisoRisco > floor;
  const quePaths = pisoCaminhos > floor;
  const risco = prepararRisco(policyCopia.risk_surface.words);
  if (queRisco || quePaths) {
    const analise = texto.length > teto ? texto.slice(0, teto) : texto;
    if (queRisco && temRisco(analise, risco)) subir(pisoRisco, 'piso_superficie_de_risco');
    if (quePaths && contaCaminhos(analise, caminhos.acima_de) > caminhos.acima_de) subir(pisoCaminhos, 'piso_caminhos');
  }

  const daFicha = ficha
    ? Math.max(tierIdx(policyCopia.ficha_tiers.complexidade[String(ficha.c)]), tierIdx(policyCopia.ficha_tiers.risco[ficha.r]))
    : 0;
  if (ficha && daFicha < floor) add('ficha_abaixo_do_piso');
  let tier = Math.max(daFicha, floor);

  // Tarefa repetida: uma subida por chave (sem laco); o teto por fluxo so impede subidas novas.
  let capped = false;
  let subidaConcedida = false;
  const falhas = chave !== null && own(falhasPorChave, chave) ? falhasPorChave[chave] : 0;
  const concedidas = new Set(listaDeTextos(hist.subidasConcedidas));
  // D2: chave registrada em subidasConcedidas sobe sempre, com ou sem falha no historico.
  const repetida = (chave !== null && concedidas.has(chave)) || (typeof falhas === 'number' && falhas >= 1);
  if (repetida) {
    const historico = {
      falhasPorChave,
      concedidas,
      ordem: new Map(listaDeTextos(hist.ordem).map((k, i) => [k, i]).reverse()),
      truncado: ctx.truncado,
    };
    const criticas = new Set(listaDeTextos(hist.chavesCriticas));
    const criticaDe = (k) => criticas.has(k) || temRisco(k, risco);
    if (concedeSubida(historico, chave, falhas, policyCopia.escalation.max_por_fluxo, criticaDe)) {
      if (tier >= TOPO || falhas >= 2) capped = true;
      tier = Math.min(TOPO, tier + 1);
      floor = Math.min(TOPO, floor + 1);
      subidaConcedida = true;
      add('repeticao');
    } else {
      capped = true;
      if (!ctx.truncado) add('teto_por_fluxo'); // historico cortado nega a concessao com os codigos history_truncado*
    }
  }
  const tierBase = tier;

  // Ritmo: acima da margem desce um nivel onde v=sim, sem passar do piso, so para nivel emitivel
  // medido e aprovado e sem descer tarefa que ja falhou; abaixo, sobe um nivel onde v=nao.
  const estado = isObj(inp.pace) && ESTADOS_RITMO.includes(inp.pace.estado) ? inp.pace.estado : 'dentro';
  if (estado === 'acima' && ficha && ficha.v === 'sim' && !repetida) {
    const alvo = tier - 1;
    if (alvo >= floor && emitivel(policyCopia, alvo) && estadoDoNivel(policyCopia, nomes, alvo) === 'medido_ok') {
      tier = alvo;
      add('ritmo_desce');
    }
  } else if (estado === 'abaixo' && ficha && ficha.v === 'nao' && tier < TOPO) {
    tier += 1;
    add('ritmo_sobe');
  }

  // Qualidade: nivel nao emitivel ou reprovado e inelegivel, sobe ate o primeiro que nao seja.
  // Nivel nao medido fica como esta (sem colapsar para o de cima). Sem nenhum elegivel, devolve o
  // nivel base e nada e aplicado.
  while (tier <= TOPO && (!emitivel(policyCopia, tier) || estadoDoNivel(policyCopia, nomes, tier) === 'reprovado')) {
    if (emitivel(policyCopia, tier)) add('abaixo_do_piso_de_qualidade');
    tier += 1;
  }
  const semElegivel = tier > TOPO;
  if (semElegivel) {
    add('sem_nivel_elegivel');
    tier = tierBase;
  }
  const estadoNivel = estadoDoNivel(policyCopia, nomes, tier);
  if (estadoNivel === 'nao_medido') add('nivel_nao_medido');

  const modoEfetivo = mode === 'enforce' && semElegivel ? 'shadow' : mode;
  const cfg = policyCopia.tiers[TIER_NAMES[tier]];
  return {
    tier: TIER_NAMES[tier],
    model: cfg.model,
    effort: cfg.effort,
    floor: TIER_NAMES[floor],
    tier_base: TIER_NAMES[tierBase],
    estado_nivel: estadoNivel,
    reasons,
    capped,
    subida_concedida: subidaConcedida,
    mode,
    modo_efetivo: modoEfetivo,
    aplicar: modoEfetivo === 'enforce',
  };
}
