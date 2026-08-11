# ADR 0027 — Evidência repassada ao delegado carrega a FONTE, não o veredito

**Status:** aceito
**Data:** 2026-08-11

## Contexto

O ADR 0011 registrou que 4 de 5 citações da configuração eram falsas ou mal atribuídas, sob
vigilância nominal da própria regra que as proibia. A conclusão de lá foi: *enunciar a regra não a
executa*.

Em 2026-08-11 a mesma classe reincidiu, e num lugar pior: dentro de `evidence/literature/`, a
camada criada especificamente para governar qualidade de evidência. Dois defeitos entraram no
repositório e passaram por 27 asserções verdes:

1. o título da referência arXiv:2602.06547 foi registrado como
   *"Malicious Agent Skills in the Wild: A Large-Scale Security Empirical Study"*. O título real é
   `"Do Not Mention This to the User": Detecting and Understanding Malicious Agent Skills in the
   Wild`. A string incorreta era o título de uma **página agregadora** que apareceu num resultado
   de busca, não o do artigo;
2. a string `"does not evaluate alternative agent frameworks"` foi registrada como quote verbatim
   de arXiv:2603.15401, com o selo *"verificado no texto completo"*. Ela tem **zero ocorrências**
   no artigo. Era **paráfrase de um sumarizador**, convertida em aspas.

O título errado propagou para `README.md` e `README.pt-BR.md`.

### A causa não foi o agente

O agente que escreveu os arquivos recebeu, no próprio prompt de delegação, um bloco rotulado
`EVIDENCIA JA VERIFICADA EM FONTE PRIMARIA (use como fato; NAO reverifique, NAO invente numero
novo)` — contendo as duas falsificações acima.

A instrução `NAO reverifique` era a única defesa restante, e o orquestrador a desligou. O agente
cumpriu o contrato que recebeu. Nenhum mecanismo do repositório podia detectar: o validador de
literatura confere **forma** (campo presente, vocabulário fechado, número com fonte declarada) e
declara explicitamente que não confere **conteúdo** contra a fonte primária.

A regra violada não é "não fabricar" — é anterior a ela. O orquestrador transformou um resumo de
ferramenta em fato, e depois exportou esse fato com autoridade que ele não tinha.

## Decisão

1. **Evidência repassada a um delegado carrega a FONTE, não o veredito.** O prompt entrega
   identificador e URL; a obrigação de ler é do delegado.
2. **É proibido instruir um delegado a não verificar.** Formulações do tipo `use como fato`,
   `não reverifique`, `já confirmado` estão vedadas em prompt de delegação. Quando a releitura for
   cara e o orquestrador quiser evitá-la, o caminho é declarar `[não verificado]`, nunca afirmar.
3. **Saída de sumarizador não é citação.** Texto produzido por resumo automático — incluindo o de
   ferramenta de fetch — é paráfrase até que a string seja lida no documento. Aspas exigem leitura
   direta da fonte.
4. **Título, autor, ano, número e quote só entram em artefato durável se lidos na fonte primária
   pelo ator que os escreve**, nesta sessão. Onde isso não for possível: `[não verificado]`.
5. **Metadados bibliográficos exigem a fonte canônica.** Página agregadora, resultado de busca e
   índice de terceiro não estabelecem título nem autoria.
6. O delegado que receber um fato sem fonte **para e reporta**, em vez de adivinhar — extensão
   direta do contrato de delegação já vigente para item exigido ausente.

## Consequências

### Positivas

- o custo de verificação passa a recair sobre quem escreve a afirmação, que é quem pode fazê-la;
- o orquestrador deixa de ser um canal por onde erro entra com autoridade emprestada;
- prompt de delegação vira artefato auditável: dá para ler um prompt e ver se ele proibiu
  verificação.

### Limites explícitos

Esta decisão **não** cria mecanismo. Não há hoje verificador que leia um prompt de delegação e
recuse `NAO reverifique`, nem que confronte `evidence/literature/*.yaml` com o texto real dos
artigos. Pela regra que este repositório adota — garantia exige política, mecanismo, verificador
observável e evidência fresca — o estado correto desta decisão é:

```text
ADVISORY, não GUARANTEE
```

Registrar isso é parte da decisão. O ADR 0011 falhou justamente por ter sido tratado como se
enunciar bastasse; repetir a forma sem repetir o erro exige dizer, aqui, que ainda não basta.

O mecanismo que fecharia: um validador que exija, para cada `evidence/literature/*.yaml`, um
digest do documento-fonte obtido em recuperação independente, e que reprove quando `citation` não
casar com os metadados canônicos daquele identificador. Não está implementado.

### Alcance

A decisão vale para todo prompt de delegação emitido neste repositório, e para a configuração
global que o governa. A mesma omissão detectada aqui existia em `~/.claude/CLAUDE.md` §9 e em
`docs/method/CONHECIMENTO.md`, onde os números de arXiv:2603.15401 estavam corretos mas
apresentados sem baseline (89,8%), sem o teto aritmético (+10,2pp), sem o efeito-teto (24 das 49
skills marcam 100% nos dois braços), sem o modelo e scaffold únicos, e sem o status de preprint
preliminar — o que os tornava enganosos por omissão.
