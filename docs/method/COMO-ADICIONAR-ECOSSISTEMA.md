# Como adicionar um ecossistema

Nao se edita hook. Cria-se `camada1-toolchain/adapters/<nome>.json`.

## A unica pergunta que importa

Para cada comando: **ele executa codigo que vem do repositorio?**

Se sim, e `test` e exige aprovacao de root. Se nao, e `analyzer` e roda automaticamente.
Em duvida, e `test` - o custo do erro e execucao de comando arbitrario por um repo clonado
(classe CVE-2025-59536, ja reproduzida neste projeto).

Casos que enganam, todos ja pagos:

| Parece analisador | Mas executa |
|---|---|
| `cargo check` | `build.rs` |
| `dotnet build` | targets MSBuild do `.csproj` (`Exec Command=...`) |
| `npx --no-install tsc` | binario em `node_modules/.bin` do repo |
| `mypy` | plugin declarado em `mypy.ini`/`pyproject` |
| `mvn` / `gradle` | plugins e tarefas declarados pelo repo |
| `pytest` | `conftest.py` |

## Passos

1. Copie um adaptador existente como molde.
2. `detect`: arquivos que indicam o ecossistema (aceita glob).
3. `analyzer.cmd` + `analyzer.porque_nao_executa` - a justificativa e **obrigatoria** e a
   suite reprova sem ela. Ela e o ponto de revisao humana.
4. `test.cmd` + `executa_codigo_do_repo: true`.
5. `extensoes`: usadas para decidir se o diff tocou este ecossistema.
6. `rejeitados`: comandos que voce considerou e descartou, com o motivo. Evita que alguem os
   adicione depois por parecerem analisadores.
7. `python3 evidence/validate-adapters.py` - conformidade de schema; e
   `bash tests/mutation/adaptadores.sh` - validacao por mutacao do contrato. Os dois rodam na CI.

Nenhuma linha de shell e necessaria.
