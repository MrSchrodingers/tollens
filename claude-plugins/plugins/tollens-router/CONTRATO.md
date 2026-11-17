# Contrato do motor de decisao para o mod (fatia R2)

Escopo: o que o mod deve passar a `decide(input, policy)` e o que `decide` devolve. O motor e puro
(`engine.mjs`): nao le relogio, arquivo, ambiente nem sentinela. Tudo isso e responsabilidade do mod.
O mod (`hooks/register.js`, secao "O mod" abaixo) liga o motor ao Claude Code; este documento descreve o que ele passa ao motor e o que faz com a decisao.

## Dado puro

`decide` e `validatePolicy` copiam a politica e a entrada para dado puro no inicio e validam a COPIA.
Dado puro e: nulo, booleano, numero, texto, lista e objeto simples (prototipo `Object.prototype` ou
nulo). Sao recusados, sem excecao: funcao, simbolo, bigint, `Date`, `Map`, instancia de classe, objeto
com outro prototipo, getter ou setter, ciclo, profundidade acima de 16 e mais de 100000 nos visitados
(um DAG compartilhado conta cada visita). Politica recusada devolve `politica_invalida`; entrada
recusada devolve `entrada_invalida`; nos dois casos `tier`, `model` e `effort` sao nulos, `mode` e
`modo_efetivo` sao `off` e `aplicar` e falso. Cada propriedade e lida uma vez, pelo descritor. Um
`Proxy` nao e detectavel: um que NAO lanca entra pela mesma regra (a copia e consistente) e nao e
rejeitado. Um `Proxy` que lanca ou foi revogado nunca faz `decide` nem `validatePolicy` lancarem: a
leitura e protegida e o resultado e `politica_invalida` ou `entrada_invalida` (`validatePolicy`
devolve `ok:false`). O mod deve passar dado vindo de `JSON.parse`.

## O que o mod deve passar em `input`

- `now`: milissegundos inteiros NUMERICOS desde a epoca, em [1,6e12, 4,1e12]. Qualquer texto (inclusive
  ISO), segundos, zero, negativo e `Date` nao valem: o motor trata como `sem_relogio_valido` e degrada
  para shadow (`Date` na entrada ainda e `entrada_invalida`, por nao ser dado puro). `valid_until`
  da politica continua ISO estrito.
- `prompt`: texto bruto da chamada. O motor le a ficha na primeira linha e varre o texto sem ela, de
  uma vez e sem janelas (o resultado nao depende de onde o texto cai), ate `policy.limites.prompt_max_bytes`
  (padrao 256 KiB, no maximo 1 MiB, em unidades de texto UTF-16). A busca de palavras de risco opera
  sobre o texto normalizado por NFKC (letras circuladas, largura total e ligaduras viram letras
  comuns), sem caracteres ignoraveis (formato como zero-width e soft hyphen, marcas combinantes e
  `Default_Ignorable_Code_Point` como os preenchimentos de hangul), em minuscula, com homoglifos
  cirilicos e gregos comuns dobrados e sem acentos; todo o resto que nao e letra ou digito separa
  palavras. Acima do teto o motor sinaliza `prompt_acima_do_teto` e aplica o piso `size.acima_do_teto`
  (T3 ou acima e nunca abaixo do piso de risco, por isso o texto depois do teto nao precisa ser
  varrido). O texto so e varrido para o que ainda pode elevar o piso: se o piso de papel, de autor ou de
  tamanho ja iguala o de risco, a varredura de risco e pulada e `piso_superficie_de_risco` nao aparece em
  `reasons`.
- `chave`: identificador da tarefa, calculado pelo mod (nao vem da ficha), de 1 a 256 caracteres. Sem
  `chave` (ausente, vazia ou longa demais) vale `sem_chave`: nenhum historico por tarefa e nenhum
  autor "da mesma chave". `ficha.t` e validada, mas o `decide` nao a usa: e informativa para o ledger
  do mod.
- `role` e `subagentType`: comparados com os nomes da politica por NFKC, sem caracteres ignoraveis,
  sem marcas combinantes, sem caixa, sem espacos extras e com homoglifos dobrados, como as palavras de
  risco. Um prefixo de namespace `plugin:nome` vale pelo ultimo segmento (so pode elevar o piso).
  Nomes que colidem depois de normalizados ficam com o maior piso.
- `history` (ate 1000 entradas por lista ou mapa; o excedente e cortado com `history_truncado` e
  nao concede nova subida, mas a entrada da `chave` do chamador e buscada por acesso direto ANTES do
  corte e sempre mantida; chaves e itens de texto com mais de 256 caracteres sao descartados; o corte
  so ocorre depois de enumerar as chaves, entao o mod deve passar o historico ja aparado: enumerar 1
  milhao de chaves custa cerca de 1,3 s so no motor, e isso continua obrigacao do mod):
  - `falhasPorChave`: falhas por chave, ja aparado pelo ledger do fluxo corrente.
  - `subidasConcedidas`: lista de chaves que ja subiram, persistida pelo mod. Uma chave desta lista sobe
    pelo menos um nivel SEMPRE (com ou sem falha em `falhasPorChave`) e nunca desce. Uma chave com 2 ou
    mais falhas sobe uma vez sem consumir vaga (sem laco).
  - `ordem`: chaves na ordem de chegada da primeira falha, a mais antiga primeiro, sem duplicatas; o
    motor tolera duplicata (vale a primeira posicao). As vagas novas vao para as mais antigas.
  - `chavesCriticas`: chaves que o mod marca como criticas (piso de risco ou papel revisor).
  - `autorTierPorChave` e `autorTierMax`: nivel DECIDIDO do autor da mesma chave e o maior nivel de
    autor do fluxo (`"T0"` a `"T4"`). Revisor, refutador e auditor usam o da mesma chave quando
    conhecido, senao `autorTierMax`.
- `pace.estado`: `abaixo`, `dentro` ou `acima`. Qualquer outro valor vale `dentro`.
- `ficha` e opcional: ausente, o motor le a primeira linha do prompt. Se informada, e revalidada.

Entrada que nao e objeto vale `{}`; campo de tipo errado e ignorado.

## Teto de novas concessoes por fluxo

`escalation.max_por_fluxo` limita as NOVAS concessoes. Consumo do teto = chaves de `subidasConcedidas`
que nao tem 2 ou mais falhas. Chave com 2 ou mais falhas nunca consome vaga e sobe uma vez. Entre as
chaves novas (1 falha, fora de `subidasConcedidas`) as vagas vao por `ordem`, depois chave critica (nome
com palavra de risco ou listada em `chavesCriticas`), depois o nome. Historico truncado: sem nova
concessao. O motor e funcao pura de um historico CONSISTENTE.

## Protocolo do mod (R2)

Respostas escritas, sem inventar alem disto; dois implementadores devem chegar ao mesmo mod.

- (a) Derivacao de `chave`: sha256 em hex dos primeiros 200 caracteres do texto normalizado (NFKC,
  minuscula, espacos colapsados) de `subagentType + '\n' + descricao` (a descricao da chamada Agent),
  NUNCA da ficha. `ficha.t` e so informativa (vai ao ledger). Limite: o orquestrador controla a
  descricao e pode reiniciar a contagem de falhas mudando-a; isso so faz perder o beneficio da subida por
  repeticao, nunca baixa o piso.
- (b) `ordem`: lista de chaves, a mais antiga primeiro, sem duplicatas, na ordem em que cada chave teve a
  primeira falha registrada; as vagas novas sao dadas nessa ordem.
- (c) Aparar TODAS as estruturas de `history` a no maximo 1000 entradas ANTES de chamar `decide`
  (`falhasPorChave`, `autorTierPorChave`, `subidasConcedidas`, `ordem`, `chavesCriticas`), preservando a
  chave atual e as chaves de `subidasConcedidas`: `falhasPorChave` mantem as chaves com 1 ou mais falhas
  mais a chave atual, escolhendo as de maior contagem. O motor sinaliza `history_truncado` quando algum
  mapa ou lista passa de 1000 e `history_truncado_lista` quando e uma lista; nesse caso nega novas
  concessoes sem o codigo `teto_por_fluxo`.
- (d) Persistir `subidasConcedidas`: sempre que `decision.subida_concedida` for `true`, em qualquer modo
  (shadow incluso) e ANTES de aplicar a decisao. Invariante do R2: com persistencia atrasada o motor
  pode revogar a concessao (uma chave nova que vem antes por ordem ocupa a vaga); o motor so garante o
  comportamento com historico consistente. Limite do R2: o protocolo nao torna atomica a sequencia
  leitura do historico, decisao e persistencia entre chamadas paralelas; o teto de novas concessoes
  pode ser excedido em ate o numero de chamadas concorrentes.
- (e) `autorTierMax`: o mod passa o tier DECIDIDO (`decision.tier`) do autor da mesma chave; o maior
  entre os autores do fluxo.
- (f) `pace.estado`: seja `p` = percentual semanal usado menos a fracao decorrida da semana (ambos em
  [0,1]). `abaixo` se `p < policy.pace.abaixo_de`; `acima` se `p > policy.pace.acima_de`; `dentro` nos
  demais casos (os limites sao `dentro`). Sem leitura de ritmo: `dentro`.
- (g) `parseRota(prompt)` e `stripRota(prompt)` sao exportados, puros, e olham apenas a primeira linha
  (J10). J3 x J10: em `shadow` e `off` a chamada NAO e alterada (a linha `@@ROTA` permanece no prompt);
  so em `enforce` (`aplicar: true`) o mod aplica `model` e `effort` e passa o prompt de `stripRota`.
  DECISAO: em `shadow` a linha `@@ROTA` permanece no prompt do subagente (J3 vence J10).
- (h) `capped` e `subida_concedida` juntos: `subida_concedida` diz que a chave recebeu concessao
  registravel (persistir); `capped` diz que nao ha mais subida a conceder. Concessao nova abaixo do
  topo: `true` e `false`. Chave com 2 ou mais falhas: `true` e `true`. Concessao no topo (sem nivel
  acima): `true` e `true`. Negada pelo teto: `false` e `true`.
- (i) Codigos de `reasons`: lista abaixo.

## Codigos de reasons

- `politica_invalida`, `entrada_invalida`: politica ou entrada que nao e dado puro ou politica invalida.
- `politica_vencida`, `sem_relogio_valido`: validade da politica e relogio.
- `sem_ficha`, `ficha_invalida`, `ficha_abaixo_do_piso`: ficha ausente, recusada ou abaixo do piso.
- `sem_chave`, `history_truncado`, `history_truncado_lista`: chave ausente, historico cortado em 1000
  entradas e corte de uma lista.
- `piso_papel:<nome>`, `piso_superficie_de_risco`, `piso_tamanho`, `piso_tamanho_acima_do_teto`,
  `piso_caminhos`, `prompt_acima_do_teto`, `revisor_nao_abaixo_do_autor`: componentes do piso.
- `repeticao`, `teto_por_fluxo`: subida por falha e teto de novas concessoes.
- `ritmo_desce`, `ritmo_sobe`: deslocamento por ritmo.
- `abaixo_do_piso_de_qualidade`, `nivel_nao_medido`, `sem_nivel_elegivel`: qualidade medida.

## O que `decide` devolve

`{ tier, model, effort, floor, tier_base, estado_nivel, reasons, capped, subida_concedida, mode,
modo_efetivo, aplicar }`

- `tier`, `model`, `effort`: decisao pretendida. `model` e sempre `haiku`, `sonnet` ou `opus`.
- `floor`: piso (papel, superficie de risco, tamanho, caminhos, autor, repeticao). `tier >= floor`.
- `tier_base`: nivel apos ficha, piso e repeticao, antes do ritmo e da qualidade.
- `estado_nivel`: `medido_ok`, `reprovado` ou `nao_medido` do nivel de `tier`. `nao_medido` inclui
  `n` menor que `limites.n_minimo` (padrao 8).
- `subida_concedida`: a chamada recebeu uma subida por repeticao; o mod persiste a chave em
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
`size.prompt_chars.piso` e `size.caminhos.piso` >= T2, `size.acima_do_teto.piso` >= T3 e nunca abaixo
do piso de risco nem de `size.caminhos.piso`, pisos de papel para `refutador` e `auditor-seguranca` (>= T3) e `revisor-codigo`
(>= T2), `reviewer_roles` contido em `role_floors` com piso >= T2, os 16 prefixos de risco minimos,
palavras com 3 ou mais caracteres apos normalizacao, `piso_aprovacao` >= 0,5 e por papel >= o default,
`valid_until` com ida e volta, no maximo 400 dias a frente de `now` e nunca depois de 2030-01-01 (teto
absoluto, vale sem `now`; revisar a cada ciclo de release). `policy.schema.json` documenta a forma; a
suite confere que o validador nunca aceita o que o schema recusa.

## Fora do motor

Sentinela de root, ledger, leitura de `session.measure`, aplicacao de `model` e `effort` na chamada,
leitura de `router-policy.json` (o motor recebe o objeto ja lido) e conferencia da allowlist contra
as chaves managed (`availableModels`, `deniedModels`): tudo isso e do mod.

## O mod (R2)

- **Caminhos FIXOS em producao.** Politica `/etc/claude-code/router-policy.json`, sentinela
  `/etc/claude-code/router-off` (presente = `off`, lida a cada decisao), managed-settings
  `/etc/claude-code/managed-settings.json` (somente leitura), ledger sob `${HOME}/.claude/logs/`. Nenhum
  caminho vem de variavel de ambiente nem de settings do repositorio. `criarMod(config)` (injecao explicita
  de `politica`, `sentinela`, `managed`, `ledgerDir`) existe so para teste; o `register` instalado usa os
  padroes. A sentinela padrao vale mesmo com outra sentinela injetada.
- **Modos.** `shadow` e `off` nao alteram a chamada (a linha `@@ROTA` permanece); so `enforce` com
  `aplicar: true` aplica `model` e `effort` e remove a primeira linha `@@ROTA`. Fork nao recebe `model` nem
  `effort`. Fable nunca e escolhido.
- **Hooks.** `tool.call` (Agent e Task); `agent.spawn` so para workflow e teammate sem `tool.call` anterior
  (subagente comum, fork e retomada passam); `session.measure`. `claude plugin validate` avisa
  `gating hook without .catch` nos dois primeiros: sem `.catch` o runtime pula o hook que lanca ou estoura
  o prazo e a chamada segue sem o mod, que e o fail-open desejado. Nao se adiciona `.catch`.
- **Variavel de ambiente.** O mod NAO altera nenhuma. Para agente de workflow define `model` em
  `agent.spawn` (e so sobe: baseline desconhecido nunca e tocado). NAO VERIFICADO: se o runtime respeita o
  `model` do hook quando `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL` esta definida (o d.ts diz que o modelo
  forcado pela sessao vence o do hook).
- **Managed.** Lê `availableModels` e `deniedModels`. Se o modelo escolhido esta negado ou ausente, aplica o
  maior nivel emitivel abaixo do decidido cujo modelo e permitido e que nao fica abaixo do `model` pedido
  pelo orquestrador; sem candidato, mantem a chamada. Registra `managed_nega_modelo` (o modelo desejado fica
  em `pedido`) e avisa com `$.ui.notice` uma vez por sessao. Arquivo ilegivel: sem restricao (falha aberta).
  O nivel alternativo nao reconfere a medicao de qualidade da politica.
- **Estado.** `$.store`, chave `router.estado.<session_id>` (falhasPorChave, subidasConcedidas, ordem,
  autorTierPorChave, chavesCriticas), aparado a 1000 entradas por estrutura antes de `decide`; indice
  `router.indice` com as ultimas 50 sessoes (sessao com 14 dias ou mais, e as excedentes, sao apagadas ao
  escrever uma sessao nova). Falha de `store.set` nao derruba o roteamento: `persistencia_falhou` e aviso.
  Sem `session_id` nada e persistido (`sem_sessao_id`).
- **Ledger.** Um arquivo por SESSAO: `router-ledger-<16 hex do sha256 do session_id>.jsonl` (sem sessao:
  `router-ledger-sem-sessao.jsonl`), rotacao em 3 geracoes por arquivo (`.1` a `.3`, acima de 2 MiB).
  Consumidores (model-honor C5, painel) leem o glob `router-ledger-*.jsonl*`. So anexa a arquivo vazio ou
  cuja primeira linha seja de ledger; nunca regrava arquivo alheio nem rotaciona sobre geracao alheia.
  `$.fs` nao tem modo de arquivo: o ledger nao e 0600 (umask do usuario). A escrita e read+write nao atomica:
  a fila serializa dentro do processo e o arquivo por sessao evita a corrida entre processos.
  Campos: `ts, evento, session_id, tool_use_id, agent_type, role, chave (16 hex), ficha (c, r, v), floor,
  tier_base, tier, pedido, aplicado, mode, modo_efetivo, pace, capped, subida_concedida, reasons, efetivo,
  usados, sinal, erro`. `ficha.t` NAO vai ao ledger (texto livre do orquestrador). Eventos: `tool.call`,
  `agent.spawn`, `efetivo` (apos o resultado: `resolvedModel` e `modelsUsed` do Agent, ou `null`; junta por
  `tool_use_id` com o model-honor), `resultado` (sinal de falha).
- **Sinais de falha.** So de formato documentado: `isError` do resultado, `status` do registro do Agent
  diferente de `completed` e `async_launched`, e linha estruturada no inicio de linha
  (`Estado|Veredito|Resultado: NAO VERIFICADO|REFUTADO|REPROVADO`). Texto solto nao conta. O mod nao
  re-executa; em enforce acrescenta a nota ao resultado.
- **Ritmo.** Leitura `seven_day` descartada (estado `dentro`) com `resetsAt` ausente, no passado ou alem de
  7 dias, ou `percentUsed` fora de [0,100]; vale por 30 minutos desde a medicao.
- **Codigos de reasons do mod:** `politica_ausente`, `politica_ilegivel`, `history_aparado`,
  `modelo_fora_da_allowlist`, `sentinela_off`, `managed_nega_modelo`, `persistencia_falhou`,
  `sem_sessao_id`.
- **Nao verificado em runtime:** carregamento real (allowManagedHooksOnly), `{...res, context}` como nota,
  nomes dos campos da chamada Agent, criacao do diretorio do ledger por `$.fs.write`, `\p{}` e `normalize`
  no sandbox do mod.

## Limites conhecidos

- Homoglifo fora do mapa cirilico e grego do motor continua sem cobertura.
- Letras que o NFKC nao converte para letras comuns (por exemplo grafias decorativas fora das
  compatibilidades Unicode) nao sao reconhecidas.
- 28 pontos de codigo expandem mais de 4 no NFKC. 19 do BMP (ligaduras arabes como U+FDFA, que expande
  18 vezes, unidades katakana e `rad/s`) valem como separador, o que evita custo de segundos; os 9
  simbolos musicais astrais (U+1D160-1D164, U+1D1BD-1D1C0) nao sao tratados (custo medido: cerca de
  270 ms para 256 KiB).
- U+2800 (braille em branco) e outros simbolos invisiveis que nao sao ignoraveis separam palavras: uma
  palavra de risco com U+2800 no meio nao e reconhecida (piso T2 em vez de T3).
- Prefixos amplos de palavra de risco elevam por excesso (por exemplo `secretaria`, `product`).
- Um caractere ignoravel colado entre duas palavras as une (`a` + zero-width + `b` vira `ab`).
- `Date.parse`, `String.prototype.normalize` e `\p{...}` nao tem verificacao no runtime de mods.
