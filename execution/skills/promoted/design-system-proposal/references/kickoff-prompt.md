# Kickoff prompt (colar em qualquer repo para disparar /design-system-proposal)

Prompt reutilizavel. Ajustar `<...>`; o resto e o contrato de qualidade.

---

Proponha um Design System para este repositorio e entregue como UM artifact HTML self-contained.
Use a skill /design-system-proposal. Nao seja generico: leia o repo de verdade.

CONTEXTO
- Marca(s)/produto(s): <deixe descobrir do repo, ou nomeie>
- Referencia de paleta/identidade: <URL do site/repo de marca, se houver>
- Producao (para telas reais): <ref git, ex.: origin/production> ; acesso read-only: <ssh/host, se houver>

O QUE QUERO
1. ESTUDE o repo: stack, libs de UI, tokens/tema existentes, telas REAIS, e se ha whitelabel/multi-marca/
   multi-projeto (spokes). Liste com caminhos:linha. Se nao houver UI verificavel, diga — nao invente.
2. EXTRAIA as cores e fontes REAIS (do repo/producao, nunca de memoria). Rotule REAL vs PROPOSTA em tudo.
3. Onde houver ambiguidade de gosto (paleta, fundo escuro, tipografia), RENDERIZE candidatos, capture
   screenshot e me deixe escolher por olho (AskUserQuestion; se o select falhar, aceite minha escolha em prosa).
4. GERE tokens OKLCH num unico gerador com clamp de gamut e PORTAO WCAG que sai exit!=0 se um par reprovar
   (if/sys.exit, nunca assert). Eixos: MARCA(acento) x SUPERFICIE(cromo) x TEMA(dark/light/hc) x TIPOGRAFIA.
   Dark nao e so escurecer o claro; status com luminosidade propria (nao isoluminante).
5. MONTE o artifact: charset utf-8 no 1o elemento, sem doctype, fontes/deps inline (CSP-safe, zero rede),
   com o par "Hoje (producao)" vs "Sob o Design System" em cada tela real.
6. MAPEIE cada cor ao seu PAPEL no UI (fundo, superficie, borda, texto, botao solido/hover, foco, link,
   status) com o piso de contraste exigido em cada lugar.
7. REVISE com o agente `revisor-frontend` e VALIDE com o agente `refutador`: varredura de erro
   obvio sobre o HTML/gerador brutos. So declare pronto com o gerador em exit 0 e a varredura passando.
8. PUBLIQUE o artifact e declare em uma linha o que e REAL vs PROPOSTA.

NAO-NEGOCIAVEIS
- Zero recurso externo, zero emoji, portugues/idioma do produto correto (sem mojibake).
- Nenhuma cor sem papel no UI; nenhum par de texto abaixo de WCAG AA.
- Fidelidade a tela real; honestidade REAL vs PROPOSTA; evidencia (exit code, contraste medido) colada.

---

## Como acionar sem o prompt longo
Basta: "crie um design system whitelabel para este repo, como o do amaral" -> a skill dispara pelo gatilho.
