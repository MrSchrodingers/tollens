# Observacao - discrepancia entre `tools:` declarado e ferramentas usadas em execucao real

- Data: 2026-08-10
- Ambiente: Linux, `claude-code 2.1.226`
- Fecha: gera o achado retrospectivo da secao 2 de `evidence/runtime-probes/capabilities.md`,
  e o `evidence.observation` de `evidence/claims/C-019.yaml`

---

## 1. O relato que motivou esta observacao

A sessao que delegou esta tarefa reportou, como fato ja medido: a listagem de agentes exposta
ao runtime numa sessao anterior mostrou `refutador ... (Tools: Read, Grep, Glob, Bash, Write,
Edit)`, enquanto `execution/agents/refutador.md` declara `tools: Read, Grep, Glob, Bash` - sem
Write nem Edit. Aquela sessao registrou nao ter conseguido determinar qual fonte e autoritativa.
Esta observacao NAO reproduz aquela listagem (nao foi capturada aqui); em vez disso, cruza o
relato com instrumentacao ja existente e independente, gravada por execucoes passadas na mesma
maquina.

## 2. Instrumentacao consultada (leitura, nao criacao de subagente)

`evidence/hooks/subagent-probe.sh` e um hook `SubagentStart`/`SubagentStop` permanente deste
repositorio (ver ADR referenciada no proprio arquivo) que grava, em `~/.claude/logs/
subagent-probe.jsonl`, o payload bruto que o runtime entrega a cada evento de subagente. Este
arquivo roda com rotacao em 2 MB (mantendo uma geracao anterior como `.jsonl.1`); durante esta
sessao ele rotacionou entre duas leituras (crescimento de 1266 para 1276 linhas, consistente
com outras sessoes rodando na mesma maquina em paralelo) - a leitura abaixo usa a geracao
`.jsonl.1`, que preservou o historico anterior a rotacao.

```
$ python3 -c "
import json
d=[json.loads(l) for l in open('/home/ti/.claude/logs/subagent-probe.jsonl.1') if l.strip()]
print('total_lines=', len(d))
refs=[x for x in d if x.get('agent_type')=='refutador']
print('refutador_entries=', len(refs))
print('schema_keys=', sorted(refs[0].keys()))
"
total_lines= 1276
refutador_entries= 10
schema_keys= ['agent_id', 'agent_transcript_path', 'agent_type', 'background_tasks', 'cwd',
  'effort', 'hook_event_name', 'last_assistant_message', 'permission_mode', 'prompt_id',
  'session_crons', 'session_id', 'stop_hook_active', 'transcript_path']
```

**O payload NAO tem campo de ferramentas concedidas.** Este canal, sozinho, nao pode responder
a pergunta de `ObservedCapabilities` - so aponta para `agent_transcript_path`, o transcrito
completo daquela execucao de subagente.

## 3. O transcrito de uma execucao real do `refutador`

```
$ python3 -c "
import json
p='/home/ti/.claude/projects/-home-ti/68deb4fd-b18d-462d-b75a-709b724f2dbd/subagents/agent-a6f3a75bb6b5ef7a7.jsonl'
recs=[json.loads(l) for l in open(p)]
print('total_records=', len(recs))
tu={}
for d in recs:
    c=(d.get('message') or {}).get('content')
    if isinstance(c, list):
        for b in c:
            if isinstance(b, dict) and b.get('type')=='tool_use':
                tu[b.get('id')]={'name':b.get('name'),'input':b.get('input')}
from collections import Counter
print('tool_use por nome=', Counter(v['name'] for v in tu.values()))
"
total_records= 139
tool_use por nome= Counter({'Bash': 39, 'Read': 3, 'Write': 2, 'Edit': 1})
```

Um agente cujo `execution/agents/refutador.md` declara `tools: Read, Grep, Glob, Bash` emitiu,
nesta execucao real, `tool_use` com `name` em `Write` (2x) e `Edit` (1x) - ferramentas ausentes
da lista declarada. Os tres `tool_result` correspondentes:

```
--- Write file_path=/home/ti/.claude/agent-memory/refutador/mutante-no-local-do-defeito.md is_error=None
--- Write file_path=/home/ti/.claude/agent-memory/refutador/raio-de-deploy-compose-dry-run.md is_error=None
--- Edit  file_path=/home/ti/.claude/agent-memory/refutador/MEMORY.md is_error=None
```

`is_error` nulo em todos os tres: as tres chamadas TIVERAM SUCESSO. O campo `permission_mode`
daquela entrada e `bypassPermissions` (o prompt de confirmacao interativa estava desligado
naquela sessao) - isto explica a AUSENCIA de um gate de confirmacao humana, mas nao explica a
DISPONIBILIDADE do nome de ferramenta `Write`/`Edit` para o modelo: se `tools:` fosse a unica
fonte da lista exposta ao modelo, `Write` nao deveria ser um `tool_use` emissivel em primeiro
lugar, independente de `permission_mode`.

## 4. Causa provavel, ja documentada neste repositorio antes desta sessao

`docs/adr/0007-topologia-de-execucao-e-contrato-de-delegacao.md:25-31`, decisao 2:

> `memory: user` e feature real e ativa, nao no-op. O campo `memory:` aceita o enum
> `user`/`project`/`local`, habilitando memoria persistente do subagente em
> `~/.claude/agent-memory/<nome>/` (Read/Write/Edit auto-habilitados; o `MEMORY.md` do agente
> pre-carregado no system prompt).

`execution/agents/refutador.md` declara `memory: user`. Os outros sete agentes read-only
tambem declaram `memory: user`; `tdd` e `implementador` (os dois agentes com Write/Edit
DECLARADO) NAO tem o campo - consistente com a nota da ADR de que soo os agentes com `memory:
user` tem pasta em `~/.claude/agent-memory/`. As tres escritas observadas na secao 3 miram
`~/.claude/agent-memory/refutador/` - dentro do escopo que a ADR descreve.

## 5. O que fica NAO VERIFICADO

A ADR usa a palavra "auto-habilitados" mas nao registra, e este cruzamento tambem nao prova,
se o grant de Write/Edit do subsistema de memoria e CONFINADO por imposicao do runtime a
`~/.claude/agent-memory/<nome>/`, ou se e um grant geral de Write/Edit que, nesta amostra
(n=1 transcrito, 3 chamadas), so foi exercitado dentro do escopo esperado porque o agente,
por disciplina de prompt e nao por imposicao do ambiente, nunca pediu escrever em outro lugar.
As duas hipoteses sao EXTERNAMENTE indistinguiveis a partir deste transcrito: as tres chamadas
observadas sao consistentes com as duas.

Isto e exatamente o que motiva os vetores A1 (Write fora do diretorio de memoria) e A1m (Write
dentro dele, como controle) em `evidence/runtime-probes/capabilities.md` secao 4.2 - a
diferenca entre as duas hipoteses so aparece testando um `file_path` DELIBERADAMENTE fora do
diretorio de memoria, o que esta observacao nao fez.

## Limites declarados

- Cobre uma unica execucao passada de `refutador`, nao amostrada de proposito (foi a entrada
  mais recente do log no momento da leitura) e sem controle pareado.
- O log e mutavel e compartilhado por qualquer sessao rodando na mesma maquina - rotacionou
  durante esta propria investigacao. Os numeros acima sao um instantaneo, nao uma constante do
  sistema.
- Nada aqui mede os outros sete agentes read-only, nem os vetores de escrita via Bash (`>`,
  `tee`, `sed -i`, etc.) citados como evidencia de investigacao anterior - aqueles ja tem
  explicacao estrutural independente (matcher de hook por nome de ferramenta, nao por efeito;
  ver `evidence/runtime-probes/capabilities.md` secao 3) e nao dependem do subsistema de
  memoria.
- Nao houve tentativa, nesta observacao, de escrever atraves de nenhum agente - toda a leitura
  foi sobre artefatos de execucoes JA GRAVADAS antes desta sessao comecar.
