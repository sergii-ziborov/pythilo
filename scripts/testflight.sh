#!/bin/bash
# Archives, exports and uploads Pythilo for TestFlight, by hand from this Mac.
#
#   scripts/testflight.sh prepare    # regenerate the project, Release archive, App Store .ipa
#   scripts/testflight.sh upload     # send the archive to App Store Connect, which validates it
#
# Uploads go through Xcode because altool reads the version from whichever package framework
# it finds first, then refuses the build.
#
# The version is MARKETING_VERSION in project.yml. PYTHILO_BUILD_NUMBER overrides the build
# number. Credentials are read at run time and never printed or committed: ASC_KEY_ID and
# ASC_ISSUER_ID from ~/.private_keys/appstoreconnect.env (or $ASC_ENV_FILE), the key from
# ~/.private_keys/AuthKey_<id>.p8. PYTHILO_ASC_KEY_ID picks a different key from that folder.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:-prepare}"
case "$mode" in prepare|upload) ;; *) echo 'Usage: scripts/testflight.sh [prepare|upload]' >&2; exit 2 ;; esac

# The App Store build needs an Xcode that knows the Duo, or it runs letterboxed there.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
release_dir="build/testflight"
archive="$release_dir/Pythilo.xcarchive"
mkdir -p "$release_dir"

set -a
# shellcheck disable=SC1090
source "${ASC_ENV_FILE:-$HOME/.private_keys/appstoreconnect.env}"
set +a
key_id="${PYTHILO_ASC_KEY_ID:-${ASC_KEY_ID:?Set ASC_KEY_ID}}"
: "${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
key_path="$HOME/.private_keys/AuthKey_$key_id.p8"
[ -f "$key_path" ] || { echo "Missing $key_path" >&2; exit 1; }
auth=(-allowProvisioningUpdates -authenticationKeyPath "$key_path"
      -authenticationKeyID "$key_id" -authenticationKeyIssuerID "$ASC_ISSUER_ID")

if [ "$mode" = prepare ]; then
    scripts/generate-project.sh
    settings=()
    if [ -n "${PYTHILO_BUILD_NUMBER:-}" ]; then
        case "$PYTHILO_BUILD_NUMBER" in *[!0-9]*) echo 'Build number must contain only digits' >&2; exit 2 ;; esac
        settings+=("CURRENT_PROJECT_VERSION=$PYTHILO_BUILD_NUMBER")
    fi
    xcodebuild -jobs 4 -project Pythilo.xcodeproj -scheme Pythilo -configuration Release \
        -destination 'generic/platform=iOS' -archivePath "$archive" \
        -derivedDataPath build/DerivedData "${auth[@]}" ${settings[@]+"${settings[@]}"} archive
    rm -rf "$release_dir/Export"
    xcodebuild -exportArchive -archivePath "$archive" \
        -exportPath "$release_dir/Export" -exportOptionsPlist scripts/ExportOptions.plist "${auth[@]}"
    echo "Exported $release_dir/Export/Pythilo.ipa"
else
    [ -d "$archive" ] || { echo "Missing $archive; run scripts/testflight.sh prepare first." >&2; exit 1; }
    options="$release_dir/ExportOptions-upload.plist"
    cp scripts/ExportOptions.plist "$options"
    plutil -replace destination -string upload "$options"
    xcodebuild -exportArchive -archivePath "$archive" \
        -exportPath "$release_dir/Upload" -exportOptionsPlist "$options" "${auth[@]}"
fi
