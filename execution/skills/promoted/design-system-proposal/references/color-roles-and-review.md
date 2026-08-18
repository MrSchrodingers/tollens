# Fase 6-7: mapa cor -> papel no UI + rubrica da banca

## Mapa cor -> papel (toda cor tem um lugar; todo lugar tem uma cor)
Preencher esta tabela para CADA marca x tema. O par (cor, fundo) traz o piso WCAG exigido ALI.

| Papel no UI | Token | Piso de contraste (WCAG 2.2) |
|---|---|---|
| Fundo do app | `n1` | base — nada exige contraste contra ele "de fora" |
| Superficie elevada (card/painel) | `n3` | separacao perceptivel de `n1` (delta L, nao ratio) |
| Borda sutil / divisor | `n5`/`n6` | 3:1 se transmite informacao (1.4.11); decorativo isento |
| Texto secundario / placeholder | `n11` | 4.5:1 sobre a superficie onde assenta (1.4.3) |
| Texto primario / titulo | `n12` | 4.5:1 (>=3:1 se >=24px ou >=18.66px bold) |
| Botao primario (solido) | `a9` + `on-solid` | fundo 3:1 vs superficie adjacente (1.4.11); label 4.5:1 vs `a9` |
| Botao hover | `a10` | manter label >=4.5:1 |
| Link / texto de acento | `a11` | 4.5:1 sobre `n1` e `n3` |
| Foco visivel (ring) | `focus` | 3:1 vs adjacente; nunca so `outline:none` (2.4.7) |
| Status ok/warn/bad (solido) | `status[]` | 3:1 vs fundo E >=1.35:1 ENTRE si (1.4.1, nao-isoluminante) |
| Overlay/scrim de modal | `overlay` | contraste suficiente do conteudo por cima |

Regras de distribuicao (convencao, nao spec — declarar como tal):
- Fundo NEUTRO + cor no ACENTO = premium/sobrio; a identidade vem do acento e da elevacao, nao do
  fundo colorido. Near-black da propria paleta (ex.: #0A0A0A) ancora o dark.
- Acento usado com PARCIMONIA (uma acao primaria por vista); excesso de acento mata a hierarquia.
- Status nunca comunicado SO por cor (1.4.1): reforcar com icone/rotulo/luminosidade.

## Rubrica da banca -> a fase 7 DELEGA ao agente `revisor-frontend` (P10a: nao repetir a rubrica dele aqui)
A banca de arte e DONA da hierarquia de autoridade da fonte (WCAG=spec > Nielsen/Gestalt/tokens=convencao
> Refactoring UI/8pt=opiniao; F/Z=hipotese) e das lentes UX/composicao/tipografia/acessibilidade/harmonia-
com-irmas. Aciona-la, nao reimplementa-la.

O DELTA que ESTA skill acrescenta a banca (nao coberto pelo `revisor-frontend`): a checagem de
DISTRIBUICAO DE COR contra a tabela cor->papel acima. Passar a tabela PREENCHIDA como insumo, e exigir:
- acento parcimonioso: no maximo uma acao primaria (a9) por vista; excesso mata a hierarquia;
- cada cor no papel declarado (fundo/superficie/borda/texto/solido/hover/foco/link/status), sem cor orfa;
- status nunca comunicado SO por cor (1.4.1): reforcar por icone/rotulo/luminosidade propria.

## Saida
Parecer por severidade (BLOQUEANTE WCAG / ALTO / MEDIO / BAIXO / OBSERVACAO), cada achado com FONTE
(spec/convencao/opiniao) + arquivo:linha + como validar. Aplicar o material antes de publicar.
Validacao VISUAL (render/pixel) roda no browser — o revisor le codigo, e fraco em cross-tela.
