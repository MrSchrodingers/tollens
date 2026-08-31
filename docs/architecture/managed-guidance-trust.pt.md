# Trust root transitiva do guidance managed

Estado: **CANDIDATO — depende do merge/CI do PR #35**  
Data: 2026-08-25  
Relacionado: G25, issue #31

## O defeito

A primeira descrição de G25 dizia que o hook managed `read-budget.sh` executava diretamente um doctool gravável pelo usuário. Essa descrição era forte demais.

O comportamento real era:

```text
hook managed root-owned
  -> lê registry de adaptadores
  -> constrói mensagem de bloqueio
  -> publica uma receita contendo o caminho do doctool
  -> o agente pode executar essa receita depois
```

O defeito continua material: uma regra imposta podia orientar o agente a executar um helper pertencente ao espaço de escrita do próprio ator governado. Mas a propriedade correta é **guidance-to-executable**, não execução direta pelo hook.

## Invariante

Quando `read-budget.sh` é executado a partir de uma árvore managed cuja raiz física termina em `/opt/tollens/hooks`:

```text
DOCTOOL = <mesma trust root>/document-tools/doctool.sh
DOCREG  = <mesma trust root>/adapters/documents
```

`HOME`, `DOCTOOL_BIN` e `DOC_ADAPTERS_DIR` fornecidos pelo ator não podem mudar esses dois referentes nesse modo.

Fora da árvore managed, o comportamento user-scope é preservado e overrides explícitos continuam válidos.

## Por que a localização do hook

A classificação não depende de um rótulo `managed=true` controlável pelo chamador. Ela deriva do caminho físico do próprio hook instalado. O prefixo de ensaio também termina em `/opt/tollens/hooks`, permitindo testar a propriedade sem sudo.

Isso segue o princípio:

```text
Observe/derive > trust declaration
```

## Oracle

`tests/unit/managed-transitive-trust.sh` cria simultaneamente:

- uma árvore managed de fixture;
- um registry e doctool managed;
- `HOME` + overrides hostis, mas válidos;
- uma cópia user-scope de controle.

O caso managed deve publicar apenas o adapter/doctool da trust root. O controle user-scope deve continuar usando seus paths configurados.

`tests/mutation/managed-transitive-trust.sh` torna o branch de localização managed inalcançável. A suite deve reprovar. Uma edição inerte permanece verde.

## Limites

Este mecanismo não demonstra:

- sandbox de Bash;
- que o modelo sempre seguirá ou nunca seguirá a receita;
- segurança de toda guidance;
- utilidade causal de `read-budget`;
- integridade das capabilities que ainda vivem em user-scope.

Ele demonstra uma propriedade mais estreita: **a receita produzida pelo `read-budget` managed não deriva helper/registry do espaço gravável do usuário**.
