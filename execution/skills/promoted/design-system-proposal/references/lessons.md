# Licoes aprendidas (erros ja pagos -> regras). Cada uma: sintoma -> regra -> verificacao.

Este e o checklist de dominio L1-L10 (os 10 itens abaixo, na ordem), COMPLEMENTAR a varredura
generica do agente `refutador` — nao a substitui. Rodar as DUAS varreduras antes de publicar (fase 8).

1. **Status isoluminante quebra WCAG 1.4.1.** Sintoma: ok/warn/bad com mesmo L/C, so matiz diferente,
   1.04:1 entre si -> daltonico nao separa. Regra: cada status com SUA luminosidade (STATUS_L por tema).
   Verificar: `ratio(status_a, status_b) >= 1.35` para todo par de solidos de status.

2. **Portao com `assert` some sob `python -O`.** Sintoma: `assert not FAILS` -> `python -O` remove o
   assert -> HTML escrito COM pares reprovados e exit 0. Regra: `if FAILS: sys.exit(1)`; o build le o
   EXIT, nao o stdout. Verificar: injetar piso impossivel + rodar `python -O build.py` -> HTML NAO escrito.

3. **Charset tardio vira mojibake (GBK).** Sintoma: "Tres" -> caractere CJK. O `<meta charset>` caiu
   apos ~1 KB de CSS/JS, fora da janela de sniffing. Regra: `<meta charset="utf-8">` e o 1o elemento.
   Verificar: `document.characterSet == "UTF-8"`.

4. **Doctype duplicado no artifact.** Sintoma: o harness ja injeta `<!doctype html>`; um doctype no
   body e parse-error. Regra: NAO por doctype quando o alvo e artifact (por SIM se for HTML standalone).
   Verificar: no publicado, `document.compatMode == "CSS1Compat"` (standards).

5. **Dark = so escurecer o claro (errado).** Sintoma: creme quente escurecido lê marrom sujo. Regra:
   superficie pode trocar matiz/chroma/rampa no dark (`H_dark`/`C_dark`/`Ls_dark`); ancorar o near-black
   na propria paleta (ex.: #0A0A0A). Verificar: n1-dark tem o H/L pretendido, nao o do claro.

6. **Varredura de contraste ignora opacity.** Sintoma: par passa no token mas o texto real tem
   `opacity:.6` e reprova. Regra: compor a cor sobre o fundo (aplicar alpha) ANTES de medir.
   Verificar: a varredura inclui `getComputedStyle().opacity` na composicao.

7. **Demo generica (nao le a tela real).** Sintoma: layout inventado a partir do nome do arquivo.
   Regra: a demo sai da TELA REAL (`git show <ref-producao>:<path>`), lida por completo. Verificar:
   cada demo cita a tela-fonte; labels/dados batem com producao.

8. **Recurso externo quebra o artifact.** Sintoma: fonte/CDN/imagem via http -> CSP bloqueia, quebra
   offline. Regra: tudo inline como data-URI; escapar `<` no JSON; abortar se lib inline tem `</script`.
   Verificar: `grep -c 'src\|href="http' final.html` == 0; abre em `file://`.

9. **Ilha isoluminante a moldura.** Sintoma: superficie demonstrada (n1) ~ fundo do frame do lab ->
   borda some. Regra: delimitar a ilha por anel/elevacao (nao mudar a cor demonstrada). Verificar no browser.

10. **Vender PROPOSTA como REAL.** Sintoma: derivado apresentado como se viesse do repo. Regra: rotular
    REAL vs PROPOSTA em toda cor/fonte; o texto nunca finge norma. Verificar: cada valor tem origem citada.
