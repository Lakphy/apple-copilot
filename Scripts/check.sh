#!/bin/zsh
# Native checks require macOS with full Xcode selected.
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

swift format lint --strict --recursive Package.swift Sources Tests
python3 Scripts/check_docs.py
for plist in Configuration/*.plist Configuration/*.entitlements; do
  plutil -lint "$plist"
done
for script in Scripts/*.sh; do
  zsh -n "$script"
done
python3 -m py_compile Scripts/*.py
./Scripts/test.sh
xcodebuild -quiet -project AppleCopilot.xcodeproj -scheme AppleCopilot-macOS \
  -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/macOS CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project AppleCopilot.xcodeproj -scheme AppleCopilot-iOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
