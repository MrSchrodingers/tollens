# tollens — Claude Code

Use `standard-change` para mudanças comuns e `high-risk-change` para autorização, parser, dependência, instalação ou CI. Leitura pode ser paralela; escrita é serializada. `tdd` precede `implementador`; revisão e refutação são independentes. O estado local máximo é `CANDIDATE`; somente `verify-pr` no SHA autoriza merge. Lacuna é `NOT_VERIFIED`.
