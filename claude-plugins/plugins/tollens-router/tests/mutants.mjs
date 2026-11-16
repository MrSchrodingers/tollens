// Gerador e executor de MUTANTES do motor de decisao (engine.mjs).
// Cada mutante troca UM trecho exato do engine por outro, grava a copia mutada numa arvore
// temporaria (o arquivo de producao nunca e alterado) e roda tests/unit/router-engine.test.mjs
// contra ela. Mutante morto = a suite falhou (ou estourou o prazo, anotado). Mutante vivo = lacuna
// de teste, exceto os marcados `equivalente`.
//
// Equivalente so vale com PROVA POR EXECUCAO: o mutante marcado que sobrevive a suite roda lado a
// lado com o original sobre o corpus adversarial deterministico (tests/corpus.mjs) mais entradas
// extras de fronteira, comparando decide, validatePolicy, parseRota e stripRota. Qualquer
// divergencia refuta a equivalencia e o mutante conta como VIVO. Zero divergencia e evidencia
// empirica (nao prova formal) e fica registrada com o numero de casos.
//
// Controles do instrumento: (1) a suite passa na copia SEM mutacao; (2) cada trecho `de` ocorre
// exatamente uma vez no engine; sem isso o mutante e reportado como INSTRUMENTO e o exit e 1.
//
// Uso: node claude-plugins/plugins/tollens-router/tests/mutants.mjs [--lista] [--diferencial=N] [--so=id1,id2]
// Exit: 0 se todo mutante nao equivalente morreu e todo equivalente foi confirmado; 1 caso contrario.
import { spawnSync } from 'node:child_process';
import { cpSync, mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';
import { casos } from './corpus.mjs';

const AQUI = path.dirname(fileURLToPath(import.meta.url));
const RAIZ = path.resolve(AQUI, '../../../..');
const PLUGIN = path.join(RAIZ, 'claude-plugins/plugins/tollens-router');
const TESTE = path.join(RAIZ, 'tests/unit/router-engine.test.mjs');
const ENGINE = readFileSync(path.join(PLUGIN, 'engine.mjs'), 'utf8');
const POLITICA = JSON.parse(readFileSync(path.join(PLUGIN, 'router-policy.json'), 'utf8'));
const SO = (process.argv.find((a) => a.startsWith('--so=')) ?? '').split('=')[1]?.split(',');
const NDIFF = Number((process.argv.find((a) => a.startsWith('--diferencial=')) ?? '--diferencial=6000').split('=')[1]);

// [id, de, para, equivalente?]
const M = [
  // ficha e parse
  ['ficha-teto-2049', 'const MAX_LINHA_BYTES = 2048;', 'const MAX_LINHA_BYTES = 4096;'],
  ['ficha-teto-2047', 'const MAX_LINHA_BYTES = 2048;', 'const MAX_LINHA_BYTES = 2047;'],
  ['ficha-so-bytes', 'linha.length > MAX_LINHA_BYTES || new TextEncoder().encode(linha).length > MAX_LINHA_BYTES',
    'new TextEncoder().encode(linha).length > MAX_LINHA_BYTES', 'bytes >= caracteres: a segunda condicao implica a primeira'],
  ['ficha-so-chars', 'linha.length > MAX_LINHA_BYTES || new TextEncoder().encode(linha).length > MAX_LINHA_BYTES',
    'linha.length > MAX_LINHA_BYTES', 'linha multibyte acima de 2048 bytes tem t fora de CHAVE_RE e vira ficha_invalida do mesmo jeito'],
  ['prefixo-sem-fronteira', '/^@@ROTA(?:[ \\t]|$)/', '/^@@ROTA/'],
  ['prefixo-sem-ancora', '/^@@ROTA(?:[ \\t]|$)/', '/@@ROTA(?:[ \\t]|$)/'],
  ['term-sem-cr', '/[\\r\\n\\u2028\\u2029\\u0085]/', '/[\\n\\u2028\\u2029\\u0085]/'],
  ['term-sem-lf', '/[\\r\\n\\u2028\\u2029\\u0085]/', '/[\\r\\u2028\\u2029\\u0085]/'],
  ['term-sem-2028', '/[\\r\\n\\u2028\\u2029\\u0085]/', '/[\\r\\n\\u2029\\u0085]/'],
  ['term-sem-2029', '/[\\r\\n\\u2028\\u2029\\u0085]/', '/[\\r\\n\\u2028\\u0085]/'],
  ['term-sem-0085', '/[\\r\\n\\u2028\\u2029\\u0085]/', '/[\\r\\n\\u2028\\u2029]/'],
  ['term-crlf-dois-terminadores', "m[0] === '\\r' && texto[m.index + 1] === '\\n' ? m.index + 2 : m.index + 1", 'm.index + 1'],
  ['strip-sempre-remove', 'if (!terminado && !parseRota(prompt).ok) return prompt;', ''],
  ['strip-remove-de-menos', 'return prompt.slice(resto);', 'return prompt.slice(resto - 1);'],
  ['strip-remove-demais', 'return prompt.slice(resto);', 'return prompt.slice(resto + 1);'],
  ['parse-linha-inteira', 'const { linha } = primeiraLinha(prompt);', 'const linha = prompt;'],
  ['ficha-4-campos', 'chaves.length !== 4', 'chaves.length !== 5'],
  ['ficha-nomes', "|| !['c', 'r', 'v', 't'].every((k) => chaves.includes(k))", ''],
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
  ['resolver-ok-false-ausente', "return f.motivo === 'ausente' ? ausente() : invalida();", 'return ausente();'],
  ['resolver-ok-false-invalida', "return f.motivo === 'ausente' ? ausente() : invalida();", 'return invalida();'],
  ['resolver-ficha-crua', 'return validateFicha(f);', 'return invalida();'],
  ['resolver-sem-revalidar', 'if (f.ok) return validateFicha(f.ficha);', 'if (f.ok) return { ok: true, ficha: f.ficha };'],
  // texto do prompt
  ['papel-sem-minuscula', ".replace(/\\s+/g, ' ').toLowerCase()", ".replace(/\\s+/g, ' ')"],
  ['papel-sem-trim', 's.trim().replace(', 's.replace('],
  ['papel-sem-colapso', ".replace(/\\s+/g, ' ')", ''],
  ['texto-sem-nfkc', ".normalize('NFKC').toLowerCase()", '.toLowerCase()'],
  ['texto-sem-minuscula', ".normalize('NFKC').toLowerCase()", ".normalize('NFKC')"],
  ['texto-sem-dobra', 'DOBRA.get(ch) ?? ch', 'ch'],
  ['texto-sem-nfd', ".normalize('NFD').replace(MARCAS_RE, '')", ".replace(MARCAS_RE, '')"],
  ['texto-sem-marcas-finais', ".normalize('NFD').replace(MARCAS_RE, '')", ".normalize('NFD')"],
  ['texto-sem-limpar-formato', '/[\\p{Cf}\\p{M}]+/gu', '/[\\p{M}]+/gu'],
  ['texto-sem-limpar-marcas', '/[\\p{Cf}\\p{M}]+/gu', '/[\\p{Cf}]+/gu'],
  ['texto-sem-corte-de-trecho', '.slice(0, MAX_TOKEN_TEXTO)', '',
    'o corte so limita custo: prefixos de ate 64 caracteres no inicio do trecho casam igual, e as marcas ja saem antes do corte'],
  ['tokens-sem-cache', 'let n = cache.get(bruto);', 'let n;', 'o cache so evita renormalizar o mesmo trecho'],
  ['risco-sem-fronteira-inicial', 'alvo.includes(` ${norm}`)', 'alvo.includes(norm)'],
  ['risco-com-fronteira-final', 'alvo.includes(` ${norm}`)', 'alvo.includes(` ${norm} `)'],
  ['risco-palavra-vazia', "norm !== '' && ", '', 'palavra que normaliza para vazio nao existe numa politica valida'],
  ['recorte-sem-cauda', 'return `${texto.slice(0, metade)} ${texto.slice(-metade)}`;', 'return texto.slice(0, metade);'],
  ['recorte-sem-cabeca', 'return `${texto.slice(0, metade)} ${texto.slice(-metade)}`;', 'return texto.slice(-metade);'],
  ['recorte-limite-exato', 'if (texto.length <= limite) return texto;', 'if (texto.length < limite) return texto;'],
  ['recorte-sem-aviso', "if (analise !== texto) add('prompt_truncado');", ''],
  ['limites-ignorados', "own(policy, 'limites') ? policy.limites.prompt_max_bytes : PROMPT_MAX_PADRAO", 'PROMPT_MAX_PADRAO'],
  ['limites-padrao-menor', 'const PROMPT_MAX_PADRAO = 65536;', 'const PROMPT_MAX_PADRAO = 32768;'],
  ['caminho-sem-barra-inicial', "tok.startsWith('/') || ", ''],
  ['caminho-sem-til', "tok.startsWith('~') || ", ''],
  ['caminho-sem-extensao', 'if (EXTENSAO_RE.test(tok)) return true;', ''],
  ['caminho-duas-barras', "tok.split('/').length - 1 >= 2", "tok.split('/').length - 1 >= 3"],
  ['caminho-sem-teto-de-token', 'tok.length > MAX_TOKEN_CAMINHO || ', ''],
  ['caminho-sem-parada', 'if (vistos.size > limite) break;', '', 'so poda trabalho: a contagem acima do limiar ja decide'],
  ['caminho-nao-distintos', 'vistos.add(tok);', 'vistos.add(tok + vistos.size);'],
  // piso
  ['piso-nao-sobe', 'if (idx > floor) floor = idx;', 'if (idx < floor) floor = idx;'],
  ['papel-so-role', 'const nomes = [papel(inp.role), papel(inp.subagentType)];', 'const nomes = [papel(inp.role)];'],
  ['papel-so-subagente', 'const nomes = [papel(inp.role), papel(inp.subagentType)];', 'const nomes = [papel(inp.subagentType)];'],
  ['revisor-sempre', 'nomes.some((n) => revisores.has(n))', 'true'],
  ['revisor-sem-own', 'chave !== null && own(autorPorChave, chave) ? tierIdx(autorPorChave[chave]) : -1', 'chave !== null ? tierIdx(autorPorChave[chave]) : -1'],
  ['revisor-sem-maximo', "if (autor < 0 && own(hist, 'autorTierMax')) autor = tierIdx(hist.autorTierMax);", ''],
  ['revisor-maximo-sempre', "if (autor < 0 && own(hist, 'autorTierMax')) autor", "if (own(hist, 'autorTierMax')) autor"],
  ['revisor-maximo-sem-own', "autor < 0 && own(hist, 'autorTierMax')", 'autor < 0'],
  ['chave-sem-limite', 'inp.chave.length <= MAX_CHAVE', 'true'],
  ['chave-de-fallback-na-ficha', "const chave = typeof inp.chave === 'string' && inp.chave.length <= MAX_CHAVE ? inp.chave : null;",
    "const chave = typeof inp.chave === 'string' && inp.chave.length <= MAX_CHAVE ? inp.chave : (ficha ? ficha.t : null);"],
  ['tamanho-igual-vale', 'texto.length > tamanho.acima_de', 'texto.length >= tamanho.acima_de'],
  ['caminhos-igual-vale', 'contaCaminhos(analise, caminhos.acima_de) > caminhos.acima_de', 'contaCaminhos(analise, caminhos.acima_de) >= caminhos.acima_de'],
  ['ficha-so-complexidade',
    'Math.max(tierIdx(policy.ficha_tiers.complexidade[String(ficha.c)]), tierIdx(policy.ficha_tiers.risco[ficha.r]))',
    'tierIdx(policy.ficha_tiers.complexidade[String(ficha.c)])'],
  ['ficha-so-risco',
    'Math.max(tierIdx(policy.ficha_tiers.complexidade[String(ficha.c)]), tierIdx(policy.ficha_tiers.risco[ficha.r]))',
    'tierIdx(policy.ficha_tiers.risco[ficha.r])'],
  ['ficha-ignora-piso', 'let tier = Math.max(daFicha, floor);', 'let tier = daFicha;'],
  ['subclassificacao-muda', "if (ficha && daFicha < floor) add('ficha_abaixo_do_piso');", ''],
  // repeticao e teto
  ['repeticao-so-depois-de-2', "typeof falhas === 'number' && falhas >= 1;", "typeof falhas === 'number' && falhas > 1;"],
  ['repeticao-sem-own', 'chave !== null && own(falhasPorChave, chave) ? falhasPorChave[chave] : 0', 'chave !== null ? falhasPorChave[chave] : 0'],
  ['teto-sempre-concede', 'if (concedeSubida(falhasPorChave, chave, falhas, policy.escalation.max_por_fluxo)) {', 'if (true) {'],
  ['concede-sem-pegajosa', 'if (falhas >= 2) return true;', ''],
  ['concede-sem-contar-concedidas', 'if (n >= 2) concedidas++;', ''],
  ['concede-conta-zeros', 'else if (n >= 1 && k < chave) novasAntes++;', 'else if (n >= 0 && k < chave) novasAntes++;'],
  ['concede-conta-a-propria', 'else if (n >= 1 && k < chave) novasAntes++;', 'else if (n >= 1 && k <= chave) novasAntes++;'],
  ['concede-limite-inclusivo', 'return novasAntes < max - concedidas;', 'return novasAntes <= max - concedidas;'],
  ['concede-nao-numero', "if (typeof n !== 'number') continue;", ''],
  ['capped-sem-repeticao-multipla', 'if (tier >= TOPO || falhas >= 2) capped = true;', 'if (tier >= TOPO) capped = true;'],
  ['capped-sem-topo', 'if (tier >= TOPO || falhas >= 2) capped = true;', 'if (falhas >= 2) capped = true;'],
  ['capped-sem-teto', '      capped = true;\n      add(\'teto_por_fluxo\');', '      add(\'teto_por_fluxo\');'],
  ['repeticao-sem-teto-topo', 'tier = Math.min(TOPO, tier + 1);', 'tier = tier + 1;'],
  ['repeticao-nao-sobe', 'tier = Math.min(TOPO, tier + 1);', 'tier = tier;'],
  ['repeticao-piso-fixo', 'floor = Math.min(TOPO, floor + 1);', 'floor = Math.min(TOPO, floor);'],
  ['tier-base-depois-do-ritmo', 'tier_base: TIER_NAMES[tierBase],', 'tier_base: TIER_NAMES[tier],'],
  // ritmo
  ['ritmo-desce-sem-verificar-v', "ficha.v === 'sim' && !repetida", "ficha.v !== 'nao' && !repetida"],
  ['ritmo-desce-apos-falha', "ficha.v === 'sim' && !repetida", "ficha.v === 'sim'"],
  ['ritmo-desce-abaixo-do-piso', 'alvo >= floor && ', ''],
  ['ritmo-desce-p-nao-medido', "estadoDoNivel(policy, nomes, alvo) === 'medido_ok'", "estadoDoNivel(policy, nomes, alvo) !== 'reprovado'"],
  ['ritmo-desce-sem-qualidade', " && estadoDoNivel(policy, nomes, alvo) === 'medido_ok'", ''],
  ['ritmo-abaixo-desce-tambem', "if (estado === 'acima' && ficha && ficha.v === 'sim' && !repetida) {",
    "if (estado !== 'dentro' && ficha && ficha.v === 'sim' && !repetida) {"],
  ['ritmo-sobe-sem-verificar-v', "estado === 'abaixo' && ficha && ficha.v === 'nao' && tier < TOPO", "estado === 'abaixo' && ficha && ficha.v !== 'sim' && tier < TOPO"],
  ['ritmo-sobe-sem-teto', "estado === 'abaixo' && ficha && ficha.v === 'nao' && tier < TOPO", "estado === 'abaixo' && ficha && ficha.v === 'nao'"],
  ['ritmo-sobe-dois', "tier += 1;\n    add('ritmo_sobe');", "tier += 2;\n    add('ritmo_sobe');"],
  ['ritmo-estado-livre', 'isObj(inp.pace) && ESTADOS_RITMO.includes(inp.pace.estado) ? inp.pace.estado', 'isObj(inp.pace) ? inp.pace.estado',
    'estado fora do enum nao casa nenhum dos dois ramos: o resultado e igual ao de dentro'],
  // qualidade (R12)
  ['qualidade-nao-sobe', "while (tier <= TOPO && estadoDoNivel(policy, nomes, tier) === 'reprovado') {", 'while (false) {'],
  ['qualidade-colapsa-nao-medido', "while (tier <= TOPO && estadoDoNivel(policy, nomes, tier) === 'reprovado') {", "while (tier <= TOPO && estadoDoNivel(policy, nomes, tier) !== 'medido_ok') {"],
  ['qualidade-sem-elegivel-aplica', 'const semElegivel = tier > TOPO;', 'const semElegivel = false;'],
  ['qualidade-sem-elegivel-nao-volta', '    tier = tierBase;', ''],
  ['qualidade-sem-aviso-final', "add('sem_nivel_elegivel');", ''],
  ['qualidade-modo-efetivo', "const modoEfetivo = mode === 'enforce' && semElegivel ? 'shadow' : mode;", 'const modoEfetivo = mode;'],
  ['qualidade-aplicar-por-mode', "aplicar: modoEfetivo === 'enforce',", "aplicar: mode === 'enforce',"],
  ['qualidade-sem-aviso-nao-medido', "if (estadoNivel === 'nao_medido') add('nivel_nao_medido');", ''],
  ['qualidade-sem-piso-de-papel', 'exigida = Math.max(exigida, v);', 'exigida = exigida;'],
  ['qualidade-igual-nao-vale', 'return q.aprovacao_medida >= exigenciaDeAprovacao(policy, nomes)', 'return q.aprovacao_medida > exigenciaDeAprovacao(policy, nomes)'],
  ['qualidade-null-vale', "if (q.aprovacao_medida === null) return 'nao_medido';", ''],
  ['degrada-shadow-sem-enforce', "(policy.mode === 'enforce' && algumNivelNaoMedido(policy));", 'algumNivelNaoMedido(policy);'],
  ['degrada-nunca-por-medicao', "(policy.mode === 'enforce' && algumNivelNaoMedido(policy));", 'false;'],
  ['degrada-sem-aviso-de-medicao', "if (policy.mode === 'enforce' && algumNivelNaoMedido(policy)) add('nivel_nao_medido');", ''],
  // modo, relogio e validade
  ['modo-vencida-promove-off', "if (mode !== 'off') mode = validade.degradaPara;", 'mode = validade.degradaPara;'],
  ['modo-aplicar-shadow', "aplicar: modoEfetivo === 'enforce',", "aplicar: modoEfetivo !== 'off',"],
  ['modo-invalida-nao-off', "mode: 'off', modo_efetivo: 'off', aplicar: false", "mode: 'shadow', modo_efetivo: 'shadow', aplicar: false"],
  ['validade-igual-vale', "return agora >= Date.parse(validUntil) ? 'vencida' : null;", "return agora > Date.parse(validUntil) ? 'vencida' : null;"],
  ['validade-sem-relogio-vale', "if (Number.isNaN(agora)) return 'sem_relogio_valido';", ''],
  ['validade-sem-aviso-vencida', "if (situacao === 'vencida') add('politica_vencida');", ''],
  ['validade-sem-aviso-relogio', "if (situacao === 'sem_relogio_valido') add('sem_relogio_valido');", ''],
  ['relogio-so-iso', "typeof now === 'number' ? now : instanteIso(now, AGORA_ISO_RE)", 'instanteIso(now, AGORA_ISO_RE)'],
  ['relogio-minimo-zero', 'ms >= AGORA_MIN', 'ms >= 0'],
  ['relogio-minimo-exclusivo', 'ms >= AGORA_MIN', 'ms > AGORA_MIN'],
  ['relogio-sem-maximo', ' && ms <= AGORA_MAX', ''],
  ['relogio-minimo-menor', 'const AGORA_MIN = 1.6e12;', 'const AGORA_MIN = 1.5e12;'],
  ['relogio-maximo-maior', 'const AGORA_MAX = 4.1e12;', 'const AGORA_MAX = 4.2e12;'],
  ['relogio-nao-inteiro', 'Number.isInteger(ms) && ', ''],
  ['iso-sem-ida-e-volta', 'return new Date(t).toISOString() === canonico ? t : NaN;', 'return t;'],
  ['iso-sem-checar-nan', 'if (Number.isNaN(t)) return NaN;', ''],
  ['horizonte-inclusivo', 'validUntil - agora > HORIZONTE_MS', 'validUntil - agora >= HORIZONTE_MS'],
  ['horizonte-maior', 'const HORIZONTE_MS = 400 * 86400000;', 'const HORIZONTE_MS = 401 * 86400000;'],
  ['entrada-nao-objeto', 'const inp = isObj(input) ? input : {};', 'const inp = input;'],
  ['texto-com-linha-rota', "const texto = stripRota(typeof inp.prompt === 'string' ? inp.prompt : '');", "const texto = typeof inp.prompt === 'string' ? inp.prompt : '';"],
  ['politica-invalida-segue', 'if (!validade.ok) return semDecisao();', ''],
  // validador
  ['alias-por-prefixo', '!ALIAS_PERMITIDOS.includes(m)', '!ALIAS_PERMITIDOS.some((a) => String(m).startsWith(a))'],
  ['tier-fora-da-allowlist', 'modelo < 0 || !allowOk.includes(x.model)', 'modelo < 0'],
  ['custo-decrescente-vale', 'if (custo < anterior)', 'if (false)'],
  ['custo-igual-reprova', 'if (custo < anterior)', 'if (custo <= anterior)'],
  ['custo-so-esforco', 'const custo = modelo * EFFORTS.length + esforco;', 'const custo = esforco;'],
  ['custo-so-modelo', 'const custo = modelo * EFFORTS.length + esforco;', 'const custo = modelo;'],
  ['revisor-piso-minimo-T1', 'tierIdx(piso) < 2', 'tierIdx(piso) < 1'],
  ['revisor-piso-minimo-T3', 'tierIdx(piso) < 2', 'tierIdx(piso) < 3'],
  ['revisores-vazios-valem', 'policy.reviewer_roles.length === 0 || ', ''],
  ['politica-schema-version', 'policy.schema_version !== 1', 'false'],
  ['politica-version', 'if (!ehTexto(policy.version, 64)) erros.push', 'if (false) erros.push'],
  ['politica-mode', 'if (!MODES.includes(policy.mode)) erros.push', 'if (false) erros.push'],
  ['politica-effort', 'if (esforco < 0) erros.push', 'if (false) erros.push'],
  ['politica-complexidade', 'if (tierIdx(complexidade[k]) < 0) erros.push', 'if (false) erros.push'],
  ['politica-risco', 'if (tierIdx(risco[k]) < 0) erros.push', 'if (false) erros.push'],
  ['politica-role-floors-nivel', 'if (!ehTexto(k, 64) || tierIdx(v) < 0) erros.push', 'if (!ehTexto(k, 64)) erros.push'],
  ['politica-role-floors-chave', 'if (!ehTexto(k, 64) || tierIdx(v) < 0) erros.push', 'if (tierIdx(v) < 0) erros.push'],
  ['politica-reviewer-itens', '|| !policy.reviewer_roles.every((r) => ehTexto(r, 64))', ''],
  ['politica-risk-piso', 'if (tierIdx(policy.risk_surface.piso) < 0) erros.push', 'if (false) erros.push'],
  ['politica-words-vazia', 'w.length === 0 || ', ''],
  ['politica-words-demais', ' || w.length > MAX_PALAVRAS', ''],
  ['politica-words-itens', ' || !w.every((x) => ehTexto(x, 64) && TEM_LETRA_OU_DIGITO_RE.test(x))', ''],
  ['politica-nota', 'if (!ehTexto(policy.risk_surface.nota, 400)) erros.push', 'if (false) erros.push'],
  ['politica-limites-faixa', 'ehInteiroEm(policy.limites.prompt_max_bytes, 1024, 4194304)', 'ehInteiroEm(policy.limites.prompt_max_bytes, 0, Number.MAX_SAFE_INTEGER)'],
  ['politica-limiar-acima', 'if (!ehInteiroEm(l.acima_de, 1, Number.MAX_SAFE_INTEGER)) erros.push', 'if (false) erros.push'],
  ['politica-limiar-piso', 'if (tierIdx(l.piso) < 0) erros.push', 'if (false) erros.push'],
  ['politica-pace-ordem', '|| !(a < b)', ''],
  ['politica-pace-numeros', '!ehNumeroEm(a, -1000, 1000) || !ehNumeroEm(b, -1000, 1000) || ', ''],
  ['politica-escalation', 'if (!ehInteiroEm(policy.escalation.max_por_fluxo, 0, 1000)) erros.push', 'if (false) erros.push'],
  ['politica-piso-default', 'if (!ehNumeroEm(piso.default, 0, 1)) erros.push', 'if (false) erros.push'],
  ['politica-piso-por-papel', 'if (!isObj(piso.por_papel) || !Object.values(piso.por_papel).every((x) => ehNumeroEm(x, 0, 1))) {', 'if (false) {'],
  ['politica-aprovacao', 'if (!semAprov && !ehNumeroEm(q.aprovacao_medida, 0, 1)) erros.push', 'if (false) erros.push'],
  ['politica-n', 'if (q.n !== null && !ehInteiroEm(q.n, 1, Number.MAX_SAFE_INTEGER)) erros.push', 'if (false) erros.push'],
  ['politica-n-consistente', 'if (semAprov !== (q.n === null)) erros.push', 'if (false) erros.push'],
  ['politica-fonte', 'if (!ehTexto(q.fonte, 400)) erros.push', 'if (false) erros.push'],
  ['politica-chave-extra', 'for (const k of Object.keys(obj)) if (!esperadas.includes(k) && !opcionais.includes(k)) erros.push', 'for (const k of Object.keys(obj)) if (false) erros.push'],
  ['politica-chave-opcional-qualquer', '!esperadas.includes(k) && !opcionais.includes(k)', '!esperadas.includes(k) && false'],
  ['politica-chave-faltando', 'for (const k of esperadas) if (!Object.hasOwn(obj, k)) erros.push', 'for (const k of esperadas) if (false) erros.push'],
  ['politica-inteiro', 'ehNumeroEm(x, min, max) && Number.isInteger(x)', 'ehNumeroEm(x, min, max)'],
  ['politica-denso', 'const denso = (a) => Array.isArray(a) && Object.keys(a).length === a.length;', 'const denso = (a) => Array.isArray(a);'],
];

function copiaDe(trabalho, engineTexto) {
  const plug = path.join(trabalho, 'claude-plugins/plugins/tollens-router');
  mkdirSync(path.join(plug, 'tests'), { recursive: true });
  mkdirSync(path.join(trabalho, 'tests/unit'), { recursive: true });
  cpSync(path.join(PLUGIN, 'router-policy.json'), path.join(plug, 'router-policy.json'));
  cpSync(path.join(PLUGIN, 'policy.schema.json'), path.join(plug, 'policy.schema.json'));
  cpSync(path.join(PLUGIN, 'tests/corpus.mjs'), path.join(plug, 'tests/corpus.mjs'));
  cpSync(TESTE, path.join(trabalho, 'tests/unit/router-engine.test.mjs'));
  writeFileSync(path.join(plug, 'engine.mjs'), engineTexto);
  return path.join(plug, 'engine.mjs');
}

function roda(trabalho) {
  const r = spawnSync(process.execPath, ['--test', '--test-reporter=tap', '--experimental-test-isolation=none', path.join(trabalho, 'tests/unit/router-engine.test.mjs')],
    { encoding: 'utf8', timeout: 90_000, killSignal: 'SIGKILL', maxBuffer: 64 * 1024 * 1024 });
  const reprovados = [...(r.stdout ?? '').matchAll(/^not ok \d+ - (.*)$/gm)].map((m) => m[1]);
  return { status: r.status, timeout: r.error?.code === 'ETIMEDOUT' || r.signal === 'SIGKILL', reprovados };
}

// Testes sensiveis a carga da maquina (tempo e orcamento de CPU). Um mutante que so cai neles pode
// ter caido por carga: reexecuta e so conta como morto se a falha se repetir.
const SENSIVEL_A_CARGA = /^J1 tempo|propriedades/;
function mortoConfirmado(dir, primeira) {
  if (primeira.status === 0) return false;
  if (primeira.timeout || primeira.reprovados.length === 0) return true;
  if (!primeira.reprovados.every((n) => SENSIVEL_A_CARGA.test(n))) return true;
  for (let i = 0; i < 2; i++) if (roda(dir).status === 0) return false;
  return true;
}

const EXTRAS = [
  `@@ROTA {"c":1,"r":"trivial","v":"sim","t":"${'\u00e9'.repeat(1100)}"}\nmigracao`,
  `@@ROTA {"c":1,"r":"trivial","v":"sim","t":"k"}${' '.repeat(2000)}\nresto`,
  `@@ROTA {"c":"1","r":"trivial","v":"sim","t":"k"}\nresto`,
  `@@ROTA {"c":true,"r":"trivial","v":"sim","t":"k"}\nresto`,
  `@@ROTA {"c":null,"r":"trivial","v":"sim","t":"k"}\nresto`,
  `@@ROTA {"c":[1],"r":"trivial","v":"sim","t":"k"}\nresto`,
  `${'palavra '.repeat(200)}deployed ${'x'.repeat(100)}`,
  `${'z'.repeat(70)} producao ${'\u200b'.repeat(80)}token`,
];

function resultado(fn) {
  try {
    return JSON.stringify(fn(), (k, v) => (typeof v === 'number' && !Number.isFinite(v) ? String(v) : v === undefined ? '__undef' : v));
  } catch (e) {
    return `LANCOU ${String(e).slice(0, 80)}`;
  }
}

// Compara original e mutante sobre o corpus e as entradas extras; devolve o numero de divergencias.
async function diferencial(arquivoMutante) {
  const orig = await import(pathToFileURL(path.join(PLUGIN, 'engine.mjs')).href);
  const mut = await import(`${pathToFileURL(arquivoMutante).href}?mutante`);
  let casosN = 0;
  let divergencias = 0;
  const g1 = casos(NDIFF, 0xD1FF, structuredClone(POLITICA));
  const g2 = casos(NDIFF, 0xD1FF, structuredClone(POLITICA));
  for (;;) {
    const a = g1.next();
    const b = g2.next();
    if (a.done) break;
    casosN++;
    const prompt = a.value.input?.prompt;
    const pares = [
      [() => orig.decide(a.value.input, a.value.policy), () => mut.decide(b.value.input, b.value.policy)],
      [() => orig.validatePolicy(a.value.policy, { now: a.value.input?.now }), () => mut.validatePolicy(b.value.policy, { now: b.value.input?.now })],
      [() => orig.parseRota(prompt), () => mut.parseRota(b.value.input?.prompt)],
      [() => orig.stripRota(prompt), () => mut.stripRota(b.value.input?.prompt)],
    ];
    for (const [fa, fb] of pares) if (resultado(fa) !== resultado(fb)) divergencias++;
  }
  for (const extra of EXTRAS) {
    for (const politica of [POLITICA, { ...structuredClone(POLITICA), mode: 'enforce' }]) {
      for (const [fo, fm] of [
        [() => orig.decide({ prompt: extra, now: 1794787200000 }, politica), () => mut.decide({ prompt: extra, now: 1794787200000 }, politica)],
        [() => orig.parseRota(extra), () => mut.parseRota(extra)],
        [() => orig.stripRota(extra), () => mut.stripRota(extra)],
      ]) {
        casosN++;
        if (resultado(fo) !== resultado(fm)) divergencias++;
      }
    }
  }
  return { casosN, divergencias };
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
    saida = 1;
  } else {
    const mortos = [];
    const vivos = [];
    const confirmados = [];
    const instrumento = [];
    for (const [id, de, para, equiv] of M) {
      if (SO && !SO.includes(id)) continue;
      const ocorrencias = ENGINE.split(de).length - 1;
      if (ocorrencias !== 1) {
        instrumento.push(`${id} (ocorrencias=${ocorrencias})`);
        continue;
      }
      const dir = path.join(base, id);
      const arquivo = copiaDe(dir, ENGINE.replace(de, () => para));
      const r = roda(dir);
      const soCarga = r.reprovados.length > 0 && r.reprovados.every((n) => SENSIVEL_A_CARGA.test(n));
      // Mutante declarado equivalente que so cai em teste de tempo/CPU nao conta como morto: vai a prova por execucao.
      const morto = mortoConfirmado(dir, r) && !(soCarga && equiv);
      if (morto) {
        mortos.push(id);
        console.log(`MORTO  ${id}${r.timeout ? ' (prazo)' : ''}${soCarga ? ' (so por teste de tempo/CPU, falha repetida)' : ''}`);
      } else if (equiv) {
        const d = await diferencial(arquivo);
        if (d.divergencias === 0) {
          confirmados.push(id);
          console.log(`EQUIVALENTE ${id}  [0 divergencias em ${d.casosN} comparacoes; ${equiv}]`);
        } else {
          vivos.push(id);
          console.log(`VIVO   ${id}  [equivalencia REFUTADA: ${d.divergencias} divergencias em ${d.casosN} comparacoes]`);
        }
      } else {
        vivos.push(id);
        console.log(`VIVO   ${id}`);
      }
      rmSync(dir, { recursive: true, force: true });
    }
    console.log(`\nTOTAL=${M.length} MORTOS=${mortos.length} EQUIVALENTES_CONFIRMADOS=${confirmados.length} VIVOS=${vivos.length} INSTRUMENTO=${instrumento.length}`);
    if (vivos.length) console.log(`VIVOS: ${vivos.join(' ')}`);
    if (confirmados.length) console.log(`EQUIVALENTES: ${confirmados.join(' ')}`);
    if (instrumento.length) console.log(`INSTRUMENTO (trecho nao encontrado ou ambiguo): ${instrumento.join(' ')}`);
    saida = vivos.length || instrumento.length ? 1 : 0;
  }
} finally {
  rmSync(base, { recursive: true, force: true });
}
process.exit(saida);
