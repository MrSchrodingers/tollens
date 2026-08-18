#!/usr/bin/env python3
from __future__ import annotations
import argparse, json, pathlib, re, tomllib
ROOT=pathlib.Path(__file__).resolve().parents[1]

def fail(msg): print(f'PROJECTION_ERROR {msg}'); return 1

# ONDA 12, achado da revisao. A primeira versao fazia `re.search(r'^description:[ ]*(.+)$')` no
# .md e comparava com o TOML PARSEADO. Dois modos de falha, ambos medidos pelo revisor:
#   - description entre aspas (obrigatorias em YAML assim que o texto contem `: `) devolvia a
#     string COM as aspas e reprovava projecao correta - falso vermelho;
#   - escalar de bloco (`>` ou `|`) devolvia o INDICADOR. Canonico e projecao Claude com o mesmo
#     indicador comparavam `'|' == '|'` e o portao PASSAVA POR VACUIDADE, no lado que ele existe
#     para vigiar, acusando o Codex que estava certo. Diagnostico invertido.
# As dez estao limpas hoje, entao era latente. Um portao que so funciona enquanto o dado for
# simples nao e portao: e sorte com sintaxe.
#
# Sem dependencia nova: `tomllib` e stdlib e ja estava importado; `pyyaml` nao e garantido aqui.
# Entao o frontmatter e desescapado por um subconjunto EXPLICITO (escalar plano, ou aspas simples
# ou duplas numa linha), e qualquer coisa fora dele RECUSA em vez de comparar lixo.
def _desc_md(p):
 t=p.read_text(encoding='utf-8')
 m=re.search(r'^description:[ ]*(.*)$',t,re.M)
 if not m: return None
 v=m.group(1).strip()
 if v[:1] in ('|','>',''): return None      # escalar de bloco ou vazio: fora do subconjunto
 if len(v)>=2 and v[0]==v[-1] and v[0] in '"\'':
  return v[1:-1].replace('\\"','"') if v[0]=='"' else v[1:-1].replace("''","'")
 if v[:1] in ('"',"'"): return None         # aspa aberta e nao fechada na linha: recusa
 return v

def _desc_toml(p):
 v=tomllib.loads(p.read_text(encoding='utf-8')).get('description'); return v.strip() if isinstance(v,str) else None

def main():
 p=argparse.ArgumentParser(); p.add_argument('--check',action='store_true'); p.parse_args()
 reg=json.loads((ROOT/'orchestration/registry.json').read_text())
 if reg.get('schema_version')!=1:return fail('schema_version')
 names=set(reg['agents'])
 for n,s in reg['agents'].items():
  if not (ROOT/s['source']).is_file(): return fail(f'fonte ausente: {n}')
  if not (ROOT/f'.claude/agents/{n}.md').is_file(): return fail(f'projecao Claude ausente: {n}')
  if not (ROOT/f'.codex/agents/{n}.toml').is_file(): return fail(f'projecao Codex ausente: {n}')
  # ONDA 12. EXISTIR NAO E ROTEAR. Ate 2026-08-17 este arquivo validava existencia e inventario,
  # nunca conteudo, e as dez projecoes traziam `description: "Projecao do agente canonico <nome>"`
  # enquanto o canonico trazia o GATILHO ("PORTAO FINAL antes de declarar pronto ou fazer merge
  # [...] Read-only, nunca corrige"). Pela doc primaria do Claude Code (sub-agents, conferida
  # 2026-08-17) `description` e o campo que o modelo usa para decidir delegar, e a precedencia poe
  # `.claude/agents/` de projeto ACIMA de `~/.claude/agents/` de usuario. Ou seja: dentro deste
  # repositorio a descricao util ficava sombreada pela inutil, nos dez agentes.
  # `evidence/runtime-probes/declared-capabilities.py` compara `tools:` e `memory:`, nunca
  # `description:` - a degradacao nao era trade-off declarado, era campo que ninguem olhava.
  _c=_desc_md(ROOT/s['source'])
  # A mensagem distingue AUSENTE de FORA DO SUBCONJUNTO: "sem description" para um arquivo que
  # TEM description em escalar de bloco manda o leitor procurar a coisa errada.
  if not _c: return fail(f'description do canonico ausente ou fora do subconjunto suportado (plano/aspas em uma linha): {n}')
  if _desc_md(ROOT/f'.claude/agents/{n}.md')!=_c: return fail(f'description da projecao Claude diverge do canonico: {n}')
  if _desc_toml(ROOT/f'.codex/agents/{n}.toml')!=_c: return fail(f'description da projecao Codex diverge do canonico: {n}')
 for f in ['.claude/settings.json','.codex/config.toml','.codex/hooks.json','CLAUDE.md','AGENTS.md']:
  if not (ROOT/f).is_file(): return fail(f'arquivo ausente: {f}')
 tomllib.loads((ROOT/'.codex/config.toml').read_text())
 if not json.loads((ROOT/'.codex/hooks.json').read_text()).get('hooks'): return fail('hooks Codex vazios')
 for pth in sorted((ROOT/'orchestration/workflows').glob('*.json')):
  w=json.loads(pth.read_text()); nodes=set(w['nodes'])
  if w['entry'] not in nodes or any(a not in nodes or b not in nodes for a,b in w['edges']): return fail(f'grafo invalido: {pth.name}')
 if names!={p.stem for p in (ROOT/'.claude/agents').glob('*.md')}:return fail('inventario Claude diverge')
 if names!={p.stem for p in (ROOT/'.codex/agents').glob('*.toml')}:return fail('inventario Codex diverge')
 print(f'projeções verificadas: {len(names)} agentes, {len(list((ROOT/"orchestration/workflows").glob("*.json")))} workflows')
 return 0
if __name__=='__main__': raise SystemExit(main())
