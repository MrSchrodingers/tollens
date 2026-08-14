---
name: defesa-de-tese
description: Valida um plano, PRD, ideia, feature ou fix como uma tese academica - tres portoes logicos + varredura de erro obvio + veredito calibrado, conduzido pelo Orquestrador-Conciliador sobre o colegiado. Acionar com /defesa-de-tese antes de aprovar/mergear algo nao trivial, ou quando o usuario pedir validar/revisar plano/PRD/feature/fix ou "validar como tese".
---

# /defesa-de-tese

IMPORTA: CLAUDE.md Diretriz 13.1 (fonte normativa) e docs/adr/0005 (base de evidencia)

## O que entrega
Um VEREDITO CALIBRADO sobre a tese (plano/PRD/ideia/feature/fix), conduzido pelo
`[Orquestrador]` (presidente da banca) sobre o colegiado de especialistas.
Verificacao: a tese so recebe "aprovar" quando a varredura de erro obvio PASSA inteira E a
evidencia esta colada. Aprovar limpo e legitimo quando nao ha furo real - NAO reprovar para
parecer rigoroso (discordancia gratuita = defeito simetrico a bajulacao, Diretriz 3).

## Gatilho
SE o usuario pedir validar/revisar um plano, PRD, ideia, feature ou fix -> FAZER os Passos.
SE estiver prestes a declarar algo NAO trivial "pronto" ou mergear -> FAZER os Passos.
SE for conversa trivial ou pergunta factual curta -> NAO acionar.

## Passos

1. EXIGIR a estrutura da tese. SE faltar pergunta, hipotese, metodo, evidencia OU a
   declaracao popperiana (qual observacao a refutaria) -> parar e pedir o que falta.
   Porque: tese sem estrutura nao e avaliavel; aceita-la e o primeiro erro que passa.

2. PORTAO G1 (premissas). Listar as premissas. SE um termo load-bearing nao tem definicao
   operacional (metrica + ponto de medida + limiar) -> FALHA: pedir operacionalizacao.
   SEPARAR premissa factual (verificar) de premissa de requisito (do usuario, acatar).
   SE ha pressuposicao oculta de existencia/unicidade -> marcar como alerta.
   Porque: premissa implicita e onde o erro se esconde (Russell, descricoes).

3. PORTAO G2 (inferencia valida). SE a conclusao afirma o consequente (trata evidencia
   meramente consistente como prova) -> FALHA: marcar invalido. Abducao GERA hipotese,
   deducao FECHA. Porque: e a falacia nº 1 do diagnostico de bug.

4. PORTAO G3 (solidez). Para cada premissa factual NAO medida -> marcar HIPOTESE A VERIFICAR
   e delegar ao `investigador`/`analista-otimalidade`. SE premissa factual load-bearing nao
   foi medida -> veredito = "pendente de evidencia", nunca "aprovado".
   Porque: valido != solido; o plano bem-argumentado com premissa nao medida e o erro tipico.

5. ARGUICAO (colegiado, gating). SE a tese e NAO trivial -> DELEGAR a arguicao adversarial a um
   arguidor INDEPENDENTE (`cetico`/`revisor-critico`, que nao autorou a tese), nao argui-la na
   sessao que a propos (anti-conluio: o autor nao preside sozinho a propria banca). Convocar so
   as lentes pertinentes. Cada uma levanta a objecao REAL da sua disciplina com grounds+warrant;
   a tese REPLICA com evidencia; steelman antes de refutar. SE uma lente nao tem objecao
   substantiva -> cede a vez (sem fabricar).

6. VARREDURA DE ERRO OBVIO (DO-CONFIRM), lida sobre os ARTEFATOS REAIS que a tese referencia
   (codigo/schema/metricas/logs), nao a prosa do autor. Rodar C1-C10 da Diretriz 13.1
   (requisito / caminho-id / sucesso-testado / referencia / limite / regressao / numero-citacao
   / deadcode / sinal-tolerado / contrafactual). SE qualquer item = FALHA -> BLOQUEAR o veredito
   (stop-the-line), nunca nota de rodape. Item que NAO se aplica (ex.: C3/C6 sobre plano nao
   implementado) -> N/A COM justificativa de uma linha, nunca silencioso.

7. VEREDITO CALIBRADO (Orquestrador, meta-review). Classificar e justificar com evidencia:
   aprovar / correcao editorial / correcao menor (revalida sem repipeline) / revisar-e-ressubmeter
   (volta ao pipeline INTEIRO) / rebaixar escopo / reprovar. NAO escalar o desfecho para parecer
   rigoroso.

## Verificacao
- Nenhuma objecao material ficou sem replica com evidencia.
- A varredura de erro obvio PASSA inteira, OU o veredito nao e "aprovar".
- Toda afirmacao de sucesso tem saida de comando executado colada (exit 0).
