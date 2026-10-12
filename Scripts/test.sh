#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
exec python3 Scripts/run_tests.py "$@"
