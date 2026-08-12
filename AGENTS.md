# tollens — Codex

Fonte normativa: `orchestration/registry.json` e `orchestration/workflows/*.json`. Use no máximo quatro subagentes de leitura em paralelo. Nunca execute dois escritores no mesmo workspace. `tdd` produz RED, `implementador` corrige, `revisor-codigo` e `refutador` avaliam. Estado terminal local: `CANDIDATE`; merge depende de `verify-pr`.
