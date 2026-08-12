# Prompt de abertura - proxima sessao

Cole o bloco abaixo como primeira mensagem de uma sessao limpa, com `cwd` em `~/tollens`.

---

```
Sessao seguinte do tollens. Estado: M3 PARCIAL.

LEIA PRIMEIRO, NESTA ORDEM, E NAO COMECE ANTES:
  docs/HANDOFF.md            - contrato de teste, rigor exigido, 12 armadilhas ja pagas
  docs/status.generated.md   - estado por execucao real (nunca digite contagem a mao)
  docs/adr/0023-*.md         - os oito defeitos da sessao anterior e como cada um apareceu
  docs/adr/0022-*.md         - a decisao central e os 6 adendos

ESTADO DE PARTIDA (confirme antes de tocar em qualquer coisa):
  bash scripts/status.sh --check           # exit 0
  bash install/verify.sh                   # exit 0, sem orfaos
  python3 evidence/validate-claims.py      # exit 0
  gh run list --limit 1                    # success
Se algum falhar, o primeiro trabalho e entender por que - nao contorne.

MUDANCA DE FLUXO: `main` esta sob ruleset com bypass_actors vazio. Push direto e RECUSADO
(medido, GH013). Trabalhe em branch e abra PR; o check `verify` precisa passar sobre o SHA.

ESCOPO, em ordem.

P2  RAIZ DE CONFIANCA - primeiro item, e o unico que fecha M3 no plano local.
    `install/apply-managed.sh` esta pronto e tem 23 assercoes contra prefixo de ensaio. Falta
    ATIVAR, o que exige sudo meu. Me peca os comandos; a sequencia esta no HANDOFF secao 5.
    MEDIR entre cada passo, com --include-hook-events. Se a contagem nao dobrar apos o deploy,
    PARE e reverta - significa que os hooks managed nao carregaram, e ativar a flag nesse
    estado derruba todo o mecanismo de hooks da maquina.

P3  SANDBOX dos parsers de documento. E a lacuna aberta mais relevante: pandoc, libreoffice e
    pdftotext processam entrada nao confiavel com a minha autoridade. D5 e contencao de
    RECURSO, nao isolamento. Enquanto nao houver sandbox, NAO expanda para OCR nem novos
    formatos - a superficie ja cresceu sem isolamento uma vez.

P3b Hermeticidade: container por digest + SBOM. `ubuntu-24.04` fixa familia, nao digest.

FORA DE ESCOPO, e nao finja o contrario: corpus de eficacia (P4, semanas), auditoria
autoralmente independente (P5, exige terceiro), metodos formais (sem gatilho), grafos.

RIGOR - o que reprova esta sessao:
  1. Reproduza antes de corrigir. Sem repro com saida colada, ha suposicao, nao defeito.
  2. Corrija a CLASSE, nao a instancia.
  3. Todo teste novo passa por mutacao, com kill ATRIBUIVEL ao caso-alvo. Caso com duas
     ancoras nao serve de alvo: nao isola qual alternativa o sustenta.
  4. Todo caso POSITIVO exige o NEGATIVO correspondente. Positivo sozinho mede presenca, nao
     poder de decisao do oraculo. Foi assim que a ancora de evidencia ficou sem discriminador
     por versoes inteiras.
  5. EXPECTED fixo. Na sessao anterior a invariante de contagem pegou TRES testes errados
     antes de eles serem publicados.
  6. Dependencia de ORACULO ausente = exit 2 / NOT_VERIFIED. Variacao de AMBIENTE = SKIP com
     assercao-guarda.
  7. Fonte primaria para todo fato externo. Ela ja corrigiu o plano de P2 uma vez.
  8. Uma suite por vez: o lock sai 3 em corrida, e isso e o lock, nao defeito.
  9. Garantia nova exige claim em evidence/claims/, com limitations preenchido. O validador
     reprova referencia a evidencia inexistente.

O QUE FUNCIONOU E VALE REPETIR: os oito defeitos da sessao anterior apareceram por MUDAR O QUE
EXECUTA - rodar o binario de verdade, sob outro locale, duas vezes ao mesmo tempo, com um
plugin a mais, com variantes de formatacao, com a garantia removida. Leitura atenta encontrou
zero deles. Prefira montar uma execucao diferente a reler o mesmo codigo.

CRITERIO DE PRONTO - nao encerre sem colar:
  [ ] status.sh --check, install/verify.sh, validate-claims.py -> 0
  [ ] as 9 suites unitarias e os 3 runners de mutacao -> 0
  [ ] CI verde, com SHA e URL, e o PR mergeado pelo ruleset
  [ ] docs/status.generated.md regenerado e committado
  [ ] ADR com o que foi feito E o que nao foi
  [ ] cada item marcado: fechado / nao fechado / bloqueado por acao minha

PORTAO FINAL, obrigatorio: delegue ao agente `refutador` com o `git diff` cru da sessao.
Relate o RACIOCINIO dele, nao so o veredito.

Comece confirmando o estado de partida e me diga o que encontrou antes de mudar qualquer coisa.
```

---

## Por que o prompt tem esta forma

- **Ordem de leitura explicita**: o HANDOFF traz o contrato de teste que impede as sete formas
  de verde vacuo ja pagas.
- **P2 primeiro e com PARE explicito**: e o unico passo desta lista capaz de derrubar o
  mecanismo inteiro se executado fora de ordem, e o criterio de aborto precisa estar no prompt,
  nao so no script.
- **A regra 4 e nova** e vem do defeito mais consequente da sessao anterior: um oraculo com
  apenas casos positivos nao tem poder de decisao medido.
- **"Mude o que executa"** substitui "revise com atencao": e a unica das duas que produziu
  achados, com oito instancias.
