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

killed = 0
for name, target, path, value in MUTANTS:
    policy = copy.deepcopy(POLICY)
    protocol = copy.deepcopy(PROTOCOL)
    set_path(policy if target == "policy" else protocol, path, value)

    with tempfile.TemporaryDirectory(prefix="tollens-method-") as raw:
        root = Path(raw)
        (root / "orchestration").mkdir()
        (root / "orchestration/skill-policy.json").write_text(json.dumps(policy), encoding="utf-8")
        (root / "orchestration/evaluation-protocol.json").write_text(json.dumps(protocol), encoding="utf-8")
        env = os.environ.copy()
        env["TOLLENS_ROOT"] = str(root)
        result = subprocess.run(
            [sys.executable, str(TESTER)],
            env=env,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    if result.returncode == 0:
        print(f"SURVIVED {name}")
    else:
        killed += 1
        print(f"KILLED {name}")

print(f"KILLED={killed}/{len(MUTANTS)}")
raise SystemExit(0 if killed == len(MUTANTS) else 1)
