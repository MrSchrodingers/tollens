# Montagem do artifact self-contained (CSP-safe)

O alvo e UM `.html` publicado como artifact do Claude (harness envolve em `<!doctype html>...<head>
...</head><body>`). Regras que fazem ele abrir offline e sem mojibake.

## build.py — o assemblador
```python
import json, pathlib, subprocess, sys
GEN = pathlib.Path(__file__).parent / "gen_tokens.py"     # resolve relativo a src/, nao ao cwd
r = subprocess.run([sys.executable, str(GEN)], capture_output=True, text=True)
if r.returncode != 0:                                  # PORTAO: nunca `assert` (python -O o apaga)
    sys.stderr.write(r.stdout + r.stderr); sys.exit("build abortado: contraste reprovou")
_, sep, payload = r.stdout.partition("// ---- dados ----")
if not sep: sys.exit("build abortado: marcador ausente")
D = json.loads(payload)

FONTS = "\n".join(_face(fam, b64, w) for fam,b64,w in FACES)   # @font-face data-URI (woff2)
css = pathlib.Path("lab.css").read_text().replace("/*__FONTFACES__*/", FONTS)
if "/*__FONTFACES__*/" in css: sys.exit("build abortado: fontes nao injetadas")
parts = [
  '<meta charset="utf-8">',                            # 1o ELEMENTO (ver charset abaixo)
  "<title>...</title>",
  "<style>\n"+css+"\n</style>",
  # libs pesadas (three.js etc.) inline; abortar se contiverem `</script`
  '<script>window.__DATA__=' + json.dumps(D, separators=(",",":"), ensure_ascii=False).replace("<","\\u003c") + ';</script>',
  pathlib.Path("lab.html").read_text(),
  "<script>\n"+pathlib.Path("lab.js").read_text()+"\n</script>",
]
pathlib.Path(sys.argv[1]).write_text("\n".join(parts), encoding="utf-8")
```

## Regras (cada uma com o porque)
- **`<meta charset="utf-8">` e o 1o byte util.** Se cair depois de ~1 KB de CSS/JS (janela de
  sniffing do browser), um consumidor raw decodifica UTF-8 como GBK e "Tres" vira mojibake.
  Verificar: `document.characterSet == "UTF-8"` no preview local.
- **NAO incluir `<!DOCTYPE html>`.** O harness do artifact ja injeta; um doctype no body e
  parse-error ignorado. (Se o alvo NAO for artifact e sim arquivo standalone, ai SIM incluir doctype,
  senao o preview roda em quirks mode.) Verificar: no artifact publicado, `document.compatMode` = standards.
- **Tudo inline como data-URI.** CSP do artifact bloqueia CDN/webfont/fetch. Fontes woff2 em base64,
  libs JS embutidas, imagens em `data:`. Verificar: `grep -c 'src\|href="http' final.html` == 0.
- **Escapar `<` no JSON injetado** (`.replace("<","\\u003c")`) e abortar se lib inline contem
  `</script` — senao o bloco `<script>` fecha cedo e quebra o HTML.
- **Contraste medido com opacity COMPOSTA.** Uma varredura que le `getComputedStyle().color` NAO ve
  `opacity < 1` do elemento/pai; um texto n11 no fio de 4.5:1 com `opacity:.6` cai abaixo de AA.
  Compor a cor sobre o fundo antes de medir.
- **0 emoji em qualquer artefato** (regra global; hook bloqueia em arquivo).

## Dual-skin: "Hoje (producao)" vs "Sob o Design System"
Cada tela-demo tem dois modos:
- `writeProd(el)` escreve os HEXES/fontes REAIS de producao (o "antes").
- `writeTokens(el)` escreve os tokens `--n*`/`--a*` do DS (o "depois").
Isso torna a proposta AUDITAVEL: o usuario ve o delta, e os bugs reais do produto (contraste baixo,
status colididos) ficam visiveis no modo "Hoje".

## Verificacao
`python src/build.py out.html` re-roda o gerador e SO escreve com exit 0. `grep -c 'href="http\|src="http'
out.html` == 0. `grep -c emoji` == 0. Abrir `file://out.html` -> renderiza sem rede.
