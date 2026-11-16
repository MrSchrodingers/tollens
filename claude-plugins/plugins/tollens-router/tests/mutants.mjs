// Gerador e executor de MUTANTES do motor de decisao (engine.mjs).
// Cada mutante troca UM trecho exato do engine por outro, grava a copia mutada numa arvore
// temporaria (o arquivo de producao nunca e alterado) e roda tests/unit/router-engine.test.mjs
// contra ela. Mutante morto = a suite falhou (ou estourou o prazo). Mutante vivo = lacuna de teste,
// exceto os marcados `equivalente`, que carregam a justificativa de por que nenhuma entrada
// observavel os distingue do original.
//
// Controles do instrumento: (1) a suite passa na copia SEM mutacao; (2) cada trecho `de` ocorre
// exatamente uma vez no engine; sem isso o mutante e reportado como INSTRUMENTO e o exit e 1.
//
// Uso: node claude-plugins/plugins/tollens-router/tests/mutants.mjs [--lista]
// Exit: 0 se todo mutante nao equivalente morreu; 1 caso contrario.
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const RAIZ = path.resolve(AQUI, '../../../..');
const PLUGIN = path.join(RAIZ, 'claude-plugins/plugins/tollens-router');
const TESTE = path.join(RAIZ, 'tests/unit/router-engine.test.mjs');
const ENGINE = readFileSync(path.join(PLUGIN, 'engine.mjs'), 'utf8');

const EQ_PREFIXO = 'prototipo: tierIdx e typeof rejeitam o valor herdado; own() e defesa em profundidade';

// [id, de, para, equivalente?]
const M = [
  ['ficha-teto-2049', 'const MAX_LINHA_BYTES = 2048;', 'const MAX_LINHA_BYTES = 4096;'],
  ['ficha-teto-2047', 'const MAX_LINHA_BYTES = 2048;', 'const MAX_LINHA_BYTES = 2047;'],
  ['ficha-so-bytes', 'linha.length > MAX_LINHA_BYTES || new TextEncoder().encode(linha).length > MAX_LINHA_BYTES',
    'new TextEncoder().encode(linha).length > MAX_LINHA_BYTES', 'bytes >= caracteres: a segunda condicao implica a primeira'],
  ['ficha-so-chars', 'linha.length > MAX_LINHA_BYTES || new TextEncoder().encode(linha).length > MAX_LINHA_BYTES',
    'linha.length > MAX_LINHA_BYTES', 'linha multibyte acima de 2048 bytes tem t fora de CHAVE_RE e vira ficha_invalida do mesmo jeito'],
  ['prefixo-sem-fronteira', '/^@@ROTA(?:[ \\t]|$)/', '/^@@ROTA/'],
  ['prefixo-sem-ancora', '/^@@ROTA(?:[ \\t]|$)/', '/@@ROTA(?:[ \\t]|$)/'],
  ['linha-inteira', 'let linha = nl < 0 ? texto : texto.slice(0, nl);', 'let linha = texto;'],
  ['linha-sem-cr', "if (linha.endsWith('\\r')) linha = linha.slice(0, -1);", ''],
  ['ficha-4-campos', 'chaves.length !== 4', 'chaves.length !== 5'],
  ['ficha-nomes', "|| !['c', 'r', 'v', 't'].every((k) => chaves.includes(k))", '',
    'com 4 chaves e nome errado falta um de c,r,v,t: o campo ausente chega undefined e cai na checagem de tipo seguinte'],
  ['ficha-c-min', 'c < 1 || c > 5', 'c < 0 || c > 5'],
  ['ficha-c-max', 'c < 1 || c > 5', 'c < 1 || c > 6'],
  ['ficha-c-inteiro', '!Number.isInteger(c) || ', ''],
  ['ficha-c-tipo', "typeof c !== 'number' || ", '', 'Number.isInteger de nao numero e false: a checagem seguinte ja recusa'],
  ['ficha-r-enum', 'if (!RISCOS.includes(r) || !VERIFICABILIDADES.includes(v)) return invalida();',
    'if (!VERIFICABILIDADES.includes(v)) return invalida();'],
  ['ficha-v-enum', 'if (!RISCOS.includes(r) || !VERIFICABILIDADES.includes(v)) return invalida();',
    'if (!RISCOS.includes(r)) return invalida();'],
  ['ficha-chave-charset', '/^[A-Za-z0-9._:-]{1,64}$/', '/^[\\s\\S]{1,64}$/'],
  ['ficha-chave-tamanho', 'const CHAVE_RE = /^[A-Za-z0-9._:-]{1,64}$/;', 'const CHAVE_RE = /^[A-Za-z0-9._:-]{1,640}$/;'],
  ['strip-newline', "return nl < 0 ? '' : prompt.slice(nl + 1);", "return nl < 0 ? '' : prompt.slice(nl);"],
  ['resolver-ok-false-ausente', "return f.motivo === 'ausente' ? ausente() : invalida();", 'return ausente();'],
  ['resolver-ok-false-invalida', "return f.motivo === 'ausente' ? ausente() : invalida();", 'return invalida();'],
  ['resolver-ficha-crua', 'return validateFicha(f);', 'return invalida();'],
  ['resolver-sem-revalidar', 'if (f.ok) return validateFicha(f.ficha);', 'if (f.ok) return { ok: true, ficha: f.ficha };'],
  ['texto-sem-nfd', ".normalize('NFD').replace(/\\p{M}+/gu, '')", ''],
  ['texto-sem-marcas', ".replace(/\\p{M}+/gu, '')", ''],
  ['texto-sem-minuscula', '.toLowerCase()', ''],
  ['risco-substring', 'alvo.includes(` ${norm} `)', 'alvo.includes(norm)'],
  ['risco-palavra-vazia', "norm !== '' && ", '', 'validatePolicy ja recusa palavra que nao gera token'],
  ['caminho-sem-barra-inicial', "tok.startsWith('/') || ", ''],
  ['caminho-sem-til', "tok.startsWith('~') || ", ''],
  ['caminho-sem-extensao', 'if (EXTENSAO_RE.test(tok)) return true;', ''],
  ['caminho-duas-barras', 'tok.split(\'/\').length - 1 >= 2', 'tok.split(\'/\').length - 1 >= 3'],
  ['caminho-sem-teto-de-token', 'tok.length > MAX_TOKEN_CAMINHO || ', ''],
  ['caminho-sem-parada', 'if (vistos.size > limite) break;', '', 'so poda trabalho: a contagem acima do limiar ja decide'],
  ['caminho-nao-distintos', 'vistos.add(tok);', 'vistos.add(tok + vistos.size);'],
  ['piso-nao-sobe', 'if (idx > floor) floor = idx;', 'if (idx < floor) floor = idx;'],
  ['papel-so-role', 'const nomes = [role, sub];', 'const nomes = [role];'],
  ['papel-so-subagente', 'const nomes = [role, sub];', 'const nomes = [sub];'],
  ['revisor-sempre', 'nomes.some((n) => policy.reviewer_roles.includes(n))', 'true'],
  ['revisor-sem-own', 'own(autorPorChave, chave)', 'true', EQ_PREFIXO],
  ['tamanho-igual-vale', 'texto.length > tamanho.acima_de', 'texto.length >= tamanho.acima_de'],
  ['caminhos-igual-vale', 'contaCaminhos(texto, caminhos.acima_de) > caminhos.acima_de', 'contaCaminhos(texto, caminhos.acima_de) >= caminhos.acima_de'],
  ['ficha-so-complexidade',
    'Math.max(tierIdx(policy.ficha_tiers.complexidade[String(ficha.c)]), tierIdx(policy.ficha_tiers.risco[ficha.r]))',
    'tierIdx(policy.ficha_tiers.complexidade[String(ficha.c)])'],
  ['ficha-so-risco',
    'Math.max(tierIdx(policy.ficha_tiers.complexidade[String(ficha.c)]), tierIdx(policy.ficha_tiers.risco[ficha.r]))',
    'tierIdx(policy.ficha_tiers.risco[ficha.r])'],
  ['ficha-ignora-piso', 'let tier = Math.max(daFicha, floor);', 'let tier = daFicha;'],
  ['subclassificacao-muda', "if (ficha && daFicha < floor) add('ficha_abaixo_do_piso');", ''],
  ['repeticao-so-depois-de-2', "typeof falhas === 'number' && falhas >= 1;", "typeof falhas === 'number' && falhas > 1;"],
  ['repeticao-sem-own', 'chave !== null && own(falhasPorChave, chave) ? falhasPorChave[chave] : 0', 'chave !== null ? falhasPorChave[chave] : 0', EQ_PREFIXO],
  ['teto-fluxo-igual', 'chavesEmFalha > policy.escalation.max_por_fluxo', 'chavesEmFalha >= policy.escalation.max_por_fluxo'],
  ['teto-fluxo-ausente', 'chavesEmFalha > policy.escalation.max_por_fluxo', 'false'],
  ['capped-sem-repeticao-multipla', 'if (tier >= TOPO || falhas >= 2) capped = true;', 'if (tier >= TOPO) capped = true;'],
  ['capped-sem-topo', 'if (tier >= TOPO || falhas >= 2) capped = true;', 'if (falhas >= 2) capped = true;'],
  ['repeticao-sem-teto-topo', 'tier = Math.min(TOPO, tier + 1);', 'tier = tier + 1;'],
  ['repeticao-nao-sobe', 'tier = Math.min(TOPO, tier + 1);', 'tier = tier;'],
  ['repeticao-piso-fixo', 'floor = Math.min(TOPO, floor + 1);', 'floor = Math.min(TOPO, floor);'],
  ['ritmo-desce-sem-verificar-v', "ficha.v === 'sim' && !repetida", "ficha.v !== 'nao' && !repetida"],
  ['ritmo-desce-apos-falha', "ficha.v === 'sim' && !repetida", "ficha.v === 'sim'"],
  ['ritmo-desce-abaixo-do-piso', 'alvo >= floor && alvo >= 0 &&', 'alvo >= 0 &&'],
  ['ritmo-desce-limite-zero', 'alvo >= floor && alvo >= 0 &&', 'alvo >= floor &&', 'floor >= 0 sempre: alvo >= floor ja implica alvo >= 0'],
  ['ritmo-desce-sem-qualidade', ' && causaDeInelegibilidade(policy, nomes, alvo) === null', ''],
  ['ritmo-abaixo-desce-tambem', "if (estado === 'acima' && ficha && ficha.v === 'sim' && !repetida) {",
    "if (estado !== 'dentro' && ficha && ficha.v === 'sim' && !repetida) {"],
  ['ritmo-sobe-sem-verificar-v', "estado === 'abaixo' && ficha && ficha.v === 'nao' && tier < TOPO", "estado === 'abaixo' && ficha && ficha.v !== 'sim' && tier < TOPO"],
  ['ritmo-sobe-sem-teto', "estado === 'abaixo' && ficha && ficha.v === 'nao' && tier < TOPO", "estado === 'abaixo' && ficha && ficha.v === 'nao'"],
  ['ritmo-sobe-dois', "tier += 1;\n    add('ritmo_sobe');", "tier += 2;\n    add('ritmo_sobe');"],
  ['ritmo-estado-livre', 'isObj(inp.pace) && ESTADOS_RITMO.includes(inp.pace.estado) ? inp.pace.estado', 'isObj(inp.pace) ? inp.pace.estado',
    'estado fora do enum nao casa nenhum dos dois ramos: o resultado e igual ao de dentro'],
  ['qualidade-sem-teto', 'causa !== null && tier < TOPO;', 'causa !== null;'],
  ['qualidade-sobe-dois', 'add(causa);\n    tier += 1;', 'add(causa);\n    tier += 2;'],
  ['qualidade-sem-aviso-final', "if (causaDeInelegibilidade(policy, nomes, tier) !== null) add('sem_nivel_elegivel');", ''],
  ['qualidade-sem-piso-de-papel', 'exigida = Math.max(exigida, porPapel[n]);', 'exigida = exigida;'],
  ['qualidade-igual-nao-vale', 'return q.aprovacao_medida >= exigenciaDeAprovacao(policy, nomes)', 'return q.aprovacao_medida > exigenciaDeAprovacao(policy, nomes)'],
  ['qualidade-null-vale', "if (q.aprovacao_medida === null) return 'nivel_nao_medido';", ''],
  ['modo-vencida-promove-off', "if (mode !== 'off') mode = validade.degradaPara;", 'mode = validade.degradaPara;'],
  ['modo-aplicar-shadow', "aplicar: mode === 'enforce',", "aplicar: mode !== 'off',"],
  ['modo-invalida-nao-off', "mode: 'off', aplicar: false }", "mode: 'shadow', aplicar: false }"],
  ['validade-igual-vale', "return agora >= Date.parse(validUntil) ? 'vencida' : null;", "return agora > Date.parse(validUntil) ? 'vencida' : null;"],
  ['validade-sem-relogio-vale', "if (Number.isNaN(agora)) return 'sem_relogio';", ''],
  ['relogio-numero', "if (typeof now === 'number') return Number.isFinite(now) ? now : NaN;", ''],
  ['relogio-date', 'if (now instanceof Date) return now.getTime();', ''],
  ['entrada-nao-objeto', 'const inp = isObj(input) ? input : {};', 'const inp = input;'],
  ['texto-com-linha-rota', "const texto = stripRota(typeof inp.prompt === 'string' ? inp.prompt : '');", "const texto = typeof inp.prompt === 'string' ? inp.prompt : '';"],
  ['politica-invalida-segue', 'if (!validade.ok) return semDecisao();', ''],
  ['allowlist-aceita-fable', '|| FABLE_RE.test(m)', ''],
  ['tier-fora-da-allowlist', '!allowOk.includes(x.model) || ', ''],
  ['politica-schema-version', 'policy.schema_version !== 1', 'false'],
  ['politica-version', 'if (!ehTexto(policy.version, 64)) erros.push', 'if (false) erros.push'],
  ['politica-mode', 'if (!MODES.includes(policy.mode)) erros.push', 'if (false) erros.push'],
  ['politica-valid-until-impossivel', '    || Number.isNaN(Date.parse(policy.valid_until))) erros.push', '    ) erros.push'],
  ['politica-effort', 'if (!EFFORTS.includes(x.effort)) erros.push', 'if (false) erros.push'],
  ['politica-complexidade', 'if (tierIdx(complexidade[k]) < 0) erros.push', 'if (false) erros.push'],
  ['politica-risco', 'if (tierIdx(risco[k]) < 0) erros.push', 'if (false) erros.push'],
  ['politica-role-floors-nivel', 'if (!ehTexto(k, 64) || tierIdx(v) < 0) erros.push', 'if (!ehTexto(k, 64)) erros.push'],
  ['politica-role-floors-chave', 'if (!ehTexto(k, 64) || tierIdx(v) < 0) erros.push', 'if (tierIdx(v) < 0) erros.push'],
  ['politica-reviewer-itens', '|| !policy.reviewer_roles.every((r) => ehTexto(r, 64))', ''],
  ['politica-risk-piso', 'if (tierIdx(policy.risk_surface.piso) < 0) erros.push', 'if (false) erros.push'],
  ['politica-words-vazia', 'w.length === 0 || ', ''],
  ['politica-words-itens', '|| !w.every((x) => ehTexto(x, 64) && tokens(x).length > 0)', ''],
  ['politica-limiar-acima', 'if (!ehInteiroEm(l.acima_de, 1, Number.MAX_SAFE_INTEGER)) erros.push', 'if (false) erros.push'],
  ['politica-limiar-piso', 'if (tierIdx(l.piso) < 0) erros.push', 'if (false) erros.push'],
  ['politica-pace-ordem', '|| !(a < b)', ''],
  ['politica-pace-numeros', '!ehNumeroEm(a, -1000, 1000) || !ehNumeroEm(b, -1000, 1000) || ', ''],
  ['politica-escalation', 'if (!ehInteiroEm(policy.escalation.max_por_fluxo, 0, 1000)) erros.push', 'if (false) erros.push'],
  ['politica-piso-default', 'if (!ehNumeroEm(piso.default, 0, 1)) erros.push', 'if (false) erros.push'],
  ['politica-piso-por-papel', "if (!isObj(piso.por_papel) || !Object.values(piso.por_papel).every((x) => ehNumeroEm(x, 0, 1))) {", 'if (false) {'],
  ['politica-aprovacao', 'if (!semAprov && !ehNumeroEm(q.aprovacao_medida, 0, 1)) erros.push', 'if (false) erros.push'],
  ['politica-n', 'if (q.n !== null && !ehInteiroEm(q.n, 1, Number.MAX_SAFE_INTEGER)) erros.push', 'if (false) erros.push'],
  ['politica-n-consistente', 'if (semAprov !== (q.n === null)) erros.push', 'if (false) erros.push'],
  ['politica-fonte', 'if (!ehTexto(q.fonte, 400)) erros.push', 'if (false) erros.push'],
  ['politica-chave-extra', 'for (const k of Object.keys(obj)) if (!esperadas.includes(k)) erros.push', 'for (const k of Object.keys(obj)) if (false) erros.push'],
  ['politica-chave-faltando', 'for (const k of esperadas) if (!Object.hasOwn(obj, k)) erros.push', 'for (const k of esperadas) if (false) erros.push',
    'cada campo exigido tem validacao de tipo propria (inclusive null/undefined): a chave ausente falha nela, com outra mensagem'],
  ['politica-inteiro', 'ehNumeroEm(x, min, max) && Number.isInteger(x)', 'ehNumeroEm(x, min, max)'],
];

function copiaDe(trabalho, engineTexto) {
  const plug = path.join(trabalho, 'claude-plugins/plugins/tollens-router');
  mkdirSync(plug, { recursive: true });
  mkdirSync(path.join(trabalho, 'tests/unit'), { recursive: true });
  cpSync(path.join(PLUGIN, 'router-policy.json'), path.join(plug, 'router-policy.json'));
  cpSync(path.join(PLUGIN, 'policy.schema.json'), path.join(plug, 'policy.schema.json'));
  cpSync(TESTE, path.join(trabalho, 'tests/unit/router-engine.test.mjs'));
  writeFileSync(path.join(plug, 'engine.mjs'), engineTexto);
}

function roda(trabalho) {
  const r = spawnSync(process.execPath, ['--test', '--experimental-test-isolation=none', path.join(trabalho, 'tests/unit/router-engine.test.mjs')],
    { encoding: 'utf8', timeout: 90_000, killSignal: 'SIGKILL' });
  return { status: r.status, timeout: r.error?.code === 'ETIMEDOUT' || r.signal === 'SIGKILL' };
}

if (process.argv.includes('--lista')) {
  for (const [id] of M) console.log(id);
  process.exit(0);
}

const base = mkdtempSync(path.join(process.env.MUTANTS_TMPDIR || tmpdir(), 'router-mutantes-'));
let saida = 0;
try {
  const ctl = path.join(base, 'controle');
  copiaDe(ctl, ENGINE);
  const c = roda(ctl);
  console.log(`CONTROLE sem mutacao: exit=${c.status}`);
  if (c.status !== 0) {
    console.log('INSTRUMENTO: a suite nao passa no original; abortado.');
    process.exit(1);
  }
  const mortos = [];
  const vivos = [];
  const equivalentes = [];
  const instrumento = [];
  for (const [id, de, para, equiv] of M) {
    const ocorrencias = ENGINE.split(de).length - 1;
    if (ocorrencias !== 1) {
      instrumento.push(`${id} (ocorrencias=${ocorrencias})`);
      continue;
    }
    const dir = path.join(base, id);
    copiaDe(dir, ENGINE.replace(de, () => para));
    const r = roda(dir);
    const morto = r.status !== 0;
    console.log(`${morto ? 'MORTO ' : 'VIVO  '} ${id}${r.timeout ? ' (prazo)' : ''}${equiv && !morto ? '  [equivalente: ' + equiv + ']' : ''}`);
    if (morto) mortos.push(id);
    else if (equiv) equivalentes.push(id);
    else vivos.push(id);
    rmSync(dir, { recursive: true, force: true });
  }
  const total = M.length;
  console.log(`\nTOTAL=${total} MORTOS=${mortos.length} EQUIVALENTES_DOCUMENTADOS=${equivalentes.length} VIVOS=${vivos.length} INSTRUMENTO=${instrumento.length}`);
  if (vivos.length) console.log(`VIVOS: ${vivos.join(' ')}`);
  if (instrumento.length) console.log(`INSTRUMENTO (trecho nao encontrado ou ambiguo): ${instrumento.join(' ')}`);
  saida = vivos.length || instrumento.length ? 1 : 0;
} finally {
  rmSync(base, { recursive: true, force: true });
}
process.exit(saida);
