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
// Uma linha por mutante: `MORTO | id | teste: <primeiro teste que falhou>`, `VIVO | id | ...` ou `EQUIVALENTE | id | ...`.
//
// Uso: node claude-plugins/plugins/tollens-router/tests/mutants.mjs [--lista] [--diferencial=N] [--so=id1,id2] [--fatia=i/n] [--verificar]
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
const FATIA = (process.argv.find((a) => a.startsWith('--fatia=')) ?? '').split('=')[1]?.split('/').map(Number);
const NDIFF = Number((process.argv.find((a) => a.startsWith('--diferencial=')) ?? '--diferencial=6000').split('=')[1]);

// [id, de, para, equivalente?]
const M = [
  // rodada 3: janelas, dado puro, teto pegajoso, papel, qualidade com n minimo e emitivel
  ['papel-sem-trim', "return norm.slice(norm.lastIndexOf(':') + 1).trim();", "return norm.slice(norm.lastIndexOf(':') + 1);"],
  ['teto-igual-sinaliza', 'if (texto.length > teto) {', 'if (texto.length >= teto) {'],
  ['teto-sem-aviso', "add('prompt_acima_do_teto');", ''],
  ['tamanho-igual-vale', 'texto.length > tamanho.acima_de', 'texto.length >= tamanho.acima_de'],
  ['varredura-sempre-risco', 'const queRisco = pisoRisco > floor;', 'const queRisco = true;'],
  ['varredura-sempre-caminhos', 'const quePaths = pisoCaminhos > floor;', 'const quePaths = true;'],
  ['varredura-nunca-risco', 'const queRisco = pisoRisco > floor;', 'const queRisco = false;'],
  ['concede-sem-lista', 'h.concedidas.has(chave) || ', ''],
  ['concede-sem-falhas2', ' || falhas >= 2) return true;', ') return true;'],
  ['concede-sem-ordem-temporal', 'if (posicao(a) !== posicao(b)) return posicao(a) < posicao(b);', ''],
  ['concede-sem-criticidade', 'if (criticaDe(a) !== criticaDe(b)) return criticaDe(a);', ''],
  ['critica-sem-lista', 'criticas.has(k) || ', ''],
  ['ordem-sem-primeira-posicao', '.map((k, i) => [k, i]).reverse()', '.map((k, i) => [k, i])'],
  ['concede-historico-truncado', 'if (h.truncado) return false;', ''],
  ['teto-sempre-concede', 'if (concedeSubida(historico, chave, falhas, policyCopia.escalation.max_por_fluxo, criticaDe)) {', 'if (true) {'],
  ['subida-concedida-nao-informa', 'subidaConcedida = true;', ''],
  ['chave-vazia-vale', 'inp.chave.length >= 1 && ', ''],
  ['chave-sem-limite', ' && inp.chave.length <= MAX_CHAVE', ''],
  ['chave-sem-aviso', "if (chave === null) add('sem_chave');", ''],
  ['historico-sem-aviso', "if (ctx.truncado) add('history_truncado');", ''],
  ['dado-puro-getter', "!Object.hasOwn(d, 'value')", 'false'],
  ['dado-puro-prototipo', 'lista ? proto !== Array.prototype : proto !== Object.prototype && proto !== null', 'false'],
  ['dado-puro-profundidade', 'profundidade > MAX_PROFUNDIDADE || ', ''],
  ['dado-puro-ciclo', ' || pilha.has(v)', '', 'o contador de nos (100000) tambem encerra o ciclo largo; o corpus tem ciclo largo, entao a comparacao e prova real'],
  ['dado-puro-history-sem-corte', "profundidade === 0 && k === 'history'", 'false'],
  ['dado-puro-corte-maior', 'const MAX_HISTORY = 1000;', 'const MAX_HISTORY = 100000;'],
  ['dado-puro-lista-esparsa', 'if (lista) saida.length = Math.min(', 'if (false) saida.length = Math.min('],
  ['dado-puro-teto-politica', 'const MAX_CHAVES_POLITICA = 10000;', 'const MAX_CHAVES_POLITICA = 100000000;'],
  ['qualidade-nao-sobe', "while (tier <= TOPO && (!emitivel(policyCopia, tier) || estadoDoNivel(policyCopia, nomes, tier) === 'reprovado')) {", 'while (false) {'],
  ['qualidade-colapsa-nao-medido', "|| estadoDoNivel(policyCopia, nomes, tier) === 'reprovado')) {", "|| estadoDoNivel(policyCopia, nomes, tier) !== 'medido_ok')) {"],
  ['qualidade-ignora-emitivel', '(!emitivel(policyCopia, tier) || ', '(false || '],
  ['qualidade-sem-aviso-reprovado', "if (emitivel(policyCopia, tier)) add('abaixo_do_piso_de_qualidade');", ''],
  ['ritmo-desce-sem-emitivel', 'emitivel(policyCopia, alvo) && ', ''],
  ['emitivel-ignorado', "policy.tiers[TIER_NAMES[idx]].emitivel !== false", 'true'],
  ['enforce-exige-nao-emitiveis', 'emitivel(policy, i) && estadoDoNivel(policy, [], i)', 'estadoDoNivel(policy, [], i)'],
  ['n-minimo-ignorado', "if (!(q.n >= limiteDe(policy, 'n_minimo', N_MINIMO_PADRAO))) return 'nao_medido';", ''],
  ['n-minimo-inclusivo', "q.n >= limiteDe(policy, 'n_minimo', N_MINIMO_PADRAO)", "q.n > limiteDe(policy, 'n_minimo', N_MINIMO_PADRAO)"],
  ['n-minimo-padrao', 'const N_MINIMO_PADRAO = 8;', 'const N_MINIMO_PADRAO = 7;'],
  ['limites-ignorados', "own(policy.limites, nome) ? policy.limites[nome] : padrao", 'padrao'],
  ['politica-limites-indefinido', 'teto !== undefined && ', ''],
  ['politica-nmin-faixa', 'ehInteiroEm(nMin, 1, 1000)', 'ehInteiroEm(nMin, 0, Number.MAX_SAFE_INTEGER)'],
  ['politica-custo-estrito', 'if (custo <= anterior)', 'if (custo < anterior)'],
  ['politica-custo-livre', 'if (custo <= anterior)', 'if (false)'],
  ['politica-algum-emitivel', "if (!algumEmitivel) erros.push('tiers: nenhum nivel emitivel');", ''],
  ['politica-emitivel-booleano', "if (Object.hasOwn(x, 'emitivel') && typeof x.emitivel !== 'boolean') erros.push", 'if (false) erros.push'],
  ['politica-papeis-obrigatorios', 'if (tierIdx(valorDoPapel(policy.role_floors, nome)) < minimo) erros.push', 'if (false) erros.push'],
  ['politica-papel-minimo-menor', 'for (const [nome, minimo] of PAPEIS_OBRIGATORIOS) {', 'for (const [nome, minimo] of PAPEIS_OBRIGATORIOS.map(([n]) => [n, 0])) {'],
  ['politica-revisores-vazios', 'policy.reviewer_roles.length === 0 || ', ''],
  ['politica-risk-piso-T3', "tierIdx(policy.risk_surface.piso) < 3", "tierIdx(policy.risk_surface.piso) < 2"],
  ['politica-size-piso-prompt', "tierIdx(policy.size.prompt_chars?.piso) < 2", "tierIdx(policy.size.prompt_chars?.piso) < 1"],
  ['politica-prefixos-obrigatorios', 'for (const p of PREFIXOS_OBRIGATORIOS) if (!normais.has(p))', 'for (const p of PREFIXOS_OBRIGATORIOS) if (false)'],
  ['politica-palavra-curta', 'if (n.length < 3) erros.push', 'if (n.length < 2) erros.push'],
  ['politica-words-demais', ' || w.length > MAX_PALAVRAS', ''],
  ['politica-words-nao-texto', ' || !w.every((x) => ehTexto(x, 64))', ''],
  ['politica-piso-default-min', 'ehNumeroEm(piso.default, 0.5, 1)) erros.push(\'quality.piso_aprovacao.default', 'ehNumeroEm(piso.default, 0, 1)) erros.push(\'quality.piso_aprovacao.default'],
  ['politica-por-papel-min', 'ehNumeroEm(x, ehNumeroEm(piso.default, 0.5, 1) ? piso.default : 0.5, 1)', 'ehNumeroEm(x, 0.5, 1)'],
  ['politica-invalida-segue', "if (!validade.ok) return semDecisao('politica_invalida');", ''],
  ['politica-piso-por-papel', "if (!isObj(piso.por_papel) || !Object.values(piso.por_papel).every((x) => ehNumeroEm(x, ehNumeroEm(piso.default, 0.5, 1) ? piso.default : 0.5, 1))) {", 'if (false) {'],
  ['degrada-shadow-sem-enforce', "(policy.mode === 'enforce' && algumEmitivelNaoMedido(policy));", 'algumEmitivelNaoMedido(policy);'],
  ['degrada-nunca-por-medicao', "(policy.mode === 'enforce' && algumEmitivelNaoMedido(policy));", 'false;'],
  ['degrada-sem-aviso-de-medicao', "if (policyCopia.mode === 'enforce' && algumEmitivelNaoMedido(policyCopia)) add('nivel_nao_medido');", ''],
  ['texto-com-linha-rota', 'const texto = stripRota(bruto);', 'const texto = bruto;'],
  ['ficha-so-complexidade', 'Math.max(tierIdx(policyCopia.ficha_tiers.complexidade[String(ficha.c)]), tierIdx(policyCopia.ficha_tiers.risco[ficha.r]))', 'tierIdx(policyCopia.ficha_tiers.complexidade[String(ficha.c)])'],
  ['ficha-so-risco', 'Math.max(tierIdx(policyCopia.ficha_tiers.complexidade[String(ficha.c)]), tierIdx(policyCopia.ficha_tiers.risco[ficha.r]))', 'tierIdx(policyCopia.ficha_tiers.risco[ficha.r])'],
  ['concede-limite-inclusivo', 'if (anteriores >= vagas) return false;', 'if (anteriores > vagas) return false;'],
  ['concede-sem-conferir-no-laco', 'if (anteriores >= vagas) return false;', ''],
  ['politica-chave-faltando', 'for (const k of esperadas) if (!Object.hasOwn(obj, k)) erros.push', 'for (const k of esperadas) if (false) erros.push', 'cada campo exigido tem validacao de tipo propria (inclusive undefined): a chave ausente falha nela'],
  ['ficha-nomes', "|| !['c', 'r', 'v', 't'].every((k) => chaves.includes(k))", '', 'com 4 chaves proprias e nome errado falta um de c,r,v,t: o campo chega undefined e falha na checagem de tipo'],
  ['revisor-maximo-sem-own', "autor < 0 && own(hist, 'autorTierMax')", 'autor < 0', 'a entrada e dado puro (so chaves proprias): tierIdx(undefined) vale -1 como a ausencia'],
  ['revisor-sem-piso-no-papel', "if (tierIdx(piso) < 2) erros.push(`role_floors.${r}: papel revisor sem piso em role_floors ou com piso abaixo de T2`);", 'if (false) erros.push();'],
  ['politica-revisor-piso-T2', 'if (tierIdx(piso) < 2) erros.push(`role_floors.${r}', 'if (tierIdx(piso) < 1) erros.push(`role_floors.${r}'],
  // rodada 4
  ['relogio-minimo-zero', 'now >= AGORA_MIN', 'now >= 0'],
  ['relogio-minimo-exclusivo', 'now >= AGORA_MIN', 'now > AGORA_MIN'],
  ['relogio-sem-maximo', ' && now <= AGORA_MAX', ''],
  ['relogio-nao-inteiro', 'Number.isInteger(now) && ', ''],
  ['relogio-aceita-texto', "(Number.isInteger(now) && now >= AGORA_MIN && now <= AGORA_MAX ? now : NaN)", "(Number.isInteger(Number(now)) && Number(now) >= AGORA_MIN && Number(now) <= AGORA_MAX ? Number(now) : NaN)"],
  ['iso-sem-ida-e-volta', 'return new Date(t).toISOString() === `${texto.slice(0, 19)}.000Z` ? t : NaN;', 'return t;'],
  ['iso-sem-checar-nan', 'if (Number.isNaN(t)) return NaN;', ''],
  ['concede-conta-zeros', 'n >= 1 && n < 2 && !h.concedidas.has(k)', 'n >= 0 && n < 2 && !h.concedidas.has(k)'],
  ['concede-duas-falhas-competem', 'n >= 1 && n < 2 && !h.concedidas.has(k)', 'n >= 1 && !h.concedidas.has(k)'],
  ['concede-sem-excluir-registradas', ' && !h.concedidas.has(k)) novas.push(k);', ') novas.push(k);'],
  ['concede-nao-numero', "typeof n === 'number' && n >= 1 && n < 2", 'n >= 1 && n < 2'],
  ['dado-puro-entrada', "if (inp === IMPURO) return semDecisao('entrada_invalida');", ''],
  ['dado-puro-entrada-primitiva', 'if (isObj(input)) {', 'if (true) {'],
  ['dado-puro-catch-politica', "return semDecisao('politica_invalida'); // Proxy que lanca ou revogado", "throw new Error('politica');"],
  ['dado-puro-catch-entrada', "  } catch {\n    return semDecisao('entrada_invalida');\n  }", "  } catch (e) {\n    throw e;\n  }"],
  ['dado-puro-catch-validate', "return { ok: false, erros: ['politica: leitura falhou (Proxy que lanca ou revogado)'] };", "throw new Error('validate');"],
  ['dado-puro-sem-contador-nos', ' || ++ctx.nos > MAX_NOS', ''],
  ['dado-puro-nos-maior', 'const MAX_NOS = 100000;', 'const MAX_NOS = 100000000;'],
  ['dado-puro-sem-chave-direta-objeto', 'if (ctx.chave !== undefined && !lista && Object.hasOwn(v, ctx.chave) && chaves.indexOf(ctx.chave) >= teto) extra = ctx.chave;', ''],
  ['dado-puro-sem-chave-direta-lista', 'if (ctx.chave !== undefined && lista && v.indexOf(ctx.chave) >= teto) extra = ctx.chave;', ''],
  ['dado-puro-chave-longa-objeto', 'if (truncavel && !lista && k.length > MAX_CHAVE) continue;', ''],
  ['dado-puro-chave-longa-lista', "if (truncavel && lista && typeof d.value === 'string' && d.value.length > MAX_CHAVE) continue;", ''],
  ['politica-impura-segue', 'return validarCopia(copia, opts);', 'return validarCopia(policy, opts);'],
  ['papel-sem-dobra', 'const norm = dobrar(s.normalize(', 'const norm = ((x) => x)(s.normalize('],
  ['papel-sem-namespace', "return norm.slice(norm.lastIndexOf(':') + 1).trim();", 'return norm;'],
  ['papel-sem-acento', "    .normalize('NFD').replace(MARCAS_RE, '');", '    ;'],
  ['papeis-sem-maior', 'if (!m.has(n) || valor(v) > valor(m.get(n))) m.set(n, v);', 'm.set(n, v);'],
  ['papeis-sem-cache', 'let m = PAPEIS.get(mapa);', 'let m;'],
  ['politica-size-caminhos-piso', 'if (tierIdx(policy.size.caminhos?.piso) < 2)', 'if (tierIdx(policy.size.caminhos?.piso) < 1)'],
  // rodada 5
  ['papel-sem-nfkc', ".normalize('NFKC').replace(IGNORAVEL_RE, '').replace(/\\s+/g, ' ')", ".replace(IGNORAVEL_RE, '').replace(/\\s+/g, ' ')"],
  ['papel-sem-ignoraveis', ".replace(IGNORAVEL_RE, '').replace(/\\s+/g, ' ')", ".replace(/\\s+/g, ' ')"],
  ['busca-sem-nfkc', ".replace(EXPANSIVO_RE, ' ').normalize('NFKC')", ".replace(EXPANSIVO_RE, ' ')"],
  ['busca-sem-ignoraveis', "texto.replace(IGNORAVEL_RE, '').replace(EXPANSIVO_RE", "texto.replace(EXPANSIVO_RE"],
  ['busca-ascii-sem-minuscula', 'return ` ${texto.toLowerCase().replace(NAO_ALFANUM_ASCII_RE', 'return ` ${texto.replace(NAO_ALFANUM_ASCII_RE'],
  ['busca-ascii-forcado', 'if (ASCII_RE.test(texto)) return ', 'if (true) return '],
  ['busca-sem-nfd', "t = t.normalize('NFD').replace(MARCAS_RE, '');", ''],
  ['busca-sem-marcas', "t = t.normalize('NFD').replace(MARCAS_RE, '');", "t = t.normalize('NFD');"],
  ['busca-sem-limite-de-expansao', ".replace(EXPANSIVO_RE, ' ')", ''],
  ['busca-sem-dobra', '(c) => DOBRA.get(c) ?? c', '(c) => c'],
  ['busca-nao-alfanum-sem-espaco', 't.replace(NAO_ALFANUM_RE, \' \')', 't.replace(NAO_ALFANUM_RE, \'\')'],
  ['busca-sem-fronteira-inicial', 'regex: new RegExp(` (?:${normais.join(\'|\')})`)', 'regex: new RegExp(`(?:${normais.join(\'|\')})`)'],
  ['busca-com-fronteira-final', 'regex: new RegExp(` (?:${normais.join(\'|\')})`)', 'regex: new RegExp(` (?:${normais.join(\'|\')}) `)'],
  ['caminhos-igual-vale', 'contaCaminhos(analise, caminhos.acima_de) > caminhos.acima_de', 'contaCaminhos(analise, caminhos.acima_de) >= caminhos.acima_de'],
  ['caminho-sem-parada', 'if (vistos.size > limite) break;', '', 'so poda trabalho: a contagem acima do limiar ja decide'],
  ['analise-sem-corte', 'const analise = texto.length > teto ? texto.slice(0, teto) : texto;', 'const analise = texto;', 'equivalente SO depois da correcao do validador (acima_do_teto.piso >= caminhos.piso): acima do teto o piso ja cobre risco e caminhos; prova diferencial com politica caminhos T4/acima T4 e 20 caminhos depois do teto'],
  ['critica-sem-nome', ' || temRisco(k, risco)', ''],
  ['teto-padrao-menor', 'const PROMPT_MAX_PADRAO = 262144;', 'const PROMPT_MAX_PADRAO = 524288;'],
  ['teto-maximo-maior', 'const PROMPT_MAX_TETO = 1048576;', 'const PROMPT_MAX_TETO = 4194304;'],
  ['politica-limites-faixa', 'ehInteiroEm(teto, 1024, PROMPT_MAX_TETO)', 'ehInteiroEm(teto, 0, Number.MAX_SAFE_INTEGER)'],
  ['valid-until-teto-absoluto', 'if (validUntil > VALID_UNTIL_TETO) erros.push', 'if (false) erros.push'],
  ['valid-until-teto-2100', "const VALID_UNTIL_TETO = Date.parse('2030-01-01T00:00:00Z');", "const VALID_UNTIL_TETO = Date.parse('2100-01-01T00:00:00Z');"],
  ['concede-vagas-ignora-registradas', 'const vagas = max - consumo;', 'const vagas = max;'],
  ['concede-consumo-conta-2falhas', "if (!(typeof h.falhasPorChave[k] === 'number' && h.falhasPorChave[k] >= 2)) consumo++;", 'consumo++;'],
  ['repeticao-so-depois-de-2', "(typeof falhas === 'number' && falhas >= 1)", "(typeof falhas === 'number' && falhas > 1)"],
  ['registrada-sem-falha-nao-sobe', '(chave !== null && concedidas.has(chave)) || ', ''],

  // rodada 6
  ['politica-acima-teto-t3', 'tierIdx(policy.size.acima_do_teto.piso) < Math.max(3, tierIdx(policy.risk_surface?.piso), tierIdx(policy.size.caminhos?.piso))', 'tierIdx(policy.size.acima_do_teto.piso) < 2'],
  ['politica-acima-teto-risco', 'Math.max(3, tierIdx(policy.risk_surface?.piso), tierIdx(policy.size.caminhos?.piso))', 'Math.max(3, tierIdx(policy.size.caminhos?.piso))'],
  ['politica-acima-teto-caminhos', 'Math.max(3, tierIdx(policy.risk_surface?.piso), tierIdx(policy.size.caminhos?.piso))', 'Math.max(3, tierIdx(policy.risk_surface?.piso))'],
  ['capped-sem-teto', "      capped = true;\n      if (!ctx.truncado) add('teto_por_fluxo');", "      if (!ctx.truncado) add('teto_por_fluxo');"],
  ['teto-por-fluxo-com-truncado', "if (!ctx.truncado) add('teto_por_fluxo');", "add('teto_por_fluxo');"],
  ['truncado-lista-sem-aviso', "if (ctx.truncadoLista) add('history_truncado_lista');", ''],
  ['truncado-lista-sempre', 'if (lista) ctx.truncadoLista = true;', 'ctx.truncadoLista = true;'],
  // ficha e parse
  ['ficha-teto-2049', 'const MAX_LINHA_BYTES = 2048;', 'const MAX_LINHA_BYTES = 4096;'],
  ['ficha-teto-2047', 'const MAX_LINHA_BYTES = 2048;', 'const MAX_LINHA_BYTES = 2047;'],
  ['ficha-so-bytes', 'linha.length > MAX_LINHA_BYTES || new TextEncoder().encode(linha).length > MAX_LINHA_BYTES',
    'new TextEncoder().encode(linha).length > MAX_LINHA_BYTES', 'bytes >= caracteres: a segunda condicao implica a primeira'],
  ['ficha-so-chars', 'linha.length > MAX_LINHA_BYTES || new TextEncoder().encode(linha).length > MAX_LINHA_BYTES',
    'linha.length > MAX_LINHA_BYTES'],
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
  ['papel-sem-colapso', ".replace(/\\s+/g, ' ')", ''],
  ['caminho-sem-barra-inicial', "tok.startsWith('/') || ", ''],
  ['caminho-sem-til', "tok.startsWith('~') || ", ''],
  ['caminho-sem-extensao', 'if (EXTENSAO_RE.test(tok)) return true;', ''],
  ['caminho-duas-barras', "tok.split('/').length - 1 >= 2", "tok.split('/').length - 1 >= 3"],
  ['caminho-sem-teto-de-token', 'tok.length > MAX_TOKEN_CAMINHO || ', ''],
  ['caminho-nao-distintos', 'vistos.add(tok);', 'vistos.add(tok + vistos.size);'],
  // piso
  ['piso-nao-sobe', 'if (idx > floor) floor = idx;', 'if (idx < floor) floor = idx;'],
  ['papel-so-role', 'const nomes = [papel(inp.role), papel(inp.subagentType)];', 'const nomes = [papel(inp.role)];'],
  ['papel-so-subagente', 'const nomes = [papel(inp.role), papel(inp.subagentType)];', 'const nomes = [papel(inp.subagentType)];'],
  ['revisor-sempre', 'nomes.some((n) => revisores.has(n))', 'true'],
  ['revisor-sem-maximo', "if (autor < 0 && own(hist, 'autorTierMax')) autor = tierIdx(hist.autorTierMax);", ''],
  ['revisor-maximo-sempre', "if (autor < 0 && own(hist, 'autorTierMax')) autor", "if (own(hist, 'autorTierMax')) autor"],
  ['ficha-ignora-piso', 'let tier = Math.max(daFicha, floor);', 'let tier = daFicha;'],
  ['subclassificacao-muda', "if (ficha && daFicha < floor) add('ficha_abaixo_do_piso');", ''],
  // repeticao e teto
  ['capped-sem-repeticao-multipla', 'if (tier >= TOPO || falhas >= 2) capped = true;', 'if (tier >= TOPO) capped = true;'],
  ['capped-sem-topo', 'if (tier >= TOPO || falhas >= 2) capped = true;', 'if (falhas >= 2) capped = true;'],
  ['repeticao-sem-teto-topo', 'tier = Math.min(TOPO, tier + 1);', 'tier = tier + 1;'],
  ['repeticao-nao-sobe', 'tier = Math.min(TOPO, tier + 1);', 'tier = tier;'],
  ['repeticao-piso-fixo', 'floor = Math.min(TOPO, floor + 1);', 'floor = Math.min(TOPO, floor);'],
  ['tier-base-depois-do-ritmo', 'tier_base: TIER_NAMES[tierBase],', 'tier_base: TIER_NAMES[tier],'],
  // ritmo
  ['ritmo-desce-sem-verificar-v', "ficha.v === 'sim' && !repetida", "ficha.v !== 'nao' && !repetida"],
  ['ritmo-desce-apos-falha', "ficha.v === 'sim' && !repetida", "ficha.v === 'sim'"],
  ['ritmo-desce-abaixo-do-piso', 'alvo >= floor && ', ''],
  ['ritmo-desce-p-nao-medido', "estadoDoNivel(policyCopia, nomes, alvo) === 'medido_ok'", "estadoDoNivel(policyCopia, nomes, alvo) !== 'reprovado'"],
  ['ritmo-desce-sem-qualidade', " && estadoDoNivel(policyCopia, nomes, alvo) === 'medido_ok'", ''],
  ['ritmo-abaixo-desce-tambem', "if (estado === 'acima' && ficha && ficha.v === 'sim' && !repetida) {",
    "if (estado !== 'dentro' && ficha && ficha.v === 'sim' && !repetida) {"],
  ['ritmo-sobe-sem-verificar-v', "estado === 'abaixo' && ficha && ficha.v === 'nao' && tier < TOPO", "estado === 'abaixo' && ficha && ficha.v !== 'sim' && tier < TOPO"],
  ['ritmo-sobe-sem-teto', "estado === 'abaixo' && ficha && ficha.v === 'nao' && tier < TOPO", "estado === 'abaixo' && ficha && ficha.v === 'nao'"],
  ['ritmo-sobe-dois', "tier += 1;\n    add('ritmo_sobe');", "tier += 2;\n    add('ritmo_sobe');"],
  ['ritmo-estado-livre', 'isObj(inp.pace) && ESTADOS_RITMO.includes(inp.pace.estado) ? inp.pace.estado', 'isObj(inp.pace) ? inp.pace.estado',
    'estado fora do enum nao casa nenhum dos dois ramos: o resultado e igual ao de dentro'],
  // qualidade (R12)
  ['qualidade-sem-elegivel-aplica', 'const semElegivel = tier > TOPO;', 'const semElegivel = false;'],
  ['qualidade-sem-elegivel-nao-volta', '    tier = tierBase;', ''],
  ['qualidade-sem-aviso-final', "add('sem_nivel_elegivel');", ''],
  ['qualidade-modo-efetivo', "const modoEfetivo = mode === 'enforce' && semElegivel ? 'shadow' : mode;", 'const modoEfetivo = mode;'],
  ['qualidade-aplicar-por-mode', "aplicar: modoEfetivo === 'enforce',", "aplicar: mode === 'enforce',"],
  ['qualidade-sem-aviso-nao-medido', "if (estadoNivel === 'nao_medido') add('nivel_nao_medido');", ''],
  ['qualidade-sem-piso-de-papel', 'exigida = Math.max(exigida, v);', 'exigida = exigida;'],
  ['qualidade-igual-nao-vale', 'return q.aprovacao_medida >= exigenciaDeAprovacao(policy, nomes)', 'return q.aprovacao_medida > exigenciaDeAprovacao(policy, nomes)'],
  // modo, relogio e validade
  ['modo-vencida-promove-off', "if (mode !== 'off') mode = validade.degradaPara;", 'mode = validade.degradaPara;'],
  ['modo-aplicar-shadow', "aplicar: modoEfetivo === 'enforce',", "aplicar: modoEfetivo !== 'off',"],
  ['modo-invalida-nao-off', "mode: 'off', modo_efetivo: 'off', aplicar: false", "mode: 'shadow', modo_efetivo: 'shadow', aplicar: false"],
  ['validade-igual-vale', "return agora >= Date.parse(validUntil) ? 'vencida' : null;", "return agora > Date.parse(validUntil) ? 'vencida' : null;"],
  ['validade-sem-relogio-vale', "if (Number.isNaN(agora)) return 'sem_relogio_valido';", ''],
  ['validade-sem-aviso-vencida', "if (situacao === 'vencida') add('politica_vencida');", ''],
  ['validade-sem-aviso-relogio', "if (situacao === 'sem_relogio_valido') add('sem_relogio_valido');", ''],
  ['relogio-minimo-menor', 'const AGORA_MIN = 1.6e12;', 'const AGORA_MIN = 1.5e12;'],
  ['relogio-maximo-maior', 'const AGORA_MAX = 4.1e12;', 'const AGORA_MAX = 4.2e12;'],
  ['horizonte-inclusivo', 'validUntil - agora > HORIZONTE_MS', 'validUntil - agora >= HORIZONTE_MS'],
  ['horizonte-maior', 'const HORIZONTE_MS = 400 * 86400000;', 'const HORIZONTE_MS = 401 * 86400000;'],
  // validador
  ['alias-por-prefixo', '!ALIAS_PERMITIDOS.includes(m)', '!ALIAS_PERMITIDOS.some((a) => String(m).startsWith(a))'],
  ['tier-fora-da-allowlist', 'modelo < 0 || !allowOk.includes(x.model)', 'modelo < 0'],
  ['custo-so-esforco', 'const custo = modelo * EFFORTS.length + esforco;', 'const custo = esforco;'],
  ['custo-so-modelo', 'const custo = modelo * EFFORTS.length + esforco;', 'const custo = modelo;'],
  ['politica-schema-version', 'policy.schema_version !== 1', 'false'],
  ['politica-version', 'if (!ehTexto(policy.version, 64)) erros.push', 'if (false) erros.push'],
  ['politica-mode', 'if (!MODES.includes(policy.mode)) erros.push', 'if (false) erros.push'],
  ['politica-effort', 'if (esforco < 0) erros.push', 'if (false) erros.push'],
  ['politica-complexidade', 'if (tierIdx(complexidade[k]) < 0) erros.push', 'if (false) erros.push'],
  ['politica-risco', 'if (tierIdx(risco[k]) < 0) erros.push', 'if (false) erros.push'],
  ['politica-role-floors-nivel', 'if (!ehTexto(k, 64) || tierIdx(v) < 0) erros.push', 'if (!ehTexto(k, 64)) erros.push'],
  ['politica-role-floors-chave', 'if (!ehTexto(k, 64) || tierIdx(v) < 0) erros.push', 'if (tierIdx(v) < 0) erros.push'],
  ['politica-words-demais', ' || w.length > MAX_PALAVRAS', ''],
  ['politica-nota', 'if (!ehTexto(policy.risk_surface.nota, 400)) erros.push', 'if (false) erros.push'],
  ['politica-limiar-acima', 'if (!ehInteiroEm(l.acima_de, 1, Number.MAX_SAFE_INTEGER)) erros.push', 'if (false) erros.push'],
  ['politica-pace-ordem', '|| !(a < b)', ''],
  ['politica-pace-numeros', '!ehNumeroEm(a, -1000, 1000) || !ehNumeroEm(b, -1000, 1000) || ', ''],
  ['politica-escalation', 'if (!ehInteiroEm(policy.escalation.max_por_fluxo, 0, 1000)) erros.push', 'if (false) erros.push'],
  ['politica-aprovacao', 'if (!semAprov && !ehNumeroEm(q.aprovacao_medida, 0, 1)) erros.push', 'if (false) erros.push'],
  ['politica-n', 'if (q.n !== null && !ehInteiroEm(q.n, 1, Number.MAX_SAFE_INTEGER)) erros.push', 'if (false) erros.push'],
  ['politica-n-consistente', 'if (semAprov !== (q.n === null)) erros.push', 'if (false) erros.push'],
  ['politica-fonte', 'if (!ehTexto(q.fonte, 400)) erros.push', 'if (false) erros.push'],
  ['politica-chave-extra', 'for (const k of Object.keys(obj)) if (!esperadas.includes(k) && !opcionais.includes(k)) erros.push', 'for (const k of Object.keys(obj)) if (false) erros.push'],
  ['politica-chave-opcional-qualquer', '!esperadas.includes(k) && !opcionais.includes(k)', '!esperadas.includes(k) && false'],
  ['politica-inteiro', 'ehNumeroEm(x, min, max) && Number.isInteger(x)', 'ehNumeroEm(x, min, max)'],
  ['politica-denso', 'const denso = (a) => Array.isArray(a) && Object.keys(a).length === a.length;', 'const denso = (a) => Array.isArray(a);'],
];

function copiaDe(trabalho, engineTexto) {
  const plug = path.join(trabalho, 'claude-plugins/plugins/tollens-router');
  mkdirSync(path.join(plug, 'tests'), { recursive: true });
  mkdirSync(path.join(trabalho, 'tests/unit'), { recursive: true });
  cpSync(path.join(PLUGIN, 'router-policy.json'), path.join(plug, 'router-policy.json'));
  cpSync(path.join(PLUGIN, 'CONTRATO.md'), path.join(plug, 'CONTRATO.md'));
  cpSync(path.join(PLUGIN, 'policy.schema.json'), path.join(plug, 'policy.schema.json'));
  cpSync(path.join(PLUGIN, 'tests/corpus.mjs'), path.join(plug, 'tests/corpus.mjs'));
  cpSync(path.join(PLUGIN, 'tests/propriedades.mjs'), path.join(plug, 'tests/propriedades.mjs'));
  cpSync(TESTE, path.join(trabalho, 'tests/unit/router-engine.test.mjs'));
  writeFileSync(path.join(plug, 'engine.mjs'), engineTexto);
  return path.join(plug, 'engine.mjs');
}

// `completo` falso pula os testes de linearidade, de papeis e de validador x schema (lentos); so os mutantes que sobrevivem sem ele rodam a suite inteira.
function roda(trabalho, completo = true) {
  const pula = completo ? [] : ['--test-skip-pattern=J1 linearidade', '--test-skip-pattern=J1 papeis normalizados', '--test-skip-pattern=J8 validador x schema', '--test-skip-pattern=J1 metamorfico'];
  const r = spawnSync(process.execPath, ['--test', '--test-reporter=tap', ...pula, '--experimental-test-isolation=none', path.join(trabalho, 'tests/unit/router-engine.test.mjs')],
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
  `${'a '.repeat(131080)}${Array.from({ length: 20 }, (_, i) => `/p${i}/f.js`).join(' ')} fim`, // 20 caminhos so depois do teto de 256 KiB
  `${'z'.repeat(70)} producao ${'\u200b'.repeat(80)}token`,
];

const semErros = (v) => ({ ok: v.ok, degradaPara: v.degradaPara });

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
      [() => semErros(orig.validatePolicy(a.value.policy, { now: a.value.input?.now })), () => semErros(mut.validatePolicy(b.value.policy, { now: b.value.input?.now }))],
      [() => orig.parseRota(prompt), () => mut.parseRota(b.value.input?.prompt)],
      [() => orig.stripRota(prompt), () => mut.stripRota(b.value.input?.prompt)],
    ];
    for (const [fa, fb] of pares) if (resultado(fa) !== resultado(fb)) divergencias++;
  }
  for (const extra of EXTRAS) {
    const t4 = structuredClone(POLITICA);
    t4.size.caminhos.piso = 'T4';
    t4.size.acima_do_teto.piso = 'T4';
    for (const politica of [POLITICA, { ...structuredClone(POLITICA), mode: 'enforce' }, t4]) {
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

if (process.argv.includes('--verificar')) {
  const ruins = M.filter(([, de]) => ENGINE.split(de).length - 1 !== 1).map(([id, de]) => `${id} (ocorrencias=${ENGINE.split(de).length - 1})`);
  console.log(ruins.length ? `INSTRUMENTO: ${ruins.join(' ')}` : `ok: ${M.length} mutantes com trecho unico`);
  process.exit(ruins.length ? 1 : 0);
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
    for (const [indice, [id, de, para, equiv]] of M.entries()) {
      if (SO && !SO.includes(id)) continue;
      if (FATIA && indice % FATIA[1] !== FATIA[0]) continue;
      const ocorrencias = ENGINE.split(de).length - 1;
      if (ocorrencias !== 1) {
        instrumento.push(`${id} (ocorrencias=${ocorrencias})`);
        continue;
      }
      const dir = path.join(base, id);
      const arquivo = copiaDe(dir, ENGINE.replace(de, () => para));
      let r = roda(dir, false);
      if (r.status === 0) r = roda(dir, true);
      const soCarga = r.reprovados.length > 0 && r.reprovados.every((n) => SENSIVEL_A_CARGA.test(n));
      // Mutante declarado equivalente que so cai em teste de tempo/CPU nao conta como morto: vai a prova por execucao.
      const morto = mortoConfirmado(dir, r) && !(soCarga && equiv);
      if (morto) {
        mortos.push(id);
        const mata = r.reprovados.length > 0 ? r.reprovados[0].slice(0, 70) : r.timeout ? 'prazo de 90 s estourado' : 'a suite nao carregou ou terminou com erro';
        console.log(`MORTO | ${id} | teste: ${mata}${r.reprovados.length > 1 ? ` (+${r.reprovados.length - 1})` : ''}${soCarga ? ' [so teste de tempo/CPU, falha repetida]' : ''}`);
      } else if (equiv) {
        const d = await diferencial(arquivo);
        if (d.divergencias === 0) {
          confirmados.push(id);
          console.log(`EQUIVALENTE | ${id} | suite verde; ${d.casosN} comparacoes com 0 divergencias; ${equiv}`);
        } else {
          vivos.push(id);
          console.log(`VIVO | ${id} | equivalencia REFUTADA: ${d.divergencias} divergencias em ${d.casosN} comparacoes`);
        }
      } else {
        vivos.push(id);
        console.log(`VIVO | ${id} | suite verde com o mutante`);
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
