# Contrato do motor de decisao para o mod (fatia R2)

Escopo: o que o mod deve passar a `decide(input, policy)` e o que `decide` devolve. O motor e puro
(`engine.mjs`): nao le relogio, arquivo, ambiente nem sentinela. Tudo isso e responsabilidade do mod.
Nao existe ainda mod, ledger nem leitura de `session.measure`; este documento nao os promete.

## O que o mod deve passar em `input`

- `now`: milissegundos inteiros desde a epoca, em [1,6e12, 4,1e12], ou ISO estrito
  `AAAA-MM-DDTHH:MM:SS[.mmm]Z` na mesma faixa. Segundos, zero, negativo, texto numerico e `Date`
  nao valem: o motor trata como `sem_relogio_valido` e degrada para shadow.
- `prompt`: texto bruto da chamada. O motor le a ficha na primeira linha e analisa o texto sem ela.
  So a cabeca e a cauda (`policy.limites.prompt_max_bytes`, padrao 65536, em unidades de texto
  UTF-16) entram na busca de palavras de risco e caminhos; o recorte e marcado com
  `prompt_truncado`. O tamanho vale pelo texto inteiro. Uma palavra de risco so no meio de um
  prompt maior que o limite nao e vista.
- `chave`: identificador da tarefa, calculado pelo mod (nao vem da ficha), ate 256 caracteres.
  Sem `chave`, nao ha historico por tarefa nem autor "da mesma chave".
- `role` e `subagentType`: comparados sem caixa e sem espacos extras com os nomes da politica.
- `history.falhasPorChave`: falhas por chave, ja aparado pelo ledger do fluxo corrente (o motor nao
  conhece fluxo). Chave com 2 ou mais falhas conta como subida ja concedida; chaves com 1 falha
  disputam as subidas novas que restam sob `escalation.max_por_fluxo`, em ordem de nome.
- `history.autorTierPorChave` e `history.autorTierMax`: nivel do autor da mesma chave e o maior
  nivel de autor do fluxo (`"T0"` a `"T4"`). Revisor, refutador e auditor usam o da mesma chave
  quando conhecido, senao `autorTierMax`.
- `pace.estado`: `abaixo`, `dentro` ou `acima`. Qualquer outro valor vale `dentro`. O mod calcula
  o estado com as faixas `policy.pace`.
- `ficha` e opcional: ausente, o motor le a primeira linha do prompt. Se informada, e revalidada.

Entrada que nao e objeto, ou campo de tipo errado, nunca lanca: o campo e ignorado.

## O que `decide` devolve

`{ tier, model, effort, floor, tier_base, estado_nivel, reasons, capped, mode, modo_efetivo, aplicar }`

- `tier`, `model`, `effort`: decisao pretendida. `model` e sempre `haiku`, `sonnet` ou `opus`.
- `floor`: piso (papel, superficie de risco, tamanho, caminhos, autor, repeticao). `tier >= floor`.
- `tier_base`: nivel apos ficha, piso e repeticao, antes do ritmo e da qualidade.
- `estado_nivel`: `medido_ok`, `reprovado` ou `nao_medido` do nivel de `tier`.
- `mode`: modo da politica apos validade e medicao. `modo_efetivo`: o que de fato vale.
- `aplicar`: `true` somente se `modo_efetivo` for `enforce`. O mod nao deve alterar a chamada
  quando `aplicar` for `false`, embora `model` e `effort` venham preenchidos.
- `capped`: houve subida pedida e negada ou esgotada (teto por chave, por fluxo ou topo).
- `reasons`: codigos curtos, sem conteudo do prompt.

Politica invalida: `tier`, `model` e `effort` nulos, `mode` e `modo_efetivo` `off`, `aplicar` falso.
Politica vencida ou sem relogio valido: `shadow`. Politica em `enforce` com qualquer nivel sem
medicao: valida, mas efetiva em `shadow` (`nivel_nao_medido`). Nenhum nivel elegivel (todos
reprovados): `tier` volta a `tier_base`, `aplicar` falso (`sem_nivel_elegivel`).

## Fora do motor

Sentinela de root, ledger, leitura de `session.measure`, aplicacao de `model` e `effort` na chamada,
leitura de `router-policy.json` (o motor recebe o objeto ja lido) e conferencia da allowlist contra
as chaves managed (`availableModels`, `deniedModels`).

## Limites conhecidos

- Homoglifo fora do mapa cirilico e grego do motor continua sem cobertura.
- Prefixos amplos de palavra de risco elevam por excesso (por exemplo `secretaria`, `product`).
- O teto por fluxo e deterministico, mas sem memoria; a ordem por nome nao e a ordem temporal.
- `Date.parse` e `String.prototype.normalize` com `\p{...}` nao tem verificacao no runtime de mods.
