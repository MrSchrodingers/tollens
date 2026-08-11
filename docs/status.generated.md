# Estado gerado

NAO EDITAR. Gerado por `scripts/status.sh` a partir de execucao real.
O README referencia este arquivo em vez de duplicar numeros.

## Suites

| Suite | Assercoes | Exit |
|---|---:|---:|
| `tests/unit/regressao-gate.sh` | 41 | 0 |
| `tests/unit/document-tools.sh` | 21 | 0 |
| `tests/unit/supply-chain.sh` | 6 | 0 |
| `tests/unit/reprodutibilidade.sh` | variavel (ambiente) | 0 |
| `tests/unit/concorrencia.sh` | 8 | 0 |
| `tests/unit/claims.sh` | 41 | 0 |
| `tests/unit/propriedades.sh` | 22 | 0 |
| `tests/unit/fronteira-externa.sh` | 11 | 0 |
| `tests/unit/managed.sh` | 65 | 0 |
| `tests/unit/conformidade-managed.sh` | 21 | 0 |
| `tests/unit/arnes-de-mutacao.sh` | 3 | 0 |
| `tests/unit/schedule.sh` | 29 | 0 |
| `tests/unit/fronteira-viva.sh` | 55 | 0 |
| `tests/unit/literatura.sh` | 31 | 0 |
| `tests/unit/capabilities.sh` | 38 | 0 |
| `tests/unit/run.sh` | 53 | 0 |
| `tests/unit/managed-root-trust.sh` | variavel (sudo) | 0 |

## Mutacao

| Alvo | Mutantes | Exit |
|---|---:|---:|
| gate | 13 | 0 |
| contrato de subagente | 9 | 0 |
| instalador | 5 | variavel (sudo) |
| fronteira externa | 7 | 0 |
| conformidade de dois escopos | 7 | 0 |
| escalonamento | 10 | 0 |
| fronteira viva | 7 | 0 |
| camada de literatura | 10 | 0 |
| claim ledger | 2 | 0 |
| capability declarada | 7 | 0 |

## Componentes

| Tipo | Qtd |
|---|---:|
| adapter | 11 |
| agent | 10 |
| doctool | 5 |
| hook | 14 |
| skill | 9 |
| **total** | **49** |

## Limites declarados

- `allowManagedHooksOnly` continua sendo uma decisao administrativa de deploy; o repositorio nao afirma que esteja ativo em toda instalacao.
- a execucao root do instalador stock agora recusa fonte que nao seja integralmente `root:root`, livre de symlinks e sem escrita de grupo/outros; isso e uma precondicao operacional, nao autenticacao criptografica do release.
- `EVIDENCE_GATE_REPO`, quando usado por hooks managed para localizar verificadores, continua sendo uma dependencia que deve receber uma fronteira de confianca compativel com o ambiente onde for ativada.
- o ambiente de CI e auditavel, nao hermetico: `ubuntu-24.04` fixa a familia da imagem, nao seu digest, e a excecao `apt` permanece declarada.
- sem corpus proprio de desfecho, nao ha claim de superioridade universal de engenharia; a governanca de skills e evidence-gated e falsificavel.
- parsers e adaptadores documentais nao constituem sandbox de sistema operacional.
- rollback cobre falhas observadas pelo supervisor. `SIGKILL` do supervisor, falha de host/filesystem e comprometimento administrativo permanecem fora da garantia.
- ownership/mode checks usam semantica POSIX/GNU exercitada no CI; ACLs, capabilities e atributos de filesystem fora desse contrato exigem verificacao especifica antes de ampliar a claim.
- o ruleset impoe o check requerido enquanto a regra estiver ativa; administradores com autoridade para alterar a regra permanecem fora desse mecanismo.

## Propriedades de seguranca medidas

- fonte privilegiada user-owned, symlinkada ou group/world-writable e rejeitada antes da delegacao quando o supervisor roda como root na raiz real.
- `EVIDENCE_GATE_MANAGED_LEGACY` e proibido em execucao root sobre a raiz real; o override permanece apenas para ensaios com `MANAGED_PREFIX`.
- modos esperados sao revalidados apos o deploy (`0755` para diretorios/scripts/document-tools; `0644` para os demais arquivos regulares), e divergencia provoca rollback.
- ownership usa `find ... \( ! -user root -o ! -group root \) -print -quit`, evitando o bug de precedencia onde `owner!=root, group=root` podia nao produzir saida.
- confinamento de origem/destino do manifesto, re-hash do staging, restauracao transacional e verificacao de permissao continuam cobertos pelas suites managed existentes.
