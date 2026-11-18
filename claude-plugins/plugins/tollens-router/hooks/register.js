// Mod tollens-router (R2): liga o motor puro (../engine.mjs) ao Claude Code. Protocolo e limites em
// CONTRATO.md. Todo uso de `$` fica neste arquivo (o analisador estatico nao segue `$` para outros).
//
// Modos (da politica): `shadow` e `off` NAO alteram a chamada; so `enforce` aplica model e effort.
// Falha aberta: qualquer excecao deixa a chamada inalterada e grava uma linha de erro sem conteudo.
// Sem `.catch` nos hooks de proposito: o runtime pula um hook que lanca ou estoura o prazo e a chamada
// segue sem o mod, que e o fail-open desejado.
//
// CAMINHOS FIXOS em producao: politica, sentinela e managed-settings sao constantes (nenhum vem de variavel
// de ambiente nem de settings do repositorio). So o diretorio do ledger vem de HOME (${HOME}/.claude/logs,
// via `$.env`); o nome do arquivo e sempre proprio do mod. `criarMod(config)` existe so para teste, com
// injecao explicita; o `register` exportado usa apenas os padroes fixos.
//
// O mod NAO altera variavel de ambiente. Para agente de workflow ele define `model` em `agent.spawn`.
// NAO VERIFICADO: se o runtime respeita o `model` do hook quando CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL esta
// definida (o d.ts diz que o modelo forcado pela sessao vence o do hook).
import { decide, normalizarPapel, parseRota, stripRota } from '../engine.mjs';
import {
  ALIASES, NOTA_FALHA, nivelIdx, aparar, autorTierMax, calcularRitmo, derivarChave, ehDoLedger, estadoDoRitmo, hex16, linhaDeLedger,
  lerManaged, melhorPermitido, modeloPermitido, nomeDoErro, normalizarEstado, podarSessoes, rankModelo, ritmoVigente, sinalDeFalha,
} from './core.js';

const PADRAO = Object.freeze({
  politica: '/etc/claude-code/router-policy.json',
  sentinela: '/etc/claude-code/router-off',
  managed: '/etc/claude-code/managed-settings.json',
  ledgerDir: null, // null: ${HOME}/.claude/logs
});
const ROTACAO_BYTES = 2097152;
const GERACOES = 3;
const EFFORTS = ['low', 'medium', 'high', 'xhigh', 'max'];

function novoEstado() {
  return { ritmo: null, decididos: new Set(), avisos: new Set(), filaEstado: Promise.resolve(), filaLedger: Promise.resolve(), managedCache: null };
}

function serializar(est, fila, fn) {
  const p = est[fila].then(fn);
  est[fila] = p.then(() => undefined, () => undefined);
  return p;
}

function lembrar(est, id) {
  if (typeof id !== 'string' || id === '') return;
  est.decididos.add(id);
  if (est.decididos.size > 500) est.decididos.delete(est.decididos.values().next().value);
}

// Aviso ao operador, uma vez por tipo e por instancia (sessao).
function avisar($, est, tipo, id, texto) {
  if (est.avisos.has(tipo)) return;
  est.avisos.add(tipo);
  try {
    if (typeof id === 'string' && id !== '') $.ui.notice(id, texto);
  } catch {
    // aviso e cortesia: a chamada segue
  }
}

async function lerPolitica($, caminho) {
  let texto;
  try {
    texto = await $.fs.read(caminho);
  } catch {
    return { policy: null, motivo: 'politica_ausente' };
  }
  if (typeof texto !== 'string' || texto.length > 1048576) return { policy: null, motivo: 'politica_ilegivel' };
  try {
    return { policy: JSON.parse(texto), motivo: null };
  } catch {
    return { policy: null, motivo: 'politica_ilegivel' };
  }
}

// managed-settings: somente leitura, cache de 30 s por instancia (a releitura a cada decisao nao compensa).
async function lerManagedSettings($, cfg, est, agora) {
  const c = est.managedCache;
  if (c && agora >= c.ts && agora - c.ts < 30000) return c.valor;
  let valor = null; // ilegivel: sem restricao conhecida (falha aberta)
  try {
    valor = lerManaged(await $.fs.read(cfg.managed));
  } catch {
    valor = null;
  }
  est.managedCache = { ts: agora, valor };
  return valor;
}

// Ledger por SESSAO: <dir>/router-ledger-<16 hex do sha256 do session_id>.jsonl, rotacao em 3 geracoes
// (.1 a .3). So escreve em arquivo vazio ou cuja primeira linha seja de ledger; nunca regrava arquivo alheio.
// $.fs nao tem modo de arquivo: o ledger nao e 0600 (umask do usuario). Nunca lanca.
async function gravarLedger($, cfg, est, sess, linha) {
  try {
    let dir = cfg.ledgerDir;
    if (!dir) {
      const home = await $.env.get('HOME');
      dir = typeof home === 'string' && home.startsWith('/') ? `${home}/.claude/logs` : null;
    }
    if (!dir) return;
    const arq = `${dir}/router-ledger-${typeof sess === 'string' && sess !== '' ? await hex16(sess) : 'sem-sessao'}.jsonl`;
    await serializar(est, 'filaLedger', async () => {
      // null = o arquivo existe e a leitura falhou (erro transitorio): NAO escrever, para nao regravar o
      // ledger da sessao com conteudo vazio. Ausente (ou existencia desconhecida e leitura falha) = ''.
      // O mod nunca grava arquivo vazio: leitura vazia de arquivo que existe e escrita concorrente em curso
      // (truncada e ainda nao gravada), nao arquivo vazio valido; tambem vira null.
      const ler = async (p) => {
        let existe = null;
        try {
          existe = await $.fs.exists(p);
        } catch {
          existe = null;
        }
        if (existe === false) return '';
        try {
          const t = await $.fs.read(p);
          return existe === true && t === '' ? null : t;
        } catch {
          return existe === true ? null : '';
        }
      };
      const erro = async () => {
        try {
          await $.store.set(`router.ledger_erro.${arq.slice(arq.lastIndexOf('-') + 1, arq.lastIndexOf('.'))}`, { ts: Date.now() });
        } catch {
          // sem onde registrar: a chamada segue
        }
      };
      let atual = await ler(arq);
      if (atual === null) return erro();
      if (!ehDoLedger(atual)) return;
      if (atual.length > ROTACAO_BYTES) {
        const geracoes = [];
        for (let g = 1; g <= GERACOES; g++) geracoes.push(await ler(`${arq}.${g}`));
        if (!geracoes.every((g) => g !== null && ehDoLedger(g))) return erro();
        // desloca so o prefixo contiguo de geracoes ocupadas (.1 a .n) para .2 a .n+1; uma lacuna nao
        // duplica conteudo nem sobrescreve geracao mais antiga
        let n = 0;
        while (n < GERACOES && geracoes[n] !== '') n++;
        for (let g = Math.min(n + 1, GERACOES); g >= 2; g--) await $.fs.write(`${arq}.${g}`, geracoes[g - 2]);
        await $.fs.write(`${arq}.1`, atual);
        atual = '';
      }
      await $.fs.write(arq, `${atual}${linha}\n`);
    });
  } catch {
    // sem ledger nao ha o que registrar; a chamada segue
  }
}

async function sessaoDe($) {
  try {
    const id = await $.session.id();
    return typeof id === 'string' && id !== '' ? id : null;
  } catch {
    return null;
  }
}

async function ledgerErro($, cfg, est, evento, ids, err) {
  let ts = null;
  try {
    ts = new Date(await $.clock.now()).toISOString();
  } catch {
    ts = null;
  }
  const sess = await sessaoDe($);
  await gravarLedger($, cfg, est, sess, linhaDeLedger({
    ts, evento, session_id: sess, tool_use_id: ids.tool_use_id, agent_type: ids.subagentType, role: ids.subagentType, erro: nomeDoErro(err),
  }));
}

const ehRevisor = (policy, papel) => {
  const alvo = normalizarPapel(papel);
  return alvo !== '' && Array.isArray(policy && policy.reviewer_roles) && policy.reviewer_roles.some((r) => normalizarPapel(r) === alvo);
};

// Indice das ultimas 50 sessoes no store. O carimbo e de ATIVIDADE: refrescado em toda chamada ativa (decisao
// e registro de falha; no maximo uma escrita do indice por hora); so sessao inativa ha 14 dias ou mais e as
// excedentes sao podadas.
async function registrarSessao($, sess, agora) {
  const indice = await $.store.get('router.indice');
  const atual = Array.isArray(indice) ? indice.find((x) => Array.isArray(x) && x[0] === sess) : undefined;
  if (atual && agora >= atual[1] && agora - atual[1] < 3600000) return;
  const { indice: novo, remover } = podarSessoes(indice, sess, agora);
  await $.store.set('router.indice', novo);
  // remocao depois da gravacao e sem propagar: falha de delete deixa estado orfao, nunca perde o da chamada
  for (const s of remover) {
    try {
      await $.store.delete(`router.estado.${s}`);
    } catch {
      // estado orfao de sessao ja fora do indice
    }
  }
}

// Decide uma delegacao. Persiste o estado ANTES de devolver (protocolo d), em qualquer modo. Falha de
// store.set nao derruba o roteamento: vira o motivo `persistencia_falhou`.
async function decidir($, cfg, est, c) {
  const agora = await $.clock.now();
  const sess = await sessaoDe($);
  const base = {
    ts: new Date(agora).toISOString(), evento: c.evento, session_id: sess, tool_use_id: c.tool_use_id,
    agent_type: c.subagentType, role: c.subagentType,
  };
  if (await $.fs.exists(PADRAO.sentinela) || (cfg.sentinela !== PADRAO.sentinela && await $.fs.exists(cfg.sentinela))) {
    return { off: true, sess, linha: { ...base, mode: 'off', modo_efetivo: 'off', reasons: ['sentinela_off'] } };
  }
  const { policy, motivo } = await lerPolitica($, cfg.politica);
  const managed = await lerManagedSettings($, cfg, est, agora);
  const chave = await derivarChave(c.subagentType, c.descricao);
  const estadoRitmo = estadoDoRitmo(ritmoVigente(est.ritmo, agora), policy);

  return serializar(est, 'filaEstado', async () => {
    const key = `router.estado.${sess}`;
    const estado = normalizarEstado(sess === null ? undefined : await $.store.get(key));
    const { history, aparado } = aparar(estado, chave);
    const max = autorTierMax(estado);
    if (max !== undefined) history.autorTierMax = max;
    const entrada = {
      now: agora, prompt: typeof c.prompt === 'string' ? c.prompt : '', subagentType: typeof c.subagentType === 'string' ? c.subagentType : '',
      role: typeof c.subagentType === 'string' ? c.subagentType : '', history, pace: { estado: estadoRitmo },
    };
    if (chave !== undefined) entrada.chave = chave;
    const d = decide(JSON.parse(JSON.stringify(entrada)), policy);
    const reasons = [...d.reasons];
    if (motivo) reasons.push(motivo);
    if (aparado) reasons.push('history_aparado');
    if (sess === null) reasons.push('sem_sessao_id');

    if (sess !== null && chave !== undefined && d.tier !== null) {
      const antes = JSON.stringify(estado);
      if (d.subida_concedida && !estado.subidasConcedidas.includes(chave)) estado.subidasConcedidas.push(chave);
      if (!ehRevisor(policy, c.subagentType)) estado.autorTierPorChave[chave] = d.tier;
      const critica = reasons.includes('piso_superficie_de_risco') || ehRevisor(policy, c.subagentType);
      if (critica && !estado.chavesCriticas.includes(chave)) estado.chavesCriticas.push(chave);
      try {
        if (JSON.stringify(estado) !== antes) await $.store.set(key, aparar(estado, chave).history);
        await registrarSessao($, sess, agora);
      } catch {
        reasons.push('persistencia_falhou');
        avisar($, est, 'persistencia', c.tool_use_id, 'router: falha ao gravar o estado; a decisao foi aplicada sem persistir');
      }
    }
    const pace = { estado: estadoRitmo, p: ritmoVigente(est.ritmo, agora) };
    return { off: false, sess, policy, managed, d, reasons, chave, base, pace, revisor: ehRevisor(policy, c.subagentType) };
  });
}

function linhaDaDecisao(r, aplicado, ficha) {
  return {
    ...r.base, chave: r.chave, ficha, floor: r.d.floor, tier_base: r.d.tier_base, tier: r.d.tier,
    pedido: { model: r.d.model, effort: r.d.effort }, aplicado, permitido: r.permitido, mode: r.d.mode, modo_efetivo: r.d.modo_efetivo,
    pace: r.pace, capped: r.d.capped, subida_concedida: r.d.subida_concedida, reasons: r.reasons,
  };
}

// Modelo/effort a aplicar numa decisao com `aplicar`: o do motor se a allowlist da politica e o managed o
// permitem; senao o melhor nivel permitido, SO se ele atinge o piso decidido pelo motor (managed_nega_modelo);
// se nenhum nivel permitido atinge o piso (ou o pedido do orquestrador), nada e aplicado (managed_nega_piso).
function escolherAplicacao(r, original) {
  const al = r.policy && Array.isArray(r.policy.model_allowlist) ? r.policy.model_allowlist : [];
  const vazio = { alvo: null, negado: false, semPiso: false, permitido: null };
  if (r.d.aplicar !== true || !ALIASES.includes(r.d.model) || !al.includes(r.d.model)) return vazio;
  if (modeloPermitido(r.d.model, r.managed)) return { ...vazio, alvo: { model: r.d.model, effort: r.d.effort } };
  const melhor = melhorPermitido(r.policy, r.d.tier, undefined, r.managed);
  const alt = melhorPermitido(r.policy, r.d.tier, original, r.managed);
  const permitido = melhor ? { model: melhor.model, effort: melhor.effort } : null;
  if (alt && al.includes(alt.model) && nivelIdx(alt.tier) >= nivelIdx(r.d.floor)) {
    return { ...vazio, alvo: { model: alt.model, effort: alt.effort }, negado: true, permitido };
  }
  return { ...vazio, negado: true, semPiso: true, permitido };
}

async function registrarFalha($, est, r) {
  if (r.sess === null) return;
  await serializar(est, 'filaEstado', async () => {
    const key = `router.estado.${r.sess}`;
    const estado = normalizarEstado(await $.store.get(key));
    estado.falhasPorChave[r.chave] = (estado.falhasPorChave[r.chave] || 0) + 1;
    if (!estado.ordem.includes(r.chave)) estado.ordem.push(r.chave);
    await $.store.set(key, aparar(estado, r.chave).history);
    try {
      await registrarSessao($, r.sess, await $.clock.now());
    } catch {
      // o carimbo e cortesia de retencao: a falha ja foi registrada
    }
  });
}

function fichaDe(prompt) {
  const p = parseRota(prompt);
  return p.ok ? { c: p.ficha.c, r: p.ficha.r, v: p.ficha.v } : null;
}

function instalar(on, cfg) {
  const est = novoEstado();

  on('tool.call', { tool: ['Agent', 'Task'] }, async ($, e, next) => {
    if (e === null || typeof e !== 'object') return next(e);
    const ids = { tool_use_id: e.tool_use_id, subagentType: e.subagent_type };
    let r;
    try {
      r = await decidir($, cfg, est, { evento: 'tool.call', subagentType: e.subagent_type, descricao: e.description, prompt: e.prompt, tool_use_id: e.tool_use_id });
    } catch (err) {
      await ledgerErro($, cfg, est, 'tool.call', ids, err);
      return next(e);
    }
    if (r.off) {
      await gravarLedger($, cfg, est, r.sess, linhaDeLedger(r.linha));
      return next(e);
    }
    lembrar(est, e.tool_use_id);
    let chamada = e;
    let aplicado = null;
    try {
      const ehFork = typeof e.subagent_type === 'string' && e.subagent_type.toLowerCase() === 'fork';
      if (r.d.aplicar && typeof e.prompt === 'string' && !ehFork) {
        const { alvo, negado, semPiso, permitido } = escolherAplicacao(r, e.model);
        r.permitido = permitido;
        if (negado) {
          r.reasons.push(semPiso ? 'managed_nega_piso' : 'managed_nega_modelo');
          avisar($, est, semPiso ? 'managed_piso' : 'managed', e.tool_use_id, semPiso
            ? `router: o managed nega o modelo ${r.d.model} e nenhum nivel permitido atinge o piso; a chamada segue como pedida`
            : `router: o managed nega o modelo ${r.d.model}; aplicado o melhor nivel permitido`);
        }
        // a linha @@ROTA so sai junto com um model aplicado (sem alvo, nada muda na chamada)
        if (alvo !== null) {
          chamada = { ...e, prompt: stripRota(e.prompt), model: alvo.model };
          if (EFFORTS.includes(alvo.effort)) chamada.effort = alvo.effort;
          aplicado = { model: alvo.model, effort: EFFORTS.includes(alvo.effort) ? alvo.effort : null };
        }
      }
      await gravarLedger($, cfg, est, r.sess, linhaDeLedger(linhaDaDecisao(r, aplicado, fichaDe(e.prompt))));
    } catch (err) {
      await ledgerErro($, cfg, est, 'tool.call', ids, err);
      chamada = e;
    }
    const res = await next(chamada);
    try {
      const rr = res !== null && typeof res === 'object' && res.result !== null && typeof res.result === 'object' ? res.result : {};
      await gravarLedger($, cfg, est, r.sess, linhaDeLedger({
        ...r.base, evento: 'efetivo', chave: r.chave, tier: r.d.tier, mode: r.d.mode, modo_efetivo: r.d.modo_efetivo,
        efetivo: rr.resolvedModel ?? null, usados: rr.modelsUsed,
      }));
      const sinal = sinalDeFalha(res, { revisor: r.revisor });
      if (sinal && r.chave !== undefined) {
        await registrarFalha($, est, r);
        await gravarLedger($, cfg, est, r.sess, linhaDeLedger({ ...r.base, evento: 'resultado', chave: r.chave, tier: r.d.tier, mode: r.d.mode, modo_efetivo: r.d.modo_efetivo, sinal }));
        if (r.d.aplicar) return { ...res, context: [...(Array.isArray(res.context) ? res.context : []), NOTA_FALHA] };
      }
    } catch (err) {
      await ledgerErro($, cfg, est, 'tool.call', ids, err);
    }
    return res;
  });

  on('agent.spawn', async ($, e, next) => {
    // Subagente comum e fork: decididos no tool.call. Aqui so workflow, teammate (sem tool.call anterior) e
    // retomada (ignorada: so pode ser recusada). O mod define `model`; nao altera variavel de ambiente.
    if (e === null || typeof e !== 'object') return next(e);
    if (e.resume || e.fork || !(e.workflow || e.isTeammate)) return next(e);
    if (!e.workflow && est.decididos.has(e.tool_use_id)) return next(e);
    const ids = { tool_use_id: e.tool_use_id, subagentType: e.subagentType };
    let r;
    try {
      r = await decidir($, cfg, est, { evento: 'agent.spawn', subagentType: e.subagentType, descricao: e.description, prompt: e.prompt, tool_use_id: e.tool_use_id });
    } catch (err) {
      await ledgerErro($, cfg, est, 'agent.spawn', ids, err);
      return next(e);
    }
    if (r.off) {
      await gravarLedger($, cfg, est, r.sess, linhaDeLedger(r.linha));
      return next(e);
    }
    let chamada = e;
    let aplicado = null;
    try {
      const atual = e.model ?? (await $.env.get('CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL')) ?? e.parentModel;
      const rAtual = rankModelo(atual);
      const { alvo, negado, semPiso, permitido } = escolherAplicacao(r, atual);
      r.permitido = permitido;
      if (negado) {
        r.reasons.push(semPiso ? 'managed_nega_piso' : 'managed_nega_modelo');
        avisar($, est, semPiso ? 'managed_piso' : 'managed', e.tool_use_id, semPiso
          ? `router: o managed nega o modelo ${r.d.model} e nenhum nivel permitido atinge o piso; o agente segue como pedido`
          : `router: o managed nega o modelo ${r.d.model}; aplicado o melhor nivel permitido`);
      }
      // so SOBE: baseline desconhecido (fable, id fora da familia) nunca e tocado
      if (alvo !== null && rAtual >= 0 && rankModelo(alvo.model) > rAtual) {
        chamada = { ...e, model: alvo.model };
        aplicado = { model: alvo.model, effort: null };
      }
      await gravarLedger($, cfg, est, r.sess, linhaDeLedger(linhaDaDecisao(r, aplicado, null)));
    } catch (err) {
      await ledgerErro($, cfg, est, 'agent.spawn', ids, err);
      chamada = e;
    }
    return next(chamada);
  });

  on('session.measure', async ($, e, next) => {
    try {
      const agora = await $.clock.now();
      const p = calcularRitmo(e.rateLimits, agora);
      est.ritmo = p === null ? null : { p, ts: agora };
    } catch {
      est.ritmo = null;
    }
    return next(e);
  });
}

export function register(on) {
  instalar(on, PADRAO);
}

// Fabrica para teste: injecao explicita de caminhos. NAO e usada pelo Claude Code.
export function criarMod(config) {
  const cfg = { ...PADRAO, ...(config || {}) };
  return (on) => instalar(on, cfg);
}
