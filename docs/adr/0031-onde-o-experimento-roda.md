# ADR 0031 - Onde o experimento roda

Data: 2026-08-17
Estado: aceito
Precede: ADR 0032 (referencia publicada que nao resolve)
Sucede parcialmente: ADR 0028 (mutacao nao cobre decisao), ADR 0030 (o verificador instalado)

## Contexto

Ate 2026-08-14 os treze arneses de `tests/mutation/` alteravam um arquivo de PRODUCAO na arvore
de trabalho e o restauravam no `trap`. A suite era verde e o desenho parecia correto: toda
mutacao tinha restauracao pareada.

Restauracao e uma propriedade. Isolamento e outra:

```
EventuallyRestored  NAO IMPLICA  NeverObservableAsMutant
```

Durante a janela entre mutar e restaurar, qualquer leitor da arvore observa o mutante e o trata
como estado real. Seis incidentes distintos em dois dias decorreram disso, todos medidos e
listados no cabecalho de `tests/lib/arena.sh:12-23`. O pior deles nao foi um teste vermelho: foi
`install/manifest.sh` gravando o digest de um mutante como estado DESEJADO do sistema.

O agravante estrutural: `scripts/status.sh --check` executa os arneses. O verificador do
documento de estado e ele mesmo um mutador de estado.

## Decisao

O arnes deixa de operar na arvore candidata. `tests/lib/arena.sh`, sourced pelos treze, copia a
arvore para `$TMPDIR/tollens-arena.XXXXXXXX` e faz `cd`. Como os arneses ja usavam caminhos
relativos a raiz, nada mais mudou neles alem da diretiva de source.

`git worktree` foi considerado e REJEITADO por tres razoes medidas nesta estacao
(`tests/lib/arena.sh:36-43`): materializa um commit e nao a arvore suja que o arnes precisa
testar; os bind mounts do runtime em `.git/worktrees` fazem `git worktree remove` devolver
"Device or resource busy"; e `.git/config` e read-only sob a politica managed.

## O que a revisao independente encontrou, e e o registro que importa

Nove defeitos graves em tres rodadas, todos meus, nenhum visivel em inspecao do diff.

| rodada | achados |
|---|---|
| `revisor-codigo` | varredura apagava arena EM USO; `AM4` observava arena de outro processo; a suite rodava sem `trap` em dois pontos |
| `refutador` | o `trap` recem-adicionado APAGAVA trabalho nao commitado; `trap` sem `exit` fazia o bash retomar e ignorar o sinal; a assercao era derrotada pelo comentario que o mesmo commit adicionou |
| CI | dois vermelhos corretos em `verify-live-policy` |

Os tres do `refutador` estavam DENTRO das correcoes dos tres do `revisor-codigo`.

Dois merecem registro nominal:

**A arena recriou o incidente que existe para eliminar.** O cabecalho afirmava, em prosa, que a
varredura "nunca remove arena em uso, porque nenhum arnes roda por uma hora". O codigo media
relogio. `tar -xf -` aplica o mtime da RAIZ DA FONTE sobre o destino, entao a arena nascia com
tres dias de idade e o `-mmin +60` casava no instante zero. Uma arena de processo vivo foi
removida, e o arnes morreu com `FAIL regressao baseline vermelha` - vermelho plausivel e falso,
exatamente o incidente 4 da lista que justifica o arquivo. A correcao trocou relogio por
PROPRIEDADE: `.arena-pid` mais `kill -0`.

**A assercao sobrevivia ao proprio mutante.** O detector era `grep -L 'lib/arena.sh'`, e o
comentario que o mesmo commit adicionou aos treze arneses continha a string. Removida a diretiva
de source, a assercao continuava verde. A regra 2 da metodologia - remova a garantia e exija que
o teste reprove - reprovada pelo teste que ela governa.

## Limites, declarados

A arena isola a ARVORE, nao o SISTEMA. Um arnes que escreva em `~/.claude`, `/opt/tollens` ou
`/etc` continua escapando. Nenhum dos treze faz isso, conferido por grep; o proximo pode.

A divida M1-M7 foi nomeada no PR #19 e a maior parte dela foi fechada na onda seguinte, no mesmo
dia - ver ADR 0032. M1 era: `tollens-arena-of.<pid>` em `/tmp` 1777 com nome previsivel, escrita
com falha engolida e leitura sem validacao, quando `tests/lib/lock.sh:56-74` ja resolvera esta
exata classe neste repositorio, apos auditoria, com diretorio 0700 por usuario. A arena nao
reusou o mecanismo que o repositorio ja tinha.

**E havia coisa pior que M1, que esta onda nao viu.** A auditoria da onda 12 encontrou, na
varredura de limpeza escrita AQUI, um primitivo de destruicao de diretorio arbitrario: o glob
terminava em barra (`tollens-arena.*/`), e barra final faz `-d`, `find` e `rm -rf`
ATRAVESSAREM symlink. Com `/tmp` em 1777, qualquer usuario local plantava
`tollens-arena.pwn -> ~/.claude` e o proximo dos treze arneses apagava o alvo. Reproduzido
executando o bloco literal deste arquivo contra um symlink.

A arena existe para impedir que o experimento destrua estado, e continha o pior primitivo de
destruicao do repositorio - noventa linhas acima do M1 que a onda seguinte estava corrigindo. As
duas revisoes desta onda leram esse laco e nenhuma o pegou; foi preciso um auditor com scanner e
disposicao de EXECUTAR o codigo contra um alvo plantado.

## Nota de metodo

Escrevi o ADR 0030 sobre verificador que verifica proposicao mais fraca que a anunciada. Nas 48
horas seguintes cometi essa forma seis vezes, incluindo dentro das correcoes dela. Conhecer o
padrao nao protege contra comete-lo. O que funcionou, sem excecao, foi contexto separado
REFAZENDO a medicao em vez de aceitar a minha.
