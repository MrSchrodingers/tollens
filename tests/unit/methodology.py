#!/usr/bin/env python3
from __future__ import annotations

import json
import os
from pathlib import Path

DEFAULT_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("TOLLENS_ROOT", DEFAULT_ROOT)).resolve()
policy = json.loads((ROOT / "orchestration/skill-policy.json").read_text(encoding="utf-8"))
protocol = json.loads((ROOT / "orchestration/evaluation-protocol.json").read_text(encoding="utf-8"))

checks: list[tuple[bool, str]] = []


def check(condition: bool, message: str) -> None:
    checks.append((condition, message))
    print(("PASS" if condition else "FAIL") + " " + message)


selection = policy["selection"]
check(policy["schema_version"] == 1, "schema da politica conhecido")
check(policy["default_activation"] == "off", "skill injection desligada por default")
check(selection["mode"] == "evidence-gated", "selecao de skill exige evidencia")
check(selection["require_observable_trigger"] is True, "gatilho observavel obrigatorio")
check(selection["require_repository_compatibility"] is True, "compatibilidade com repositorio obrigatoria")
check(selection["require_version_compatibility"] is True, "compatibilidade de versao obrigatoria")
check(selection["allow_blanket_injection"] is False, "injecao blanket proibida")
check(selection["max_selected_skills_per_task"] == 1, "composicao multi-skill permanece desabilitada sem avaliacao")

lifecycle = policy["lifecycle"]
check(lifecycle["initial_state"] == "quarantine", "skill nova inicia em quarentena")
check(set(lifecycle["states"]) == {"quarantine", "candidate", "promoted", "deprecated", "rejected"}, "estados de lifecycle fechados")
required = set(lifecycle["promotion_requires"])
check({
    "paired_evaluation",
    "fixed_repository_snapshot",
    "deterministic_requirement_verifier",
    "compatibility_manifest",
    "negative_control",
    "cost_measurement",
    "context_interference_check",
} <= required, "promocao cobre baseline, snapshot, oraculo, compatibilidade, custo e interferencia")
check({"negative_correctness_delta", "version_mismatch", "security_regression", "verifier_invalidated"} <= set(lifecycle["deprecate_on"]), "depreciacao cobre regressao e invalidacao")
claims = policy["claims"]
check(claims["skill_is_not_authority"] is True, "skill nao e autoridade")
check(claims["skill_is_not_certifier"] is True, "skill nao certifica a propria eficacia")
check(claims["self_generated_skill_requires_quarantine"] is True, "skill auto-gerada exige quarentena")

check(protocol["schema_version"] == 1, "schema do protocolo conhecido")
check(protocol["unit"] == "repository_task_trial", "unidade experimental explicita")
check(protocol["task_tuple"] == ["repository", "environment", "requirement", "skill_condition", "agent_scaffold", "model", "trial"], "tupla experimental controla scaffold, modelo e trial")
repository = protocol["repository"]
check(repository["fixed_commit_required"] is True, "snapshot fixo por tarefa")
check(repository["container_or_immutable_environment_required"] is True, "ambiente reproduzivel obrigatorio")
requirement = protocol["requirement"]
check(requirement["self_sufficient"] is True, "requisito autocontido")
check(requirement["acceptance_criteria_required"] is True, "criterios de aceitacao obrigatorios")
check(requirement["must_not_leak_skill_content"] is True, "requisito nao vaza conteudo da skill")
check(requirement["traceability_required"] is True, "rastreabilidade requisito-oraculo obrigatoria")

verifier = protocol["verifier"]
check(verifier["deterministic"] and verifier["execution_based"], "desfecho primario e deterministico e executado")
check(verifier["llm_as_judge_for_primary_outcome"] is False, "LLM-as-judge nao decide outcome primario")
check(verifier["keyword_only_checks_prohibited"] is True, "oraculo keyword-only proibido")
check(verifier["file_existence_only_checks_prohibited"] is True, "oraculo existence-only proibido")
check(verifier["edge_cases_required"] is True, "casos de borda obrigatorios")
check(verifier["negative_control_required"] is True, "controle negativo obrigatorio")

design = protocol["design"]
check(design["paired_conditions"] == ["without_skill", "with_skill"], "contraste pareado explicito")
check(design["same_task_snapshot_between_conditions"] is True, "snapshot identico entre condicoes")
check(design["same_environment_between_conditions"] is True, "ambiente identico entre condicoes")
check(design["same_model_scaffold_between_paired_conditions"] is True, "modelo e scaffold controlados no par")
check(design["repeated_trials_required_for_stochastic_agents"] is True, "agentes estocasticos exigem repeticao")
check(design["record_execution_order"] is True, "ordem de execucao registrada")
check(design["skill_selection_evaluated_separately"] is True, "retrieval/selecao nao se confunde com utilidade")

metrics = protocol["metrics"]
check({"requirement_pass_rate", "paired_correctness_delta"} <= set(metrics["primary"]), "metricas primarias preservam requisito e delta pareado")
check({"token_cost", "wall_clock_latency", "tool_calls", "test_runs"} <= set(metrics["secondary"]), "custo, latencia e atividade medidos")
check({"security_regressions", "scope_violations", "context_interference_failures"} <= set(metrics["safety"]), "seguranca, escopo e interferencia medidos")
check({"selection_precision", "selection_recall", "unnecessary_injection_rate"} <= set(metrics["selection"]), "qualidade do seletor medida separadamente")

analysis = protocol["analysis"]
check(analysis["report_confidence_intervals"] is True, "incerteza estatistica reportada")
check(analysis["report_discordant_pairs"] is True, "pares discordantes reportados")
check(analysis["separate_model_scaffold_results"] is True, "resultados estratificados por modelo e scaffold")
check(analysis["report_null_and_negative_results"] is True, "resultados nulos e negativos nao sao ocultados")
check(analysis["no_universal_skill_claim_from_single_model"] is True, "um modelo nao sustenta claim universal")
check(analysis["no_universal_scaffold_claim_from_single_scaffold"] is True, "um scaffold nao sustenta claim universal")

failed = sum(not ok for ok, _ in checks)
print(f"TOTAL={len(checks)} FAIL={failed}")
raise SystemExit(1 if failed else 0)
