#!/usr/bin/env bash
# UserPromptSubmit - lembrete de ALTA SALIENCIA e BAIXO CUSTO.
#
# Substitui colegio-operating-mode.sh (3660 B = ~915 tok POR PROMPT; ~36k tokens numa sessao
# de 40 turnos, injetados por repeticao literal). Este carrega ~600 B (~150 tok): -84%.
#
# Criterio do que fica: so o que precisa de saliencia NO MOMENTO DA DECISAO (efeito de
# recencia). Fato invariante ja esta no CLAUDE.md, carregado uma vez no inicio (efeito de
# primazia); repeti-lo aqui e imposto puro. A tabela de lentes, a topologia e o contrato de
# delegacao vivem la, nao aqui.
#
# O que NAO fica, e por que: a instrucao de "responder como colegiado com vozes rotuladas"
# foi removida (ADR 0011). Voz rotulada dentro da mesma resposta e auto-correcao intrinseca -
# mesmos pesos e mesmo contexto produzem erro em MODO COMUM, com dependencia substancial de
# magnitude NAO MEDIDA aqui - e degrada em vez de verificar (Huang et al., ICLR 2024).
# Ate 2026-08-12 esta linha dizia "correlacao 1": numero forte, falso, e desnecessario, porque
# a evidencia de Huang et al. sustenta a conclusao sem coeficiente nenhum. Ver a errata em
# docs/adr/0011. Contraditorio real exige contexto separado: agente `refutador`.
#
# Fail-open por construcao: so escreve em stdout e sai 0. Nunca bloqueia o prompt.

cat <<'EOF'
[LEMBRETE] Regras que decidem AGORA:
1. "pronto/corrigido/funciona" so com EXECUCAO colada: teste que falhava e agora passa +
   suite rodada + exit code visivel. Sem isso, o estado e "nao verificado" - diga isso.
2. Numero, autor, ano, URL, big-O: conferir na FONTE PRIMARIA antes de afirmar. Sem fonte,
   marque [nao verificado]. Enunciar a regra nao a executa.
3. Tarefa nao trivial -> DELEGAR por gatilho. Diff que toca dado/autorizacao/entrada
   nao-confiavel sempre passa por revisor-codigo; portao final e o refutador (contexto
   separado, le o diff cru). Trivial e conversa: executar direto, sem pipeline.
4. Afirmacao do usuario = hipotese a avaliar. Requisito dele se acata; fato tecnico nao se
   silencia. Nao elogiar o operador, nao fabricar objecao.
EOF
exit 0
