# Sistema de tokens OKLCH + portao WCAG (fonte da verdade)

Layout dos arquivos (canonico, o mesmo em todos os refs): `src/gen_tokens.py` (este gerador),
`src/build.py` (assemblador), `src/lab.{css,html,js}`, `assets/*`. Comandos rodam da RAIZ do lab
(ex.: `python src/build.py out.html`). Um unico `src/gen_tokens.py` gera TODAS as escalas e ABORTA
(exit != 0) se qualquer par (texto,fundo) reprovar o piso WCAG. O build re-roda e so escreve o HTML
com exit 0. Nunca hardcodar hex no HTML: tudo sai daqui.

## Os 4 eixos ortogonais
- MARCA -> acento: `a9` (solido/botao), `a10` (hover), `a11` (texto/link sobre superficie). Semente = hex REAL da marca.
- SUPERFICIE -> cromo: `n1..n12` (n1 fundo do app; n3 card; n5 borda; n11/n12 texto). Matiz proprio por superficie.
- TEMA -> rampa de luminosidade: dark / light / hc (alto contraste). Muda os L, nao o matiz base.
- TIPOGRAFIA -> `display` por marca (serif/sans/slab conforme identidade). Corpo = sans neutro; mono para dados.

Override de superficie POR TEMA (licao critica): dark NAO e o claro escurecido. A superficie pode
declarar `H_dark`, `C_dark`, `Ls_dark`, `sunk_dark` aplicados so quando `theme.dark` — ex.: papel
creme quente no claro, onix neutro profundo (n1~#0A0A0A) no escuro.

## Status com luminosidade PROPRIA (WCAG 1.4.1)
Tres solidos de status (ok/warn/bad) com MESMO L e C, mudando so o matiz, ficam isoluminantes
(1.04:1 entre si) e um daltonico nao os separa. Cada status recebe SUA luminosidade:
```python
STATUS_L = {"light": {"ok":.52,"warn":.70,"bad":.42},
            "dark":  {"ok":.68,"warn":.82,"bad":.58},
            "hc":    {"ok":.46,"warn":.66,"bad":.36}}
# alem do par (fg,bg) assertado, exigir >= 1.35:1 ENTRE os solidos de status.
```

## Esqueleto do gerador (adaptar hexes/marcas do repo)
```python
import json, math, sys
def s2l(c): return c/12.92 if c<=0.04045 else ((c+0.055)/1.055)**2.4
def l2s(c):
    c=max(0.,min(1.,c)); return 12.92*c if c<=0.0031308 else 1.055*c**(1/2.4)-0.055
def to_oklch(h):
    h=h.lstrip('#'); r,g,b=(s2l(int(h[i:i+2],16)/255) for i in (0,2,4))
    l=.4122214708*r+.5363325363*g+.0514459929*b; m=.2119034982*r+.6806995451*g+.1073969566*b; s=.0883024619*r+.2817188376*g+.6299787005*b
    l_,m_,s_=(v**(1/3) if v>0 else 0 for v in (l,m,s))
    L=.2104542553*l_+.7936177850*m_-.0040720468*s_; a=1.9779984951*l_-2.4285922050*m_+.4505937099*s_; bb=.0259040371*l_+.7827717662*m_-.8086757660*s_
    return L, math.hypot(a,bb), math.degrees(math.atan2(bb,a))%360
def oklab_lin(L,a,b):
    l_=L+.3963377774*a+.2158037573*b; m_=L-.1055613458*a-.0638541728*b; s_=L-.0894841775*a-1.2914855480*b
    lo,m,s=l_**3,m_**3,s_**3
    return (4.0767416621*lo-3.3077115913*m+.2309699292*s, -1.2684380046*lo+2.6097574011*m-.3413193965*s, -.0041960863*lo-.7034186147*m+1.7076147010*s)
def in_gamut(L,C,H,e=1e-4):
    a,b=C*math.cos(math.radians(H)),C*math.sin(math.radians(H)); return all(-e<=v<=1+e for v in oklab_lin(L,a,b))
def clampC(L,C,H):
    if in_gamut(L,C,H): return C
    lo,hi=0.,C
    for _ in range(40):
        mid=(lo+hi)/2; lo,hi=(mid,hi) if in_gamut(L,mid,H) else (lo,mid)
    return lo
def oklch(L,C,H):
    C=clampC(L,C,H); a,b=C*math.cos(math.radians(H)),C*math.sin(math.radians(H)); r,g,bl=oklab_lin(L,a,b)
    return "#{:02X}{:02X}{:02X}".format(*[max(0,min(255,round(l2s(v)*255))) for v in (r,g,bl)])
def lum(h):
    h=h.lstrip('#'); r,g,b=(s2l(int(h[i:i+2],16)/255) for i in (0,2,4)); return .2126*r+.7152*g+.0722*b
def ratio(h1,h2):
    a,b=lum(h1),lum(h2); hi,lo=max(a,b),min(a,b); return (hi+.05)/(lo+.05)

THEMES = {  # Ls[1..8] = rampa de luminosidade da superficie; cmul = multiplicador de chroma
  "dark":  dict(dark=True,  cmul=1.15, Ls={1:.179,2:.214,3:.261,4:.297,5:.331,6:.377,7:.437,8:.531}),
  "light": dict(dark=False, cmul=1.00, Ls={1:.985,2:.967,3:.940,4:.910,5:.870,6:.780,7:.560,8:.420}),
  "hc":    dict(dark=False, cmul=0.55, Ls={1:1.0,2:.988,3:.970,4:.952,5:.933,6:.825,7:.690,8:.570}),
}
C_N = {1:.55,2:.75,3:1.0,4:1.1,5:1.15,6:1.2,7:1.15,8:1.05}
SURFACES = {"papel": dict(H=95.,C=.008, H_dark=181.,C_dark=.006,
                          Ls_dark={1:.145,2:.180,3:.230,4:.265,5:.315,6:.375,7:.445,8:.545})}
BRANDS = {"marca": dict(surface="papel", accent="#546B65")}  # accent = hex REAL da marca

def neutral(surf, th):
    s,t = SURFACES[surf], THEMES[th]; d=t["dark"]
    H = s.get("H_dark",s["H"]) if d else s["H"]
    Cb = (s.get("C_dark",s["C"]) if d else s["C"]) * t["cmul"]
    Ls = s.get("Ls_dark",t["Ls"]) if d else t["Ls"]
    return {i: oklch(Ls[i], Cb*C_N[i], H) for i in range(1,9)}

FAILS=[]
def assert_pair(name, fg, bg, floor):  # NAO usar assert (python -O o remove)
    r=ratio(fg,bg)
    if r < floor-1e-3: FAILS.append(f"{name}: {r:.2f} < {floor}")

data={"neutral":{}}
for th in THEMES:
    for surf in SURFACES:
        n=neutral(surf,th); data["neutral"][f"{surf}-{th}"]={"n":[n[i] for i in range(1,9)]}
        assert_pair(f"n11/n1 {surf}-{th}", n[6] if th!="light" else "#000", n[1], 4.5)  # exemplo; casar com o papel real de cada token
# ... (acento a9/a10/a11, status, e cada par texto-sobre-superficie assertado aqui)
print("// ---- dados ----"); print(json.dumps(data, separators=(",",":")))
sys.exit(1 if FAILS else 0)  # PORTAO: 1 se qualquer par reprovou
```

## Contrato de saida
1. Imprimir logs no stdout; depois o marcador `// ---- dados ----`; depois UM JSON.
2. `sys.exit(1 if FAILS else 0)` — o build le o exit, NAO o stdout, para decidir escrever.
3. O JSON traz `neutral[surf-theme].n`, `accent[brand-theme]`, `status[theme]`, `brands`, `typography`.

## Verificacao
`python src/gen_tokens.py >/dev/null; echo $?` == 0. Injetar um piso impossivel (ex.: 99.0) num par
-> exit 1. Depois `python -O src/build.py out.html` com o par reprovado -> HTML NAO escrito (prova que
o gate do BUILD e `if/sys.exit`, nao `assert`: o -O apaga assert, mas nao o `if`).
