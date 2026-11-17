// Fuzz do MOTOR DE DECISAO fora do agregador (run.sh despacha so *.sh e *.py). Roda o corpus
// adversarial deterministico de 2000 entradas (semente fixa) sobre as propriedades de
// tests/propriedades.mjs e confere contadores minimos de cobertura. Orcamentos absolutos de tempo
// (prompt patologico de 1 MiB, 10 MiB comum, 1 milhao de chaves no historico) sao apenas AVISO:
// dependem da carga da maquina e nao reprovam.
// Exit 0: propriedades e cobertura ok. Exit 1: violacao ou cobertura abaixo do minimo.
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { verificar } from '../../claude-plugins/plugins/tollens-router/tests/propriedades.mjs';
import { decide } from '../../claude-plugins/plugins/tollens-router/engine.mjs';

const DIR = path.join(path.dirname(fileURLToPath(import.meta.url)), '../../claude-plugins/plugins/tollens-router');
const SHIPPED = JSON.parse(readFileSync(path.join(DIR, 'router-policy.json'), 'utf8'));
const NOW = 1794787200000;

const t0 = performance.now();
const { falhas, cobertura } = verificar(2000, 0xC0FFEE, SHIPPED);
const ms = performance.now() - t0;
console.log(`fuzz: 2000 entradas em ${ms.toFixed(0)} ms; cobertura ${JSON.stringify(cobertura)}; violacoes ${falhas.length}`);
let saida = 0;
for (const f of falhas.slice(0, 10)) console.log(`  VIOLACAO ${f}`);
if (falhas.length) saida = 1;
const minimos = { ritmo_desce: 20, repeticao: 50, revisor: 100 };
for (const [k, min] of Object.entries(minimos)) {
  if (cobertura[k] < min) {
    console.log(`  COBERTURA ${k}=${cobertura[k]} < ${min}`);
    saida = 1;
  }
}

const medida = (rotulo, fn, limiteMs) => {
  const t = performance.now();
  fn();
  const d = performance.now() - t;
  console.log(`${d > limiteMs ? 'AVISO' : 'ok   '} ${rotulo}: ${d.toFixed(0)} ms (orcamento ${limiteMs} ms)`);
};
const politica = structuredClone(SHIPPED);
politica.valid_until = '2027-06-30T00:00:00Z';
const entrada = (prompt, extra = {}) => ({ prompt, role: 'autor', subagentType: 'x', now: NOW, ...extra });
medida('prompt patologico de 1 MiB (marcas combinantes)', () => decide(entrada(`a${'̖́'.repeat(524288)}`), politica), 300);
medida('10 MiB de texto comum', () => decide(entrada('palavra comum de teste '.repeat(Math.ceil((10 * 1024 * 1024) / 23))), politica), 1000);
medida('1 MiB de texto comum com a palavra de risco no meio', () => decide(entrada(`${'lorem ipsum '.repeat(43690)} producao ${'lorem ipsum '.repeat(43690)}`), { ...politica, role_floors: { ...politica.role_floors } }), 300);
const muitas = {};
for (let i = 0; i < 1_000_000; i++) muitas[`k${i}`] = 1;
medida('1 milhao de chaves em history.falhasPorChave', () => decide(entrada('x', { chave: 'k1', history: { falhasPorChave: muitas, autorTierPorChave: {} } }), politica), 300);
process.exit(saida);
