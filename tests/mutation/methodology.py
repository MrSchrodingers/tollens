#!/usr/bin/env python3
from __future__ import annotations

import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
POLICY = json.loads((ROOT / "orchestration/skill-policy.json").read_text(encoding="utf-8"))
PROTOCOL = json.loads((ROOT / "orchestration/evaluation-protocol.json").read_text(encoding="utf-8"))
TESTER = ROOT / "tests/unit/methodology.py"


def set_path(document: dict, path: tuple[str, ...], value: object) -> None:
    cursor = document
    for key in path[:-1]:
        cursor = cursor[key]
    cursor[path[-1]] = value


MUTANTS = [
    ("blanket-injection", "policy", ("selection", "allow_blanket_injection"), True),
    ("sem-gatilho", "policy", ("selection", "require_observable_trigger"), False),
    ("sem-versao", "policy", ("selection", "require_version_compatibility"), False),
    ("sem-quarentena", "policy", ("lifecycle", "initial_state"), "promoted"),
    ("skill-certifica", "policy", ("claims", "skill_is_not_certifier"), False),
    ("snapshot-mutavel", "protocol", ("repository", "fixed_commit_required"), False),
    ("llm-judge", "protocol", ("verifier", "llm_as_judge_for_primary_outcome"), True),
    ("keyword-only", "protocol", ("verifier", "keyword_only_checks_prohibited"), False),
    ("existence-only", "protocol", ("verifier", "file_existence_only_checks_prohibited"), False),
    ("sem-controle-negativo", "protocol", ("verifier", "negative_control_required"), False),
    ("sem-pareamento-snapshot", "protocol", ("design", "same_task_snapshot_between_conditions"), False),
    ("sem-controle-scaffold", "protocol", ("design", "same_model_scaffold_between_paired_conditions"), False),
    ("sem-repeticao", "protocol", ("design", "repeated_trials_required_for_stochastic_agents"), False),
    ("selecao-confundida", "protocol", ("design", "skill_selection_evaluated_separately"), False),
    ("sem-incerteza", "protocol", ("analysis", "report_confidence_intervals"), False),
    ("oculta-negativos", "protocol", ("analysis", "report_null_and_negative_results"), False),
]

# ONDA 12. ESTE ARNES MATAVA POR CRASH, NAO POR ASSERCAO - achado do portao final.
#
# A raiz temporaria continha SO os dois JSON de orchestration. O tester le tambem
# `execution/skills/promoted`, `execution/agents` e as fontes de instrucao sob `execution/` e
# `docs/method/`; sem elas ele morre em `FileNotFoundError` ANTES de avaliar qualquer coisa.
# Medido: com a raiz minima e os JSON NAO MUTADOS, `python3 tests/unit/methodology.py` sai 1 com
# traceback. Logo todo `returncode != 0` era o crash, e `KILLED=16/16 EXIT=0` era sinal verde
# medindo nada - invocado ao vivo por `tests/unit/runtime-ports.sh`.
#
# A ironia e registravel: um dos proprios mutantes e `sem-controle-negativo`, e o arnes que o
# executa nao tinha controle negativo. `tests/mutation/run.sh` faz o baseline certo nos arneses
# `.sh`; so este, em Python, nao fazia.
#
# Correcao em duas partes: a raiz passa a espelhar por symlink o que o tester le (leitura apenas),
# e o CONTROLE NEGATIVO roda primeiro - raiz nao mutada tem de sair 0, senao o arnes se declara
# vacuo e reprova em vez de reportar 16/16.
LIDOS_PELO_TESTER = ("execution", "docs")


def monta_raiz(raw: str, policy: dict, protocol: dict) -> Path:
    root = Path(raw)
    (root / "orchestration").mkdir()
    (root / "orchestration/skill-policy.json").write_text(json.dumps(policy), encoding="utf-8")
    (root / "orchestration/evaluation-protocol.json").write_text(json.dumps(protocol), encoding="utf-8")
    for nome in LIDOS_PELO_TESTER:
        (root / nome).symlink_to(ROOT / nome, target_is_directory=True)
    return root


def roda(policy: dict, protocol: dict) -> int:
    with tempfile.TemporaryDirectory(prefix="tollens-method-") as raw:
        env = os.environ.copy()
        env["TOLLENS_ROOT"] = str(monta_raiz(raw, policy, protocol))
        return subprocess.run(
            [sys.executable, str(TESTER)],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        ).returncode


baseline = roda(POLICY, PROTOCOL)
if baseline != 0:
    print(f"BASELINE VERMELHO (exit={baseline}): a raiz NAO MUTADA ja reprova.")
    print("Sem baseline verde, todo 'KILLED' abaixo seria crash e nao assercao - o arnes e VACUO.")
    raise SystemExit(1)
print("baseline verde: raiz nao mutada sai 0")

killed = 0
for name, target, path, value in MUTANTS:
    policy = copy.deepcopy(POLICY)
    protocol = copy.deepcopy(PROTOCOL)
    set_path(policy if target == "policy" else protocol, path, value)

    if roda(policy, protocol) == 0:
        print(f"SURVIVED {name}")
    else:
        killed += 1
        print(f"KILLED {name}")

print(f"KILLED={killed}/{len(MUTANTS)}")
raise SystemExit(0 if killed == len(MUTANTS) else 1)
