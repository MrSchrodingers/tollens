# Windows: configurar o tollens no Claude Code Desktop

## Pré-requisitos

Claude Desktop atualizado, Git for Windows com Git Bash, Python 3, `jq` e o repositório clonado.

## Validar

```powershell
git clone https://github.com/MrSchrodingers/tollens.git
Set-Location tollens
python .\orchestration\render.py --check
```

No Git Bash:

```bash
bash tests/unit/runtime-ports.sh
bash tests/unit/managed.sh
bash tests/mutation/install.sh
```

## Abrir

Na aba Code: nova sessão, ambiente Local, selecione a pasta, comece em Plan e revise `.claude/settings.json`, `.claude/hooks/` e `.claude/agents/` antes de confiar.

Prompt inicial:

```text
Use o workflow standard-change. Execute investigador e mapeador-dependencias em paralelo, sem escrita. Apresente o plan gate. Depois use tdd e implementador serialmente em worktree. Finalize com revisor-codigo e refutador. O resultado local máximo é CANDIDATE; não declare merge sem verify-pr no SHA final.
```

Para instalador, autorização, parser, dependência ou CI, use `high-risk-change`.

## Instalação global opcional

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install\apply-claude-global.ps1 -DryRun
.\install\apply-claude-global.ps1
.\install\apply-claude-global.ps1 -Verify
```

Se Git Bash estiver fora do padrão, defina `CLAUDE_CODE_GIT_BASH_PATH`. A instalação global continua `governed=user`; configuração por projeto é preferível.
