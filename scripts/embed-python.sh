#!/bin/bash
# Xcode build phase. Copies the standard library, Pythilo's runtime and the
# bundled packages into the app, then turns every extension module into a
# signed framework, which is the only form iOS will load.
set -euo pipefail
source "$PROJECT_DIR/Vendor/Python.xcframework/build/utils.sh"

case "$EFFECTIVE_PLATFORM_NAME" in
  -iphonesimulator) platform=iphonesimulator ;;
  -iphoneos) platform=iphoneos ;;
  *) echo "Unsupported platform $EFFECTIVE_PLATFORM_NAME"; exit 1 ;;
esac

mkdir -p "$CODESIGNING_FOLDER_PATH/app" "$CODESIGNING_FOLDER_PATH/app_packages"
rsync -au --delete --exclude '__pycache__' "$PROJECT_DIR/Pythilo/PythonRuntime/" "$CODESIGNING_FOLDER_PATH/app/"

packages="$PROJECT_DIR/build/app_packages/$platform"
if [ -d "$packages" ]; then
  rsync -au --delete --exclude '__pycache__' --exclude '*.fwork' "$packages/" "$CODESIGNING_FOLDER_PATH/app_packages/"
  # NumPy's static libraries are for building against it. App Store Connect refuses them.
  find "$CODESIGNING_FOLDER_PATH/app_packages" -name '*.a' -delete
else
  echo "warning: no bundled packages at $packages; run scripts/vendor-packages.py"
fi

install_python Vendor/Python.xcframework app_packages

# Keep signed native backends; their Python APIs and teaching material are on demand.
python3 "$PROJECT_DIR/scripts/strip-downloadable-content.py" "$CODESIGNING_FOLDER_PATH"
