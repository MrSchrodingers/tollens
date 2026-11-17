# Mutantes de `evidence/hooks/model-honor.sh`

Prova da regra 3 do ADR 0015 para o numero "N de M mutantes mortos" do ADR 0048.

- `gen.py <saida> <hook>`: escreve um hook mutante por troca textual (ancora obrigatoria) e a lista de equivalentes.
- `um.sh <mutante> <resultado>`: roda `tests/unit/model-honor.sh` contra um mutante (via `MODEL_HONOR_HOOK`).
- `resumo.sh <resultado> <equivalentes>`: classifica cada mutante em morto (caso FAIL nomeado), vivo (rc 0) ou inconclusivo (rc != 0 sem caso nomeado: timeout, contagem inesperada, dependencia ausente).
- `run-all.sh`: gera, roda 2 em paralelo (`MODEL_HONOR_MUT_PARALELO`) e resume; o arquivo de resultado e gravado a cada mutante e fica no disco (caminho impresso no inicio).

```
ROOT="$(git rev-parse --show-toplevel)"
bash "$ROOT/tests/mutation/model-honor/run-all.sh"
```

Saida: uma linha `MUTANTE <ID> <morto|vivo|inconclusivo> casos=<...>` por mutante e
`MORTOS=<n> DE=<m> INCONCLUSIVOS=<k>`. Exit 0 se todo mutante nao equivalente morreu e nada ficou
inconclusivo; 1 se algum nao equivalente sobreviveu; 2 se ha inconclusivo ou o instrumento falhou.
Dura de alguns a dezenas de minutos conforme a carga da maquina; nao entra em
`tests/unit/run.sh` nem na lista de `tests/mutation/*.sh`.
