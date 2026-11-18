// Propriedades do motor de decisao sobre o corpus adversarial deterministico (tests/corpus.mjs).
// Compartilhado pela suite unitaria (corpus pequeno) e por tests/unit/router-engine-fuzz.mjs (2000).
// Verifica: nunca lanca; J1 (tier >= piso); J2 (modelo na allowlist, nunca fable); J3 (aplicar so em
// enforce, entradas congeladas); determinismo; J6 (uma subida por chave); J7 (revisor >= autor); J8.
import assert from 'node:assert/strict';
import { casos } from './corpus.mjs';
import { decide, validatePolicy } from '../engine.mjs';

const T = ['T0', 'T1', 'T2', 'T3', 'T4'];
const idx = (t) => T.indexOf(t);
const plain = (o) => o !== null && typeof o === 'object' && !Array.isArray(o);
const normalizaRole = (r) => (typeof r === 'string' ? r.trim().replace(/\s+/g, ' ').toLowerCase() : '');
const ownTier = (o, k) => (plain(o) && Object.hasOwn(o, k) && T.includes(o[k]) ? idx(o[k]) : -1);

function congelar(o) {
  if (o && typeof o === 'object' && !Object.isFrozen(o)) {
    Object.freeze(o);
    for (const k of Object.keys(o)) congelar(o[k]);
  }
  return o;
}

export function verificar(n, semente, base) {
  const falhas = [];
  const cobertura = { validas: 0, invalidas: 0, aplicadas: 0, ritmo_desce: 0, repeticao: 0, revisor: 0, oraculo: 0 };
  let contador = 0;
  for (const { input, policy, oraculo } of casos(n, semente, base)) {
    contador++;
    congelar(input);
    congelar(policy);
    let d;
    let d2;
    try { d = decide(input, policy); d2 = decide(input, policy); } catch (e) { falhas.push(`lancou: ${e}`); continue; }
    try { assert.deepEqual(d, d2); } catch { falhas.push('nao deterministico'); }
    const v = validatePolicy(policy, { now: plain(input) ? input.now : undefined });
    if (!v.ok) {
      cobertura.invalidas++;
      if (!(d.mode === 'off' && d.modo_efetivo === 'off' && d.aplicar === false && d.model === null)) falhas.push('J8: politica invalida nao virou off');
      continue;
    }
    cobertura.validas++;
    if (!plain(input) || !d.tier) continue;
    if (!T.includes(d.tier)) { falhas.push(`tier invalido ${d.tier}`); continue; }
    if (idx(d.tier) < idx(d.floor)) falhas.push('J1: tier < floor');
    if (oraculo) {
      cobertura.oraculo++;
      if (idx(d.tier) < oraculo.minTier) falhas.push(`J1 (oraculo independente): tier ${d.tier} abaixo de T${oraculo.minTier}: ${oraculo.motivo}`);
    }
    if (!['haiku', 'sonnet', 'opus'].includes(d.model) || /fable/i.test(d.model)) falhas.push(`J2: modelo ${d.model}`);
    if (!policy.model_allowlist.includes(d.model)) falhas.push('J2: fora da allowlist');
    if (d.aplicar !== (d.modo_efetivo === 'enforce')) falhas.push('J3: aplicar incoerente com modo_efetivo');
    if (policy.mode !== 'enforce' && d.aplicar) falhas.push('J3: aplicou fora de enforce');
    if (d.aplicar) cobertura.aplicadas++;
    if (d.reasons.includes('ritmo_desce')) cobertura.ritmo_desce++;
    if (d.reasons.includes('repeticao')) cobertura.repeticao++;
    if (d.reasons.includes('revisor_nao_abaixo_do_autor')) cobertura.revisor++;
    const hist = plain(input.history) ? input.history : {};
    const nomes = [normalizaRole(input.role), normalizaRole(input.subagentType)];
    if (nomes.some((nome) => policy.reviewer_roles.map(normalizaRole).includes(nome))) {
      const chave = typeof input.chave === 'string' && input.chave.length >= 1 ? input.chave : null;
      let autor = chave !== null ? ownTier(hist.autorTierPorChave, chave) : -1;
      if (autor < 0) autor = ownTier(hist, 'autorTierMax');
      if (autor >= 0 && idx(d.tier) < autor) falhas.push('J7: revisor abaixo do autor');
    }
    if (contador % 4 === 0 && typeof input.chave === 'string' && input.chave.length >= 1 && plain(input.history) && plain(input.history.falhasPorChave) && d.tier_base) {
      const comFalhas = (k) => {
        const c = structuredClone(input);
        c.pace = { estado: 'dentro' };
        c.history.falhasPorChave[input.chave] = k;
        return decide(c, policy);
      };
      const k0 = comFalhas(0).tier_base;
      const k2 = comFalhas(2).tier_base;
      const k9 = comFalhas(9).tier_base;
      if (k2 !== k9) falhas.push('J6: mais falhas subiram de novo');
      if (idx(k2) > idx(k0) + 1) falhas.push('J6: subiu mais de um nivel');
    }
  }
  return { falhas, cobertura };
}
