#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1

python3 orchestration/render.py --check
python3 orchestration/schedule.py --check
python3 tests/unit/governance-links.py
python3 tests/unit/methodology.py
python3 tests/mutation/methodology.py
bash tests/unit/repository-hygiene.sh
bash tests/unit/managed-root-trust.sh
