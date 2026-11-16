# Mutantes de `evidence/hooks/model-honor.sh`

Prova da regra 3 do ADR 0015 para o numero "N de M mutantes mortos" do ADR 0048.

- `gen.py <saida> <hook>`: escreve um hook mutante por troca textual (ancora obrigatoria) e a lista de equivalentes.
- `um.sh <mutante> <resultado>`: roda `tests/unit/model-honor.sh` contra um mutante (via `MODEL_HONOR_HOOK`).
- `run-all.sh`: gera, roda 4 em paralelo num diretorio temporario e resume.

```
ROOT="$(git rev-parse --show-toplevel)"
bash "$ROOT/tests/mutation/model-honor/run-all.sh"
```

Saida: `MORTOS=<n> DE=<m>`, os vivos e os equivalentes declarados. Exit 0 se so sobreviveram
equivalentes; 1 se algum mutante nao equivalente sobreviveu; 2 se o instrumento falhou. Dura
alguns minutos; nao entra em `tests/unit/run.sh` nem na lista de `tests/mutation/*.sh`.
