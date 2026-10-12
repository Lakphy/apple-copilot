#!/bin/zsh
# Install pinned development dependencies separately with npm ci --ignore-scripts.
set -euo pipefail
cd "${0:A:h}/MarkdownRenderer"
npm run build
npm test
# Every generated resource must match the committed build on CI.
if [[ "${CI:-}" == "true" ]]; then
  git diff --exit-code -- ../../Sources/CopilotUI/Resources/Markdown
fi
