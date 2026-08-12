#!/usr/bin/env bash
# Regenera install/requirements-ci.txt com hashes do fecho transitivo.
#
# Roda DENTRO de ubuntu:24.04, nao na maquina local, e a razao e medida: a familia da imagem do
# runner traz Python 3.12, e esta estacao roda 3.14. Resolver na versao errada produz um fecho
# que o runner pode recusar - e o erro so aparece na CI, com 26 minutos de latencia.
#
# Este script nao escreve no repositorio sozinho. Ele gera em um diretorio temporario e imprime
# o diff, para que a promocao seja um ato deliberado - dependencia trocada em silencio e
# exatamente o que o hash existe para impedir.
set -euo pipefail
cd "$(dirname "$0")/.."
IN=install/requirements-ci.in
[ -f "$IN" ] || { echo "ausente: $IN"; exit 1; }
command -v docker >/dev/null || { echo "docker ausente - nao ha como resolver na familia certa"; exit 1; }

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cp "$IN" "$TMP/requirements-ci.in"

docker run --rm -v "$TMP:/out" ubuntu:24.04 bash -c '
set -euo pipefail
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq && apt-get install -y -qq python3 python3-venv >/dev/null 2>&1
echo "python do container: $(python3 -V)"
python3 -m venv /v
/v/bin/pip install --quiet --upgrade pip >/dev/null
/v/bin/pip install --quiet pip-tools >/dev/null
/v/bin/pip-compile --quiet --generate-hashes --allow-unsafe --strip-extras \
    --output-file /out/requirements-ci.txt /out/requirements-ci.in
# PORTAO: o arquivo so vale se instalar de fato sob --require-hashes, em venv limpo.
python3 -m venv /t
/t/bin/pip install --quiet --require-hashes -r /out/requirements-ci.txt
/t/bin/python -c "import pandas,openpyxl,fitz,yaml,coverage,packaging"
echo "instalacao com --require-hashes em venv limpo: OK"
'

echo
echo "=== diff contra o versionado (o cabecalho explicativo nao entra na comparacao) ==="
diff <(tail -n +7 "$TMP/requirements-ci.txt") <(grep -vE '^#' install/requirements-ci.txt | sed '/^$/d') \
  && echo "  sem mudanca" \
  || echo "  HA MUDANCA acima. Promova manualmente, preservando o cabecalho de install/requirements-ci.txt."
