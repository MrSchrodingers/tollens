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
     default `$HOME/.claude`). Com `--repo-only`, este passo NAO RODA - a saida declara o numero
     de fontes efetivamente comparadas (2, nao 3) e diz explicitamente que a perna instalada
     ficou de fora; nunca reporta "identico nas 3 fontes" tendo comparado so 2.
  4. Os conjuntos comparados nesta execucao precisam ser IDENTICOS. Arquivo ausente numa das
     dependencias, ou frontmatter que nao fecha, e NAO_VERIFICADO (nao se pode concluir
     conformidade nem divergencia). Conjunto diferente e VIOLACAO - inclusive quando a diferenca
     e uma chave `tools:` OMITIDA numa projecao: pela doc primaria do Claude Code, omitir
     `tools:` faz o subagente herdar TODAS as ferramentas disponiveis (a concessao MAXIMA), o que
     e decidivel e diverge de qualquer lista finita do canonico - nao e lacuna, e VIOLACAO.

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

import argparse
import os
import re
import sys
from pathlib import Path

EXIT_OK, EXIT_VIOLACAO, EXIT_NAO_VERIFICADO = 0, 1, 2

DEFAULT_ROOT = Path(__file__).resolve().parents[2]
ROOT = Path(os.environ.get("EVIDENCE_GATE_ROOT", DEFAULT_ROOT)).resolve()
CLAUDE_HOME = Path(os.environ.get("CLAUDE_HOME", Path.home() / ".claude")).resolve()

ROTULO_PROJECAO = "projecao do repo (.claude/agents)"
ROTULO_INSTALADA = "instalada (CLAUDE_HOME/agents)"
ROTULO_CANONICA = "canonica (execution/agents)"

RE_TOOLS = re.compile(r"^tools:\s*(.+)$")  # forma INLINE: `tools: A, B, C` numa unica linha.
RE_TOOLS_CHAVE_BLOCO = re.compile(r"^tools:\s*$")  # a mesma chave sem valor na linha - abre,
                                                     # potencialmente, uma lista YAML de BLOCO.
RE_ITEM_BLOCO = re.compile(r"^\s*-\s*(.+?)\s*$")  # item `  - Nome` de uma lista de bloco.


class _ChaveToolsAusente:
    """Sentinela devolvida por `tools_declarados`: o frontmatter FECHOU e foi lido por inteiro,
    e mesmo assim nenhuma lista `tools:` foi encontrada (nem inline, nem em bloco) - chave
    omitida, ou presente e vazia. Isto e DIFERENTE de `None` (arquivo ausente ou frontmatter que
    nao fecha, onde nada pode ser concluido): aqui o documento foi lido ate o fim e a ausencia da
    chave e ela mesma o dado. Pela tabela de frontmatter da doc primaria do Claude Code
    (https://code.claude.com/docs/en/sub-agents, campo `tools`: "Inherits every tool available to
    subagents if omitted"), omitir `tools:` faz o subagente HERDAR TODAS as ferramentas - a
    concessao MAXIMA, o oposto de uma lacuna indecidivel."""


TOOLS_AUSENTE = _ChaveToolsAusente()


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


def tools_declarados(caminho: Path) -> frozenset[str] | _ChaveToolsAusente | None:
    """Conjunto de ferramentas em `tools:`, em qualquer uma das DUAS formas que o frontmatter
    YAML aceita para uma chave de lista: inline (`tools: A, B`) ou bloco (`tools:` seguido de
    `  - A` / `  - B` nas linhas seguintes). Um parser que so reconhecesse a forma inline
    tornaria uma lista de bloco indistinguivel de uma chave omitida - o MESMO erro de
    classificacao que `TOOLS_AUSENTE` existe para corrigir, so que reintroduzido pela LEITURA em
    vez da decisao.

    Retorno:
      None            = indecidivel: arquivo ausente ou frontmatter que nao fecha.
      TOOLS_AUSENTE   = frontmatter fechado e lido por inteiro, mas nenhuma lista `tools:` foi
                        encontrada - ver a doutrina no docstring de `_ChaveToolsAusente`.
      frozenset[str]  = a lista declarada, com pelo menos um nome de ferramenta.
    """
    fm = frontmatter_lines(caminho)
    if fm is None:
        return None
    for i, linha in enumerate(fm):
        m = RE_TOOLS.match(linha)
        if m:
            valores = frozenset(t.strip() for t in m.group(1).split(",") if t.strip())
            return valores if valores else TOOLS_AUSENTE
        if RE_TOOLS_CHAVE_BLOCO.match(linha):
            itens = []
            for seguinte in fm[i + 1:]:
                m_item = RE_ITEM_BLOCO.match(seguinte)
                if not m_item:
                    break
                item = m_item.group(1).strip()
                if item:
                    itens.append(item)
            return frozenset(itens) if itens else TOOLS_AUSENTE
    return TOOLS_AUSENTE


def parse_args(argv: list[str]) -> argparse.Namespace:
    """Argumentos de linha de comando. `argparse` recusa qualquer flag desconhecida com exit 2
    (SystemExit) e mensagem em stderr - o mesmo codigo de EXIT_NAO_VERIFICADO deste script, o que
    e a leitura correta: um invocador que passa algo que este programa nao reconhece nao pode ter
    seu pedido decidido, entao "nao verificado" (e nao "modo completo por omissao silenciosa") e
    a unica resposta honesta. Antes, `"--repo-only" in sys.argv` aceitava QUALQUER outro token sem
    reclamar - `--repoonly` (erro de digitacao) rodava o modo completo calado, sem avisar que o
    filtro pedido nunca foi aplicado."""
    ap = argparse.ArgumentParser(
        description="Compara `tools:` do frontmatter entre a fonte canonica, a projecao do "
                    "repo e (fora de --repo-only) a copia instalada em CLAUDE_HOME.")
    ap.add_argument(
        "--repo-only", action="store_true",
        help="compara so execution/agents x .claude/agents; NAO verifica CLAUDE_HOME/agents "
             "(uso: CI, onde a perna instalada nao existe no runner)")
    return ap.parse_args(argv)


def main() -> int:
    args = parse_args(sys.argv[1:])
    repo_only = args.repo_only

    # `--repo-only` COMPARA SO AS DUAS ARVORES INTERNAS AO REPOSITORIO.
    #
    # Existe para a CI. Num runner limpo `CLAUDE_HOME/agents` nao existe, e a perna instalada
    # sai NAO_VERIFICADO (exit 2) - correto localmente, mas transformaria um passo de CI em
    # vermelho permanente por ausencia esperada, o que ensina a ignorar o passo.
    #
    # O que ele NAO faz: afrouxar. A comparacao `execution/agents` x `.claude/agents` continua
    # exit 1 em divergencia e exit 2 se qualquer das duas arvores faltar. A perna descartada NAO
    # E VERIFICADA neste modo - nem PASS nem FAIL sao emitidos para ela - e isso e declarado
    # tanto no numero de fontes de cada linha PASS quanto num aviso explicito abaixo, nao so em
    # comentario: uma saida que dissesse "identico nas 3 fontes" comparando so 2 seria uma prova
    # arquivada de uma comparacao que nunca ocorreu.
    #
    # Valor colateral: `orchestration/render.py --check` so verifica que a projecao EXISTE.
    # Esta comparacao de conteudo fecha parte dessa lacuna semantica para o campo `tools:`.
    canon_dir = ROOT / "execution" / "agents"
    repo_proj_dir = ROOT / ".claude" / "agents"
    home_dir = CLAUDE_HOME / "agents"

    canon_files = sorted(canon_dir.glob("*.md"))
    if not canon_files:
        sys.stderr.write(
            f"NAO VERIFICADO: nenhum agente canonico em {canon_dir} - "
            f"o contrato de extracao nao tem o que comparar.\n")
        return EXIT_NAO_VERIFICADO

    rotulos_desta_execucao = [ROTULO_PROJECAO] if repo_only else [ROTULO_PROJECAO, ROTULO_INSTALADA]
    n_fontes = 1 + len(rotulos_desta_execucao)  # canonica + as demais deste modo

    if repo_only:
        print(f"--repo-only: comparando {n_fontes} fontes ({ROTULO_CANONICA}, {ROTULO_PROJECAO}). "
              f"A perna instalada ({home_dir}) NAO e verificada nesta execucao - PASS abaixo "
              f"nao decide conformidade com o runtime realmente instalado.\n")

    violacoes: list[str] = []
    nao_verificados: list[str] = []
    ok = 0

    for canon_path in canon_files:
        nome = canon_path.stem
        t_canon = tools_declarados(canon_path)
        if t_canon is None or t_canon is TOOLS_AUSENTE:
            motivo = ("frontmatter ausente ou que nao fecha" if t_canon is None
                      else "`tools:` omitido na fonte canonica")
            violacoes.append(f"{nome}: fonte canonica {canon_path} sem `tools:` legivel "
                              f"({motivo}) - isto e defeito estrutural, nao ausencia de dado")
            continue

        fontes = {ROTULO_PROJECAO: repo_proj_dir / f"{nome}.md"}
        if not repo_only:
            fontes[ROTULO_INSTALADA] = home_dir / f"{nome}.md"

        divergiu = False
        for rotulo, caminho in fontes.items():
            if not caminho.is_file():
                nao_verificados.append(f"{nome}: {rotulo} ausente em {caminho}")
                divergiu = True
                continue
            t_outra = tools_declarados(caminho)
            if t_outra is None:
                nao_verificados.append(f"{nome}: {rotulo} existe mas o frontmatter nao fecha "
                                        f"em {caminho} - indecidivel")
                divergiu = True
                continue
            if t_outra is TOOLS_AUSENTE:
                violacoes.append(
                    f"{nome}: {rotulo} nao declara `tools:` em {caminho} - por omissao o "
                    f"subagente HERDA TODAS as ferramentas disponiveis (concessao MAXIMA, "
                    f"doc primaria do Claude Code), o OPOSTO de conformidade com o canonico "
                    f"({', '.join(sorted(t_canon))})")
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
            print(f"PASS {nome}: tools: identico nas {n_fontes} fontes comparadas "
                  f"({ROTULO_CANONICA}, {', '.join(rotulos_desta_execucao)}) "
                  f"({', '.join(sorted(t_canon))})")

    total = len(canon_files)
    modo = " [--repo-only: perna instalada NAO verificada]" if repo_only else ""
    print(f"\nagentes canonicos: {total} | conformes: {ok} | "
          f"divergentes: {len(violacoes)} | nao verificados: {len(nao_verificados)}{modo}")

    if violacoes:
        print("\nVIOLACOES (tools: declarado diverge entre fontes, ou concede mais do que o "
              "canonico declara):")
        for v in violacoes:
            print(f"  - {v}")
    if nao_verificados:
        print("\nNAO VERIFICADO (fonte ausente ou frontmatter ilegivel - nao decide conformidade):")
        for v in nao_verificados:
            print(f"  - {v}")

    print("\nISTO FECHA APENAS A METADE DECLARADA. ObservedCapabilities (o que o runtime "
          "realmente concede em execucao) NAO foi medido aqui - ver "
          "evidence/runtime-probes/capabilities.md.")
    if repo_only:
        print(f"--repo-only tambem NAO fechou a metade declarada inteira: {ROTULO_INSTALADA} "
              f"ficou fora desta execucao por desenho (ver acima).")

    if violacoes:
        return EXIT_VIOLACAO
    if nao_verificados:
        return EXIT_NAO_VERIFICADO
    return EXIT_OK


if __name__ == "__main__":
    sys.exit(main())
