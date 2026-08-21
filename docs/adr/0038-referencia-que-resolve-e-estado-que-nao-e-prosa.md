# ADR 0038 - Referencia que resolve, e estado que nao e prosa

Data: 2026-08-21
Estado: aceito
Sucede: ADR 0037 (o frame e derivado, e a ausencia e delimitada)

## Contexto

A onda 18 tornou o frame do corpus derivado dos proprios achados. A auditoria seguinte aceitou o
fechamento e achou dois gaps no que ficou derivado - os dois no mesmo lugar: **o derivado e fiel
ao declarado, e nada garantia o declarado**.

## **G14** - `source_ref` nao resolvia

`evidence/corpus/render.py` deriva `sources` do campo `source_ref` de cada achado. Isso garante

```
derived.sources == { source_ref declarados }
```

e nada sobre

```
PARA TODO s em derived.sources: Existe(s)
```

Medido:

```
$ # source_ref = "docs/adr/nao-existe.md"
$ python3 evidence/corpus/render.py --update && python3 tests/unit/governance-links.py
rc=0        <- frame derivado atualizado, portao verde, referencia morta
```

E a familia da onda 12 - "referencia publicada que nao resolve" - voltando DENTRO do instrumento
construido para medir a propria trajetoria de defeitos. Fechado: `source_ref` e `resolution_ref`
tem de resolver para arquivo existente, confinado ao repositorio, sem `..`. `MCC12` e `MCC13`.

## **G15** - o estado do achado era prosa autodeclarada

`open_findings` derivava de `status.startswith("aberto")`, texto livre. Medido:

```
$ # G4 (aberto) tem o status trocado por "corrigido", e nada mais muda
open_findings agora: ['G5', 'G6b', 'G7']
rc=0
```

O derivado seguia perfeitamente consistente. A parte governada continuava escolhendo o proprio
estado - a familia do `G4`, num campo diferente.

`state` passa a ser enum fechado (`open`, `resolved`, `invalidated`, `superseded`), `resolved`
exige `resolution_ref` que RESOLVA, e `open` exige `open_note` dizendo o que falta. `MCC14`,
`MCC15` e `MCC16`.

**LIMITE, e ele importa mais que a correcao.** Enum nao remove a autodeclaracao: quem edita o
corpus continua escrevendo o `state`. O que deixou de ser possivel e declarar `resolved` sem
apontar para nada. A claim que o corpus pode sustentar encolheu para o que ela sempre foi:

```
existe artefato alegando corrigir  NAO E  o defeito foi corrigido
```

## Correcao factual: quatro ADRs desta serie, nao oito

Um relatorio publicado por esta sessao dizia "cinco PRs (#23 a #27), oito ADRs (0030-0037)".
Medido:

```
0030  52b5bb7  2026-08-12     0034  7538824  2026-08-19   PR #23
0031  190b68e  2026-08-17     0035  df26c6f  2026-08-19   PR #24
0032  190b68e  2026-08-17     0036  2114823  2026-08-20   PR #26
0033  e9f2332  2026-08-18     0037  3d0290f  2026-08-20   PR #27
```

Os quatro primeiros sao ANTERIORES ao PR #23. A serie produziu 0034 a 0037. A frase induzia
atribuicao causal errada, e nao foi corrigida em silencio: fica aqui, porque o defeito era de
uma afirmacao publicada.

## Tambem ajustado no relatorio

- `34 capabilities` sao 34 ENTRIES do registry: 33 instaladas e governadas mais o tombstone
  `defesa-de-tese`, que existe justamente para nao ser instalado. Sem a nota, o numero sugere 34
  componentes ativos.
- "sete rodadas de revisao" NAO e numero derivado, ao contrario dos 56 achados. As rodadas
  passam a ser nomeadas em vez de contadas, para que o `7` nao pegue emprestada a forca
  observacional do `56`.
- A frase "transformaria isso de engenharia em resultado" era imprecisa: ha resultado empirico
  farto sobre VALIDADE DE MECANISMO - mutantes mortos, o `rm -rf` por symlink, o fail-open de
  locale, a CI recusando o renderer sem piso. O que falta e resultado sobre EFICACIA EXTERNA. A
  distincao e mais forte que a frase original e foi adotada.

## Limites, declarados

`G4`, `G5`, `G6b` e `G7` seguem abertos, e a proposta de fecha-los por propriedades observaveis
da capability segue registrada e nao construida.

`historical_states` continua sendo registro DECLARADO, nao reconstrucao mecanica dos SHAs
historicos. O renderer o imprime; ninguem o verifica contra o git. Enquanto for assim, ele nao
tem a mesma forca de `derived.n_findings`, e o relatorio nao deve trata-lo como se tivesse.
