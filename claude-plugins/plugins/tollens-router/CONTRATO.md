# Contrato do motor de decisao para o mod (fatia R2)

Escopo: o que o mod deve passar a `decide(input, policy)` e o que `decide` devolve. O motor e puro
(`engine.mjs`): nao le relogio, arquivo, ambiente nem sentinela. Tudo isso e responsabilidade do mod.
Nao existe ainda mod, ledger nem leitura de `session.measure`; este documento nao os promete.

## Dado puro

`decide` e `validatePolicy` copiam a politica e a entrada para dado puro no inicio e validam a COPIA.
Dado puro e: nulo, booleano, numero, texto, lista e objeto simples (prototipo `Object.prototype` ou
nulo). Sao recusados, sem excecao: funcao, simbolo, bigint, `Date`, `Map`, instancia de classe, objeto
com outro prototipo, getter ou setter, ciclo, profundidade acima de 16 e mais de 100000 nos visitados
(um DAG compartilhado conta cada visita). Politica recusada devolve
`politica_invalida`; entrada recusada devolve `entrada_invalida`; nos dois casos `tier`, `model` e
`effort` sao nulos, `mode` e `modo_efetivo` sao `off` e `aplicar` e falso. Cada propriedade e lida uma
vez, pelo descritor. Um `Proxy` nao e detectavel: um que NAO lanca entra pela mesma regra (a copia e
consistente) e nao e rejeitado. Um `Proxy` que lanca ou foi revogado nunca faz `decide` nem
`validatePolicy` lancarem: a leitura e protegida e o resultado e `politica_invalida` ou
`entrada_invalida` (`validatePolicy` devolve `ok:false`). O mod deve passar dado vindo de `JSON.parse`.

## O que o mod deve passar em `input`

- `now`: milissegundos inteiros NUMERICOS desde a epoca, em [1,6e12, 4,1e12]. Qualquer texto (inclusive
  ISO), segundos, zero, negativo e `Date` nao valem: o motor trata como `sem_relogio_valido` e degrada
  para shadow (`Date` na entrada ainda e `entrada_invalida`, por nao ser dado puro). `valid_until`
  da politica continua ISO estrito.
- `prompt`: texto bruto da chamada. O motor le a ficha na primeira linha e varre o texto sem ela, em
  janelas de 64 KiB com sobreposicao de ate 128 caracteres (a proxima janela recua ate o inicio de um
  trecho de letras, digitos, marcas ou formato; corrida de espacos, travessoes ou outros nao-letras
  acima de U+007F nao a engana), ate `policy.limites.prompt_max_bytes` (padrao
  1 MiB, em unidades de texto UTF-16). Acima do teto o motor sinaliza `prompt_acima_do_teto`, aplica
  o piso `size.acima_do_teto` e varre so o que cabe no teto. O texto so e varrido para o que ainda
  pode elevar o piso: se o piso de papel, de autor ou de tamanho ja iguala o de risco, a varredura
  de risco e pulada e `piso_superficie_de_risco` nao aparece em `reasons`. Palavras de politica com
  varias palavras so casam dentro de uma janela.
- `chave`: identificador da tarefa, calculado pelo mod (nao vem da ficha), de 1 a 256 caracteres. Sem
  `chave` (ausente, vazia ou longa demais) vale `sem_chave`: nenhum historico por tarefa e nenhum
  autor "da mesma chave". `ficha.t` e validada, mas o `decide` nao a usa: e informativa para o ledger
  do mod.
- `role` e `subagentType`: comparados com os nomes da politica por NFKC, sem caracteres de formato
  (zero-width, soft hyphen), sem marcas combinantes, sem caixa, sem espacos extras e com homoglifos
  cirilicos e gregos dobrados, como as palavras de risco. Um prefixo de namespace `plugin:nome` vale
  pelo ultimo segmento (so pode elevar o piso). Nomes que colidem depois de normalizados ficam com o
  maior piso.
- `history` (ate 1000 entradas por lista ou mapa; o excedente e cortado com `history_truncado` e
  nao concede nova subida, mas a entrada da `chave` do chamador e buscada por acesso direto ANTES do
  corte e sempre mantida, entao uma falha ou uma concessao da chave nunca se perde; chaves e itens de
  texto com mais de 256 caracteres sao descartados; o corte so ocorre depois de enumerar as chaves,
  entao o mod deve passar o historico ja aparado: medido, enumerar 1 milhao de chaves custa cerca de
  1,3 s so no motor):
  - `falhasPorChave`: falhas por chave, ja aparado pelo ledger do fluxo corrente.
  - `subidasConcedidas`: lista de chaves que ja subiram, persistida pelo mod (R2 DEVE persisti-la: a
    pegajosidade so vale enquanto a falha existe no historico; fora dele, so esta lista a mantem).
    O motor nunca revoga uma chave desta lista nem uma com 2 ou mais falhas. Teto de NOVAS
    concessoes por fluxo: `escalation.max_por_fluxo` menos as chaves de `subidasConcedidas`. Uma
    chave com 2 ou mais falhas sobe uma vez sem consumir o teto (sem laco).
  - `ordem`: chaves na ordem temporal da primeira falha. As subidas NOVAS (1 falha) usam as vagas que
    restam sob `escalation.max_por_fluxo` na ordem de `ordem`, depois chave critica (nome com palavra
    de risco ou listada em `chavesCriticas`), depois o nome.
  - `chavesCriticas`: chaves que o mod marca como criticas (piso de risco ou papel revisor).
  - `autorTierPorChave` e `autorTierMax`: nivel do autor da mesma chave e o maior nivel de autor do
    fluxo (`"T0"` a `"T4"`). Revisor, refutador e auditor usam o da mesma chave quando conhecido,
    senao `autorTierMax`.
- `pace.estado`: `abaixo`, `dentro` ou `acima`. Qualquer outro valor vale `dentro`.
- `ficha` e opcional: ausente, o motor le a primeira linha do prompt. Se informada, e revalidada.

Entrada que nao e objeto vale `{}`; campo de tipo errado e ignorado.

## O que `decide` devolve

`{ tier, model, effort, floor, tier_base, estado_nivel, reasons, capped, subida_concedida, mode,
modo_efetivo, aplicar }`

- `tier`, `model`, `effort`: decisao pretendida. `model` e sempre `haiku`, `sonnet` ou `opus`.
- `floor`: piso (papel, superficie de risco, tamanho, caminhos, autor, repeticao). `tier >= floor`.
- `tier_base`: nivel apos ficha, piso e repeticao, antes do ritmo e da qualidade.
- `estado_nivel`: `medido_ok`, `reprovado` ou `nao_medido` do nivel de `tier`. `nao_medido` inclui
  `n` menor que `limites.n_minimo` (padrao 8).
- `subida_concedida`: a chamada recebeu uma subida por repeticao; o mod deve acrescentar a chave a
  `subidasConcedidas`.
- `mode`: modo da politica apos validade e medicao. `modo_efetivo`: o que de fato vale.
- `aplicar`: `true` somente se `modo_efetivo` for `enforce`. O mod nao deve alterar a chamada
  quando `aplicar` for `false`, embora `model` e `effort` venham preenchidos.
- `capped`: houve subida pedida e negada ou esgotada (teto por chave, por fluxo ou topo).
- `reasons`: codigos curtos, sem conteudo do prompt.

Politica invalida: `tier`, `model` e `effort` nulos, `mode` e `modo_efetivo` `off`, `aplicar` falso.
Politica vencida ou sem relogio valido: `shadow`. Politica em `enforce` com qualquer nivel EMITIVEL
sem medicao: valida, mas efetiva em `shadow` (`nivel_nao_medido`). Nivel com `emitivel: false` nunca e
escolhido: o motor sobe ate o proximo emitivel. Nenhum nivel elegivel (todos reprovados ou nao
emitiveis acima): `tier` volta a `tier_base`, `aplicar` falso (`sem_nivel_elegivel`).

## Politica (validatePolicy)

Alem da forma, o validador exige: custo estritamente crescente entre niveis (modelo, depois effort),
ao menos um nivel emitivel, aliases somente `haiku`, `sonnet`, `opus`, `risk_surface.piso` >= T3,
`size.prompt_chars.piso`, `size.caminhos.piso` e `size.acima_do_teto.piso` >= T2, pisos de papel para `refutador` e
`auditor-seguranca` (>= T3) e `revisor-codigo` (>= T2), `reviewer_roles` contido em `role_floors` com
piso >= T2, os 16 prefixos de risco minimos, palavras com 3 ou mais caracteres apos normalizacao,
`piso_aprovacao` >= 0,5 e por papel >= o default, `valid_until` com ida e volta e no maximo 400 dias
a frente de `now`. `policy.schema.json` documenta a forma; a suite confere que o validador nunca
aceita o que o schema recusa.

## Fora do motor

Sentinela de root, ledger, leitura de `session.measure`, aplicacao de `model` e `effort` na chamada,
leitura de `router-policy.json` (o motor recebe o objeto ja lido) e conferencia da allowlist contra
as chaves managed (`availableModels`, `deniedModels`).

## Limites conhecidos

- Homoglifo fora do mapa cirilico e grego do motor continua sem cobertura.
- Prefixos amplos de palavra de risco elevam por excesso (por exemplo `secretaria`, `product`).
- Num token de mais de 128 caracteres sem separador, a fronteira da janela pode criar um inicio de
  palavra falso: so eleva, nunca baixa.
- `Date.parse`, `String.prototype.normalize` e `\p{...}` nao tem verificacao no runtime de mods.
