# ADR 0026 — Fronteira de confiança do instalador managed executado como root

**Status:** aceito  
**Data:** 2026-08-07

## Contexto

O instalador managed existe para publicar hooks, adapters e document tools fora do espaço de escrita do ator governado. Essa propriedade é anulada se o próprio caminho privilegiado executar código vindo de um checkout ainda controlado por esse ator.

O caso concreto observado foi `apply-managed-worker.sh` executar `install/hooks-spec.sh` por `bash`. O confinamento de caminhos do manifesto e o re-hash do staging protegem contra classes importantes de drift e travessia, mas não autenticam um script-irmão executado como root.

A fronteira correta é sobre a **closure de código privilegiado**, não sobre um arquivo isolado.

```math
\mathrm{PrivilegedExec}(p)
\Rightarrow
\mathrm{TrustedSource}(p)
```

E, para toda dependência executada por `p`:

```math
\mathrm{PrivilegedExec}(p)
\Rightarrow
\forall d\in\mathrm{ExecClosure}(p):\mathrm{TrustedSource}(d).
```

## Decisão

1. `install/apply-managed.sh` trata execução com UID 0 sobre a raiz real como uma fronteira privilegiada distinta.
2. Antes de delegar para qualquer helper, o supervisor stock exige que o repositório inteiro observado por ele seja `root:root`, não contenha symlinks e não seja gravável por grupo/outros segundo os bits POSIX.
3. `TOLLENS_MANAGED_WORKER` é proibido nessa execução privilegiada real. O override permanece exclusivamente como seam de teste quando `MANAGED_PREFIX` desloca a raiz.
4. A pós-condição do deploy passa a verificar **modos exatos**, não apenas conteúdo e ausência de escrita por grupo/outros:
   - diretórios: `0755`;
   - `*.sh`: `0755`;
   - material sob `document-tools`: `0755`;
   - demais arquivos regulares: `0644`.
5. A verificação de posse usa agrupamento explícito no `find`:

```text
\( ! -user root -o ! -group root \) -print -quit
```

Isso evita o defeito anterior em que `owner!=root, group=root` podia tornar a expressão verdadeira sem executar `-print`, produzindo falso negativo.
6. Divergência de modo, permissão ou ownership após o delegado retornar sucesso é falha de commit e aciona o mesmo rollback transacional do supervisor.

## Consequências

### Positivas

- o código stock deixa de aceitar `sudo ./install/apply-managed.sh` diretamente de um checkout user-owned;
- um helper novo adicionado sob o repositório herda a mesma precondição em vez de depender de um check por arquivo;
- falha silenciosa de `chmod` deixa de poder ser mascarada por conformidade apenas de conteúdo;
- o bug de precedência do `find` ganha um caso executável sob UID 0 em prefixo isolado;
- mutation testing passa a matar mutantes específicos de rollback, modo, trust preflight e ownership.

### Limites explícitos

Esta decisão **não transforma um checkout arbitrário em software autenticado**. Um entrypoint deliberadamente adulterado antes de ser chamado com `sudo` continua sendo código que o operador escolheu executar como root; nenhum teste interno pode servir como raiz de confiança contra a própria adulteração do teste.

Assim, a claim operacional é:

> o entrypoint stock é fail-closed quando executado de uma fonte previamente colocada fora da autoridade de escrita do ator.

Não é:

> qualquer checkout user-owned pode se auto-validar com segurança depois que `sudo` já começou a executá-lo.

Também permanecem fora da claim:

- autenticidade criptográfica ou assinatura do release;
- ACLs, Linux capabilities, atributos imutáveis e semânticas de filesystem não exercitadas;
- comprometimento do administrador/host;
- terminação não observável do supervisor, como `SIGKILL` do próprio processo ou falha do host/filesystem;
- segurança de `TOLLENS_REPO` em um deployment no qual hooks managed dependam dele.

## Evidência executável

- `tests/unit/managed-root-trust.sh`: usa `sudo -n` quando disponível e cópias/prefixos isolados; não escreve em `/opt`;
- `tests/unit/managed-transaction.sh`: cobre rollback e modos exatos;
- `tests/mutation/install.sh`: cinco mutantes atribuíveis;
- `tests/unit/runtime-ports.sh`: inclui a fronteira privilegiada no gate multirruntime;
- `scripts/status.sh`: publica limites e propriedades medidas sem conservar a narrativa obsoleta do wrapper anterior.

## Nota de portabilidade

A auditoria não sustenta a afirmação de que BusyBox `stat` tenha, por si só, semântica oposta ao GNU `stat` para dereference de symlinks. O contrato relevante deve ser testado nas plataformas suportadas em vez de inferido por nome da implementação. A claim atual permanece limitada ao ambiente POSIX/GNU exercitado pela CI.

> **NOTA DE RENOMEACAO, 2026-08-12 (onda 10).** Este ADR foi escrito quando o instalador
> de fase 2 se chamava `install/apply-managed-legacy.sh` e o override `TOLLENS_MANAGED_LEGACY`.
> Os dois foram renomeados para `apply-managed-worker.sh` e `TOLLENS_MANAGED_WORKER`, e as
> mencoes acima acompanham a renomeacao para que continuem resolvendo para um arquivo que
> existe. O NOME era o defeito, nao o codigo: o script nunca foi legado - e o worker que
> `apply-managed.sh` invoca em toda instalacao, incluindo a de producao. Nome que declara
> obsolescencia sobre codigo portante convida a remocao errada.
> Nenhum comando ou saida GRAVADA foi alterado por esta renomeacao: as observacoes em
> `evidence/observations/` nao foram tocadas (conferido por `git diff --name-only`). Quem
> buscar o nome antigo no historico do git encontra ambos os lados.
