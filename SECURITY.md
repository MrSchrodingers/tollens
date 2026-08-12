# Política de segurança

## Escopo

O `tollens` executa hooks, verificadores, adaptadores e instaladores. Falhas que permitam contornar autorização, escapar de diretórios gerenciados, executar conteúdo não confiável com autoridade excessiva, adulterar evidência ou deixar um deploy privilegiado em estado inconsistente são consideradas vulnerabilidades de segurança.

O projeto é experimental. Ele não fornece, por si só, sandbox, isolamento de sistema operacional, atestação externa independente ou proteção contra um administrador que possa alterar a política do repositório.

## Como reportar

Não publique segredos, tokens, chaves, payloads ativos ou dados pessoais em issues públicas. Use o canal privado de Security Advisories do GitHub deste repositório. Inclua versão/commit, precondições, reprodução mínima, impacto, expectativa violada e mitigação com limitações.

## Classes prioritárias

- bypass de `verify-pr`, ruleset, claim ledger ou autorização;
- path traversal, symlink race ou escrita fora do prefixo;
- rollback parcial ou perda de recuperação;
- parser ou adaptador processando arquivo hostil;
- execução de hook não versionado ou não pinado;
- injeção em JSON, shell, workflow ou manifesto;
- permissões, proprietário, grupo ou tipo de inode divergentes.

Uma correção candidata inclui contraexemplo, regressão, controle negativo ou mutante, escopo e execução remota no SHA. Ausência de ferramenta é `NOT_VERIFIED`, não sucesso.
