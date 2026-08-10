#!/usr/bin/env python3
"""Conformidade DECLARADA de ferramentas de subagente - a metade ESTATICA do probe.

POR QUE ESTE ARQUIVO EXISTE, E O QUE ELE NAO PROVA
----------------------------------------------------
A pergunta que interessa e RuntimeConformant(a,r): o conjunto de ferramentas que o runtime
CONCEDE em execucao a um agente `a` (ObservedCapabilities) e exatamente o conjunto listado em
`tools:` no frontmatter dele (DeclaredCapabilities)? Nem mais, nem menos.

Este script NAO responde essa pergunta. Ele fecha uma metade mais estreita e mais barata:

    DeclaredCapabilities(execution/agents/X.md) == DeclaredCapabilities(<instalado>/agents/X.md)

isto e, que as fontes que DECLARAM capacidade concordam entre si. Isso e necessario mas nao
suficiente: um agente pode ser instalado com `tools:` identico ao canonico e mesmo assim o
runtime conceder mais do que essa linha diz - foi exatamente o que uma sessao real capturou
para `refutador` (ver evidence/observations/2026-08-10-capacidade-declarada-vs-observada.md).
Fechar so a metade declarada e valioso, mas chama-la de "conformidade" sem qualificar seria o
MESMO erro epistemologico de tests/unit/methodology.py: esse arquivo valida que
orchestration/skill-policy.json e orchestration/evaluation-protocol.json contem as constantes
que eles mesmos declaram - nunca observa uma execucao real. Comparar frontmatter contra
frontmatter tem a mesma limitacao estrutural: sao TRES fontes de texto declarado (canonica,
projecao do repo, instalada), nunca o comportamento do runtime.

A metade OBSERVADA exige uma sessao capaz de delegar a agentes reais e ler o resultado - isto
e, o protocolo em evidence/runtime-probes/capabilities.md, executado pelo ORQUESTRADOR (uma
sessao principal, nunca um subagente: subagente nao cria subagente).

O QUE ESTE SCRIPT VERIFICA
---------------------------
Para cada `execution/agents/<nome>.md` (a fonte canonica):
  1. O `tools:` do frontmatter e extraido como um CONJUNTO (a ORDEM dos nomes nao importa -
     medido: a projecao do repo para `tdd` lista as mesmas seis ferramentas em ordem diferente
     da fonte canonica, e isso NAO e divergencia).
  2. O mesmo campo e extraido de `.claude/agents/<nome>.md` (projecao local deste repositorio,
     gerada por `orchestration/render.py` - um estipe DIFERENTE do arquivo canonico, com corpo
     truncado e campos extras como `permissionMode`, mas que declara `tools:` de novo).
  3. O mesmo campo e extraido de `<CLAUDE_HOME>/agents/<nome>.md` (a copia instalada que o
     runtime de fato carrega; `CLAUDE_HOME` segue a mesma convencao de `install/verify.sh`,
     default `$HOME/.claude`).
  4. Os tres conjuntos precisam ser IDENTICOS. Arquivo ausente numa das dependencias e
     NAO_VERIFICADO (nao se pode concluir conformidade nem divergencia); conjunto diferente e
     VIOLACAO.

`orchestration/render.py --check` ja confere que as tres arvores existem e que os workflows sao
validos; ele NAO confere que `tools:` case entre elas (registry.json nem armazena a lista de
ferramentas). Este script fecha exatamente essa lacuna, sem duplicar a logica de render.py.

LIMITE DECLARADO
-----------------
- So compara TEXTO declarado. Nao invoca nenhum agente, nao inspeciona `~/.claude/logs` nem
  transcritos de sessao - isso e do protocolo runtime, deliberadamente fora deste arquivo.
- So confere `.codex/agents/*.toml`? NAO. O runtime Codex usa `sandbox_mode` (um modelo de
  sandbox de SO), nao uma allowlist de nomes de ferramenta - comparar os dois exigiria uma
  ontologia de equivalencia que nao existe hoje, entao fica fora de escopo (nao "resolvido em
  silencio").
"""
from __future__ import annotations

import os
import re
import sys
from pathlib import Path

EXIT_OK, EXIT_VIOLACAO, EXIT_NAO_VERIFICADO = 0, 1, 2

DEFAULT_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("EVIDENCE_GATE_ROOT", DEFAULT_ROOT)).resolve()
CLAUDE_HOME = Path(os.environ.get("CLAUDE_HOME", Path.home() / ".claude")).resolve()

RE_TOOLS = re.compile(r"^tools:\s*(.+)$")


def frontmatter_lines(caminho: Path) -> list[str] | None:
    """Linhas ENTRE os dois `---` do frontmatter YAML. None = arquivo ausente ou sem
    frontmatter fechado (indecidivel, nao ausencia de divergencia)."""
    try:
        linhas = caminho.read_text(encoding="utf-8").splitlines()
    except OSError:
        return None
    if not linhas or linhas[0].strip() != "---":
        return None
    for i, linha in enumerate(linhas[1:], start=1):
        if linha.strip() == "---":
            return linhas[1:i]
    return None


def tools_declarados(caminho: Path) -> frozenset[str] | None:
    """Conjunto de ferramentas em `tools:`. None = indecidivel (arquivo ausente, sem
    frontmatter, ou frontmatter sem a chave `tools:`)."""
    fm = frontmatter_lines(caminho)
    if fm is None:
        return None
    for linha in fm:
        m = RE_TOOLS.match(linha)
        if m:
            valores = frozenset(t.strip() for t in m.group(1).split(",") if t.strip())
            return valores if valores else None
    return None


def main() -> int:
    # `--repo-only` COMPARA SO AS DUAS ARVORES INTERNAS AO REPOSITORIO.
    #
    # Existe para a CI. Num runner limpo `CLAUDE_HOME/agents` nao existe, e a perna instalada
    # sai NAO_VERIFICADO (exit 2) - correto localmente, mas transformaria um passo de CI em
    # vermelho permanente por ausencia esperada, o que ensina a ignorar o passo.
    #
    # O que ele NAO faz: afrouxar. A comparacao `execution/agents` x `.claude/agents` continua
    # exit 1 em divergencia e exit 2 se qualquer das duas arvores faltar. A perna descartada e
    # DECLARADA aqui e na saida, nao silenciada - e continua valendo na execucao local, que e
    # onde `CLAUDE_HOME` existe.
    #
    # Valor colateral: `orchestration/render.py --check` so verifica que a projecao EXISTE.
    # Esta comparacao de conteudo fecha parte dessa lacuna semantica para o campo `tools:`.
    repo_only = "--repo-only" in sys.argv
    canon_dir = ROOT / "execution" / "agents"
    repo_proj_dir = ROOT / ".claude" / "agents"
    home_dir = CLAUDE_HOME / "agents"

    canon_files = sorted(canon_dir.glob("*.md"))
    if not canon_files:
        sys.stderr.write(
            f"NAO VERIFICADO: nenhum agente canonico em {canon_dir} - "
            f"o contrato de extracao nao tem o que comparar.\n")
        return EXIT_NAO_VERIFICADO

    violacoes: list[str] = []
    nao_verificados: list[str] = []
    ok = 0

    for canon_path in canon_files:
        nome = canon_path.stem
        t_canon = tools_declarados(canon_path)
        if t_canon is None:
            violacoes.append(f"{nome}: fonte canonica {canon_path} sem `tools:` legivel "
                              f"- isto e defeito estrutural, nao ausencia de dado")
            continue

        fontes = {"projecao do repo (.claude/agents)": repo_proj_dir / f"{nome}.md"}
        if not repo_only:
            fontes["instalada (CLAUDE_HOME/agents)"] = home_dir / f"{nome}.md"

        divergiu = False
        for rotulo, caminho in fontes.items():
            if not caminho.is_file():
                nao_verificados.append(f"{nome}: {rotulo} ausente em {caminho}")
                divergiu = True
                continue
            t_outra = tools_declarados(caminho)
            if t_outra is None:
                nao_verificados.append(f"{nome}: {rotulo} existe mas `tools:` nao pode ser "
                                        f"lido em {caminho}")
                divergiu = True
                continue
            if t_outra != t_canon:
                falta = sorted(t_canon - t_outra)
                sobra = sorted(t_outra - t_canon)
                detalhe = []
                if falta:
                    detalhe.append(f"ausentes ali: {', '.join(falta)}")
                if sobra:
                    detalhe.append(f"a mais ali: {', '.join(sobra)}")
                violacoes.append(
                    f"{nome}: {rotulo} DIVERGE do canonico ({'; '.join(detalhe)})")
                divergiu = True

        if not divergiu:
            ok += 1
            print(f"PASS {nome}: tools: identico nas 3 fontes ({', '.join(sorted(t_canon))})")

    total = len(canon_files)
    print(f"\nagentes canonicos: {total} | conformes: {ok} | "
          f"divergentes: {len(violacoes)} | nao verificados: {len(nao_verificados)}")

    if violacoes:
        print("\nVIOLACOES (tools: declarado diverge entre fontes):")
        for v in violacoes:
            print(f"  - {v}")
    if nao_verificados:
        print("\nNAO VERIFICADO (fonte ausente ou ilegivel - nao decide conformidade):")
        for v in nao_verificados:
            print(f"  - {v}")

    print("\nISTO FECHA APENAS A METADE DECLARADA. ObservedCapabilities (o que o runtime "
          "realmente concede em execucao) NAO foi medido aqui - ver "
          "evidence/runtime-probes/capabilities.md.")

    if violacoes:
        return EXIT_VIOLACAO
    if nao_verificados:
        return EXIT_NAO_VERIFICADO
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
