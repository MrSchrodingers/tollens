# `tools:` declarado nao prediz `tools:` concedido - nas DUAS direcoes

Data: 2026-08-31. Maquina: estacao `ti`, Fedora 43. Sessao principal
`68e9eb26-f760-418d-a88d-613921631721`, `cwd=/home/ti/evidence-gate`.

## O que foi observado

Dois subagentes lancados nesta sessao reportaram, de dentro, o proprio esquema de funcoes:

    investigador           declarou `Read, Grep, Glob, Bash`   recebeu {Read, Bash}
    mapeador-dependencias  declarou `Read, Grep, Glob, Bash`   recebeu {Read, Bash}

Subconjunto ESTRITO do declarado. Uso efetivo medido no transcrito do primeiro: `{Bash: 15,
Read: 1}` - zero `Grep`, zero `Glob`.

## O que NAO se conclui disso, e a tentativa errada esta registrada de proposito

A primeira leitura desta sessao foi "`Grep` e `Glob` NAO EXISTEM neste runtime", e sobre ela foram
construidos um inventario publicado e um portao de CI. A leitura e FALSA, e o `refutador` a
derrubou com fonte primaria na propria maquina:

    sdk-tools.d.ts (2.1.252)   `interface GrepInput` e `interface GlobInput`, na uniao canonica
    historico da maquina       507 chamadas `Grep` e 220 `Glob`, com tool_result e zero is_error
    a mais recente             sob 2.1.241, em `/var/www/amaral-intern-hub`, em SUBAGENTE

As duas ferramentas existem. O que varia e a CONFIGURACAO: as sessoes que as receberam sao de
outro projeto.

O INSTRUMENTO NAO PODIA TER FALSIFICADO A HIPOTESE. O controle positivo usado foi
`ToolSearch select:Grep,Glob` -> `No matching deferred tools found`. Essa mensagem fala sobre
ferramenta DIFERIDA; uma ferramenta DIRETA produz exatamente a mesma resposta. Existe resposta
positiva possivel para diferida (`select:Monitor` devolve `tool_reference`) e nenhuma para direta.
A metade que decidia - "nao aparece na lista direta" - era autorrelato de esquema, sem artefato.

E o rotulo de versao estava errado: o inventario gravava `2.1.252`, que e o que `claude --version`
le do DISCO. O processo desta sessao e `2.1.241`, lido do transcrito. Medir um processo e etiquetar
com a versao de outro e o defeito que a secao 2 do kernel nomeia.

## A formulacao que sobrevive

O claim C-019 (`2026-08-10-capacidade-declarada-vs-observada.md`) registrou o grant como ADITIVO:
`Write`/`Edit` concedidos a um `refutador` que nao os declara. Esta observacao e SUBTRATIVA.

    NAO sobrevive:  "o runtime concede a mais"
    SOBREVIVE:      "o `tools:` declarado nao prediz o concedido, nas duas direcoes,
                     e o concedido depende da configuracao da sessao"

## Precedencia de escopo, medida e com o limite declarado

Havia duas definicoes do mesmo agente, diferentes:

    /etc/claude-code/.claude/agents/mapeador-dependencias.md   tools: Read, Grep, Glob, Bash
    /home/ti/.claude/agents/mapeador-dependencias.md           tools: Read, Bash

A sonda reportou esquema efetivo `{Read, Bash}`, o que casa com o escopo de USUARIO e refuta o
managed. LIMITE QUE A PROPRIA SONDA DECLAROU: o frontmatter nao lhe e exposto, entao a conclusao e
por CAPACIDADE EFETIVA, nao por leitura. Hipotese alternativa que ela nao pode refutar de dentro:
o managed ter vencido e uma camada posterior ter removido os dois nomes. Os corpos dos dois
arquivos eram byte-identicos, entao o corpo nao discrimina. Para tornar isso decidivel seria
preciso um marcador distinto por escopo - que nao existe.

## Aresta pendurada, do mesmo modo de falha

A sonda recebeu instrucoes do servidor MCP `plugin:context7:context7` e NENHUMA ferramenta
correspondente no esquema. Texto injetado sem a capacidade que ele pressupoe: a mesma divergencia
entre o que o runtime declara e o que habilita.
