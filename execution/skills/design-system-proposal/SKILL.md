---
name: design-system-proposal
description: Le e estuda um repositorio qualquer (stack, libs de UI, tokens/temas, telas REAIS, whitelabel/multi-marca/spokes) e entrega uma PROPOSTA de Design System como UM unico artifact HTML self-contained, com gerador de tokens OKLCH + portao de contraste WCAG, fidelidade as telas reais, banca de revisao de UI/UX/cor e veredito calibrado. Acionar quando o usuario pedir "propor/criar design system", "tokens/tema para o repo", "design system whitelabel/multi-marca", "paleta para as marcas".
---

# /design-system-proposal

IMPORTA: o agente `revisor-frontend` (banca de UI/UX/cor - renderiza a tela e roda axe) e
o agente `refutador` (veredito calibrado, contexto separado). NAO reimplementar o review nem o
gate de tese: este dominio e a GERACAO da proposta; as duas bancas sao as fases 7 e 8.

## O que entrega
UM arquivo `.html` self-contained (CSP-safe: zero requisicao externa, fontes/deps inline como
data-URI) que demonstra a proposta de Design System sobre as TELAS REAIS do repo, em N marcas x
{dark, light, alto-contraste}, com o par "Hoje (producao)" vs "Sob o Design System" e o rotulo
honesto REAL vs PROPOSTA em cada token derivado do que nao existe no repo.
Verificacao (binaria): (a) o gerador de tokens sai `exit 0` e escreve o HTML SO se todo par
(texto,fundo) passa WCAG AA; sob `python -O` ele AINDA bloqueia; (b) `grep` no HTML final acha 0
`src|href="http` e 0 emoji; (c) o `<meta charset="utf-8">` e o 1o elemento; (d) cada cor da paleta
tem um PAPEL declarado no UI (ver fase 6). Falha em qualquer item BLOQUEIA a publicacao.

## Gatilho
SE o usuario pede propor/criar um design system, tokens/tema, paleta multi-marca, ou "um DS como o
do amaral" -> FAZER as Fases.
SE a duvida e so revisar UI ja existente (nao propor DS novo) -> delegar ao `revisor-frontend` direto,
NAO esta skill (evita custo sem retorno).
SE o pedido e um artefato PONTUAL (uma cor, um token OKLCH avulso) sem proposta de DS -> resolver
direto, NAO rodar o pipeline de 9 fases.
SE o usuario quer um prompt colavel para disparar isto em outro repo -> entregar references/kickoff-prompt.md.

## Fases (cada uma VERIFICA antes de avancar; nao pular)

### 1. ESTUDAR o repo -> references/repo-study.md
Delegar ao agente `Explore`/`investigador` (contexto ruidoso fica isolado). Levantar: stack e
libs de UI (package.json/pyproject/tailwind.config/ConfigProvider/CSS vars), tokens/temas
existentes, telas REAIS, e a topologia (monorepo? whitelabel? marcas? spokes/multi-projeto?).
VERIFICAR: inventario escrito com caminhos:linha reais. SE nao houver UI verificavel -> parar e
dizer, nunca inventar.

### 2. EXTRAIR marcas + telas REAIS (REAL vs PROPOSTA) -> references/repo-study.md
Ler os HEXES e FONTES reais do repo/producao, nunca de memoria nem de nome de arquivo. Para tela
de producao, usar `git show <ref>:<path>` (ex.: `origin/production`). Marcar cada valor: REAL (existe
no repo) ou PROPOSTA (derivado por voce). VERIFICAR: toda cor/fonte tem origem citada.

### 3. DECIDIR com o usuario (AskUserQuestion) -> so onde ha ambiguidade real
Perguntar 2-4 opcoes MUTUAMENTE EXCLUSIVAS, cada uma com o trade-off, para: refinar paleta, escolher
o fundo escuro (renderizar candidatos e deixar escolher por OLHO), e a tipografia por marca. Antes de
perguntar, renderizar os candidatos num comparador e capturar screenshot (decisao por evidencia
visual). NAO perguntar o obvio. SE o select do AskUserQuestion falhar -> apresentar os
candidatos por imagem e aceitar a escolha em prosa.
VERIFICAR: cada decisao de gosto (paleta/fundo/tipo) registrada com o candidato escolhido + o
screenshot que a fundamentou; nenhuma decisao sem evidencia visual.

### 4. GERAR tokens -> references/token-system.md
Gerador OKLCH unico (fonte da verdade) com clamp de gamut e PORTAO de contraste que sai `exit != 0`
se um par reprovar. Eixos ortogonais: MARCA(acento a9/a10/a11) x SUPERFICIE(cromo n1..n12) x
TEMA(dark/light/hc rampa de L) x TIPOGRAFIA(display por marca). Override de superficie por tema
(H_dark/C_dark/Ls_dark): dark NAO e so escurecer o claro. Status com luminosidade PROPRIA (nao
isoluminante). VERIFICAR: `python src/gen_tokens.py; echo $?` == 0.

### 5. MONTAR o artifact -> references/artifact-build.md
Assemblar UM HTML: `<meta charset>` 1o, SEM `<!DOCTYPE>` (o harness de artifact injeta), fontes e
libs inline como data-URI, dual-skin "Hoje vs Sob o DS", gate `if/sys.exit` (nunca `assert`).
VERIFICAR: build re-roda o gerador e ABORTA a escrita se exit != 0; HTML abre offline.

### 6. MAPEAR cor -> papel no UI -> references/color-roles-and-review.md
Para CADA cor: onde entra (fundo/superficie/borda/texto/acento-solido/hover/foco/status) e o piso de
contraste exigido ali. VERIFICAR: nenhuma cor sem papel; nenhum papel sem cor.

### 7. REVISAR (banca de arte) -> agente `revisor-frontend`
Acionar a skill importada: parecer por severidade, gate WCAG binario, harmonia com o DS, comparacao
de telas-irmas. Aplicar achados material antes de seguir. VERIFICAR: parecer com veredito.

### 8. VALIDAR (banca academica) -> agente `refutador`
Tratar a proposta como TESE: 3 portoes logicos + varredura de erro obvio
sobre o HTML/gerador BRUTOS, MAIS o checklist de dominio L1-L10 (references/lessons.md). VERIFICAR:
veredito calibrado; "aprovar" so com as DUAS varreduras passando e evidencia colada.

### 9. PUBLICAR
Publicar o artifact (mesma URL em iteracoes). Declarar em UMA linha o que e REAL vs PROPOSTA. Backup
timestampado da fonte+artifact fora do repo se o usuario pedir seguranca.

## Regras inviolaveis do dominio (subset curado; L1-L10 completo + verificacao em references/lessons.md)
- Status NAO isoluminante (cada status sua L) -> senao WCAG 1.4.1 quebra p/ daltonico. Verificar: 1.35:1 entre solidos.
- Gate = `if r.returncode: sys.exit(...)`, nunca `assert` -> `python -O` remove assert e escreve HTML reprovado. Verificar: injetar falha sob -O, HTML NAO escrito.
- `<meta charset="utf-8">` 1o byte util -> senao sniffing vira GBK/mojibake nos acentos. Verificar: `document.characterSet=="UTF-8"`.
- SEM `<!DOCTYPE>` quando alvo e artifact -> o harness injeta; doctype no body e parse-error. Verificar: harness = standards mode.
- Varredura de contraste no browser NAO ve opacity compositada -> medir a cor JA composta, nao o token. Verificar: incluir `opacity` no calculo.
- Demo de spoke sai da TELA REAL lida (git show producao), nunca de nome de arquivo -> senao vira generico. Verificar: cada demo cita a tela-fonte.
- Fundo neutro + cor no ACENTO e o padrao premium; near-black da paleta (ex.: #0A0A0A) ancora o dark -> identidade vem do acento, nao do fundo colorido.

## Verificacao (da skill inteira)
Artifact publicado; gerador exit 0; 0 par WCAG reprovado; 0 recurso externo/emoji; REAL vs PROPOSTA
declarado; parecer do `revisor-frontend` e veredito do `refutador` anexados; cada cor com papel no UI.

## Porque (P7)
- Duas bancas importadas: o review de arte e o gate de tese ja existem e sao caros de refazer (P10a).
- Fidelidade a tela real: o valor do DS e ser reconhecivelmente o produto; generico e ruido.
- Portao WCAG no gerador (nao no review): erro obvio barrado por poka-yoke, nao por memoria (ADR 0005).
- REAL vs PROPOSTA: honestidade epistemica; nunca vender derivado como se fosse do repo (anti-bajulacao).
