# defesa-de-tese - DEPRECADA em 2026-08-14

## Motivo, e ele e estrutural, nao de qualidade

A skill validava plano, PRD ou fix como tese academica, com portoes logicos. O conteudo era bom.
O DEFEITO era onde ela rodava: **na mesma resposta que propos a coisa validada**.

Isso e auto-correcao intrinseca. A §1 da config global ja bastava para descarta-la, e o ADR 0011
registrou a decisao de trocar encenacao por mecanismo. O agente `refutador` faz a mesma pergunta
com CONTEXTO SEPARADO, que compra independencia procedimental parcial - fraca, mas real, e a
skill nao comprava nenhuma.

## Por que ela sobreviveu tanto tempo depois de declarada absorvida

O `~/.claude/CLAUDE.md` §9 dizia, desde antes desta data, que "a antiga skill `defesa-de-tese` foi
absorvida" pelo `refutador`. O texto estava certo e o arquivo continuou instalado e promovido.
Ninguem detectou porque NADA valida coerencia entre o que a config declara e o que o registro de
skills contem - a mesma classe do ADR 0030: a norma no texto, ausente no portao.

Junto com ela havia uma referencia PIOR: `execution/skills/promoted/design-system-proposal/SKILL.md`
invocava `/direcao-de-arte` em quatro pontos, e essa skill nao existe mais - foi absorvida pelo
`revisor-frontend`. Referencia morta em producao, num fluxo que o operador aciona por comando.
`orchestration/skill-policy.json` lista `unresolved_reference` como gatilho de depreciacao, e o
proprio registro tinha uma.

Ambas as chamadas foram reapontadas para os agentes no mesmo commit.

## O que NAO foi feito, declarado

O arquivo permanece versionado, nao apagado: a `skill-policy.json` distingue `deprecated` de
`rejected`, e nada aqui justifica `rejected`. O conteudo pode servir de referencia para o prompt
do `refutador`.

Nao houve medicao de eficacia - nem desta skill, nem de nenhuma outra. `evidence/skills/` nao
existe e 0 de 19 claims citam skill. Esta depreciacao decorre de REDUNDANCIA ESTRUTURAL provada
(mesmo contexto = sem descorrelacao), nao de delta de desempenho medido. Chamar isso de "provado
ineficiente" seria overclaim.
