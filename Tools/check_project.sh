#!/bin/bash
# Run from any directory; set PET_TEST_DESTINATION to choose a simulator.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
PET_PYTHON="${PET_PYTHON:-python3}"
PET_REPORT_DIR="${PET_REPORT_DIR:-outputs/qa/check-$(date +%Y%m%d-%H%M%S)}"
PET_DERIVED_DATA="${PET_DERIVED_DATA:-outputs/DerivedData}"
PET_RELEASE_DERIVED_DATA="${PET_RELEASE_DERIVED_DATA:-outputs/ReleaseValidation}"
mkdir -p "$PET_REPORT_DIR"
"$PET_PYTHON" Tools/validate_timer_fonts.py | tee "$PET_REPORT_DIR/fonts.log"
"$PET_PYTHON" Tools/validate_accessories.py | tee "$PET_REPORT_DIR/accessories.log"
"$PET_PYTHON" Tools/validate_natural_gaits.py | tee "$PET_REPORT_DIR/gaits.log"
"$PET_PYTHON" Tools/validate_companion_assets.py | tee "$PET_REPORT_DIR/new-pets.log"
"$PET_PYTHON" Tools/validate_release_readiness.py | tee "$PET_REPORT_DIR/release-metadata.log"
if [[ -z "${PET_TEST_DESTINATION:-}" ]]; then
  PET_SIM_ID=$(xcrun simctl list devices available --json | "$PET_PYTHON" -c '
import json,sys
data=json.load(sys.stdin)
phones=[d for runtime,devices in data["devices"].items() if "iOS" in runtime for d in devices if "iPhone" in d["name"]]
if not phones: sys.exit("Install an iOS simulator runtime in Xcode first.")
print(next((d for d in phones if d["state"] == "Booted"), phones[-1])["udid"])
')
  PET_TEST_DESTINATION="platform=iOS Simulator,id=$PET_SIM_ID"
fi
if [[ "$PET_TEST_DESTINATION" == *id=* ]]; then
  PET_SIM_ID="${PET_TEST_DESTINATION##*id=}"
  PET_SIM_ID="${PET_SIM_ID%%,*}"
  xcrun simctl bootstatus "$PET_SIM_ID" -b > "$PET_REPORT_DIR/simulator.log"
fi
# Include the local StoreKit purchase/recovery tests in every full check.
# Serialize tests because SKTestSession mutates the app's shared test catalog.
xcodebuild test -project PetIsland.xcodeproj -scheme PetIslandTips -parallel-testing-enabled NO \
  -destination "$PET_TEST_DESTINATION" -derivedDataPath "$PET_DERIVED_DATA" \
  -resultBundlePath "$PET_REPORT_DIR/Tests.xcresult" \
  CODE_SIGN_IDENTITY=- SWIFT_EMIT_LOC_STRINGS=NO > "$PET_REPORT_DIR/tests.log" 2>&1 || { tail -n 80 "$PET_REPORT_DIR/tests.log"; exit 1; }
xcodebuild build analyze -project PetIsland.xcodeproj -scheme PetIsland \
  -configuration Release -destination 'generic/platform=iOS' \
  -derivedDataPath "$PET_RELEASE_DERIVED_DATA" CODE_SIGNING_ALLOWED=NO \
  SWIFT_EMIT_LOC_STRINGS=NO > "$PET_REPORT_DIR/release.log" 2>&1 || { tail -n 80 "$PET_REPORT_DIR/release.log"; exit 1; }
"$PET_PYTHON" Tools/validate_release_readiness.py --app "$PET_RELEASE_DERIVED_DATA/Build/Products/Release-iphoneos/PetIsland.app" \
  | tee "$PET_REPORT_DIR/release-bundle.log"
printf 'Checks passed. Reports: %s\n' "$PET_REPORT_DIR"
