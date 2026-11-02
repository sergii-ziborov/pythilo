#!/bin/bash
# Builds and installs on a connected device: scripts/install-device.sh <device-udid>
set -euo pipefail
cd "$(dirname "$0")/.."
device="${1:?Pass the device identifier from: xcrun devicectl list devices}"
xcodebuild -project Pythilo.xcodeproj -scheme Pythilo -configuration Release \
  -destination "id=$device" -derivedDataPath build/DerivedData -allowProvisioningUpdates build
xcrun devicectl device install app --device "$device" build/DerivedData/Build/Products/Release-iphoneos/Pythilo.app
