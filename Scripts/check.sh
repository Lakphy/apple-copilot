#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
swift test --filter CopilotCoreTests
xcodebuild -quiet -project AppleCopilot.xcodeproj -scheme AppleCopilot-macOS \
  -destination 'platform=macOS,arch=arm64' -derivedDataPath build/macOS CODE_SIGNING_ALLOWED=NO build
xcodebuild -quiet -project AppleCopilot.xcodeproj -scheme AppleCopilot-iOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath build/iOS CODE_SIGNING_ALLOWED=NO build
