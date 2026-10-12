#!/bin/zsh
# Xcode must link simulated entitlements into Mach-O; signing an unsigned build
# afterward is insufficient for simulator App Groups and translation registration.
set -euo pipefail
project_root="${0:A:h:h}"
# Honor DEVELOPER_DIR or the active xcode-select toolchain.
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"

if (( $# > 1 )); then
  print -u2 -r -- "Usage: $0 [DERIVED_DATA_PATH]"
  exit 2
fi
if (( $# == 1 )) && [[ "$1" == "--help" || "$1" == "-h" ]]; then
  print -r -- "Usage: $0 [DERIVED_DATA_PATH]"
  print -r -- "Builds the simulator app and embedded extension with Xcode's simulated entitlements."
  print -r -- "Does not install an app, boot a device, or change developer-tool selection."
  exit 0
fi
derived_data="${1:-$project_root/build/SimulatorRuntime}"
derived_data="${derived_data:A}"
cd "$project_root"
xcodebuild -quiet -project AppleCopilot.xcodeproj -scheme AppleCopilot-iOS \
  -destination 'generic/platform=iOS Simulator' -derivedDataPath "$derived_data" \
  CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO build

app_bundle="$derived_data/Build/Products/Debug-iphonesimulator/Apple Copilot.app"
for executable in "$app_bundle/Apple Copilot" \
    "$app_bundle/Extensions/AppleCopilotTranslation.appex/AppleCopilotTranslation"; do
  if ! xcrun otool -l "$executable" | /usr/bin/grep 'sectname __entitlements' >/dev/null; then
    print -u2 -r -- "Missing linked simulator entitlements: $executable"
    exit 1
  fi
done
print -r -- "Simulator build ready: $app_bundle"
