# Fase 1-2: estudar o repo e extrair marcas + telas REAIS

Objetivo: um inventario com caminhos:linha reais, do qual a proposta deriva. Delegar a leitura pesada
ao `Explore`/`investigador` (isolar ruido). Nunca inferir de nome de arquivo — sempre abrir e ler.

## Inventario de stack e UI
- Gestor/monorepo: `package.json`, `pnpm-workspace.yaml`, `nx.json`, `pyproject.toml`, `turbo.json`.
- Libs de UI: React/Vue/Svelte? ShadcnUI/antd/MUI/Chakra? Tailwind (`tailwind.config.*`)? styled-components?
- Tokens/tema JA existentes: `tailwind.config` theme, `theme.ts`, `tokens.json`, CSS custom properties
  (`--*` em `:root`), `ConfigProvider` do antd, `styled-components` DefaultTheme.
- Motion: framer-motion? CSS transitions? tokens de `--ease-*`/`--dur-*`?
- Fontes: `@font-face`, `next/font`, links de webfont, `font-family` em CSS/tema.

## Detectar whitelabel / multi-marca / multi-projeto
- Multiplas marcas: procurar mapas de `brand`, `tenant`, `organization`, `theme` com hexes distintos;
  logos/wordmarks por marca; um seletor de marca.
- Multi-projeto (spokes/monorepo): pastas `spokes/*`, `apps/*`, `packages/*`, remotes de Module
  Federation, projetos Nx com tags `scope:*`. Cada um vira uma TELA-DEMO distinta.
- SE o repo tem UM produto so -> a proposta e single-brand; nao fabricar marcas que nao existem.

## Extrair a PALETA e a TIPOGRAFIA reais (REAL vs PROPOSTA)
- Ler os HEXES da fonte real (colors.ts/tokens/tailwind). Ex.: `gh api repos/<org>/<repo>/contents/
  src/theme/colors.ts --jq .content | base64 -d`. Registrar cada cor com nome e papel declarado no repo.
- Ler as FONTES reais (nao inventar). Se a marca nao tem identidade tipografica verificavel -> marcar
  PROPOSTA e dizer que e proposta.
- Distinguir SEMPRE: REAL = existe no repo/producao; PROPOSTA = voce derivou. O artifact rotula os dois
  (badge REAL verde / PROPOSTA ambar) e o texto nunca vende derivado como do repo.

## Telas REAIS para as demos (nao generico)
- A demo de cada projeto/spoke sai da TELA REAL: `git show origin/production:<path-da-tela>` (ou o ref
  de producao), lida por completo, reproduzindo layout/labels/dados de exemplo reais.
- Capturar os BUGS reais do produto (contraste baixo, status colididos, foco invisivel) e mostra-los no
  modo "Hoje" — a proposta ganha forca ao corrigi-los sob o DS.
- Verificar: cada demo cita a tela-fonte (arquivo:ref). Zero layout inventado.

## Saida da fase
Um bloco: {stack, libs_ui, tokens_existentes, marcas:[{nome, hexes REAL, fontes}], projetos/telas:
[{nome, tela-fonte, bugs-hoje}], topologia}. Sem esse inventario, NAO gerar tokens (fase 4 depende dele).
