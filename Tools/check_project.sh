#!/bin/bash
# Modes: all (default), resources, unit, ui, release. UI shards: PET_UI_SHARD=1/6.
set -euo pipefail
cd "$(dirname "$0")/.."
PET_CHECK_MODE="${1:-all}"
case "$PET_CHECK_MODE" in all|resources|unit|ui|release) ;; *) printf 'Unknown check mode: %s\n' "$PET_CHECK_MODE" >&2; exit 2 ;; esac
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
PET_PYTHON="${PET_PYTHON:-python3}"
PET_REPORT_DIR="${PET_REPORT_DIR:-outputs/qa/check-$(date +%Y%m%d-%H%M%S)}"
PET_DERIVED_DATA="${PET_DERIVED_DATA:-outputs/DerivedData}"
PET_RELEASE_DERIVED_DATA="${PET_RELEASE_DERIVED_DATA:-outputs/ReleaseValidation}"
mkdir -p "$PET_REPORT_DIR"

run_logged() {
  local log="$1"
  shift
  printf '\n[%s] Running: %s\n' "$(date '+%H:%M:%S')" "$*"
  # pipefail preserves failures; tee keeps both live output and artifact logs.
  "$@" 2>&1 | tee "$PET_REPORT_DIR/$log"
}

prepare_simulator() {
  run_logged xcode.log xcodebuild -version
  if [[ -z "${PET_TEST_DESTINATION:-}" ]]; then
    PET_SIM_ID=$("$PET_PYTHON" Tools/ci_test_plan.py simulator)
    PET_TEST_DESTINATION="platform=iOS Simulator,id=$PET_SIM_ID"
  fi
  printf 'Test destination: %s\n' "$PET_TEST_DESTINATION"
  if [[ "$PET_TEST_DESTINATION" == *id=* ]]; then
    PET_SIM_ID="${PET_TEST_DESTINATION##*id=}"
    PET_SIM_ID="${PET_SIM_ID%%,*}"
    run_logged simulator.log xcrun simctl bootstatus "$PET_SIM_ID" -b
  fi
}

run_tests() {
  local kind="$1"
  local selectors=()
  local allowance=120 maximum=180
  if [[ "$kind" == unit ]]; then
    selectors=(-only-testing:PetIslandTests)
  elif [[ "$kind" == ui ]]; then
    # Validate the complete selection before starting xcodebuild. Never allow a
    # failed/empty discovery to fall back to running the entire suite silently.
    "$PET_PYTHON" Tools/ci_test_plan.py ui --shard "${PET_UI_SHARD:-1/1}" > "$PET_REPORT_DIR/ui-tests.txt"
    while IFS= read -r selector; do selectors+=("$selector"); done < "$PET_REPORT_DIR/ui-tests.txt"
    [[ ${#selectors[@]} -gt 0 ]]
    printf 'UI shard %s: %s tests\n' "${PET_UI_SHARD:-1/1}" "${#selectors[@]}"
    cat "$PET_REPORT_DIR/ui-tests.txt"
    allowance=180 maximum=300
  else
    allowance=180 maximum=300
  fi
  # Every job owns its simulator; StoreKit and UI cases remain serial within it.
  local command=(xcodebuild test -project PetIsland.xcodeproj -scheme PetIslandTips \
    -parallel-testing-enabled NO -destination "$PET_TEST_DESTINATION" -derivedDataPath "$PET_DERIVED_DATA" \
    -resultBundlePath "$PET_REPORT_DIR/$kind-Tests.xcresult" \
    -test-timeouts-enabled YES -default-test-execution-time-allowance "$allowance" \
    -maximum-test-execution-time-allowance "$maximum")
  # Bash 3.2 (the macOS default) treats an empty array as unset with set -u.
  if [[ "$kind" != all ]]; then command+=("${selectors[@]}"); fi
  run_logged "$kind-tests.log" "${command[@]}" CODE_SIGN_IDENTITY=- SWIFT_EMIT_LOC_STRINGS=NO
}

if [[ "$PET_CHECK_MODE" == all || "$PET_CHECK_MODE" == resources ]]; then
  run_logged ci-tests.log "$PET_PYTHON" -m unittest discover -s Tools -p 'test_ci_*.py'
  run_logged fonts.log "$PET_PYTHON" Tools/validate_timer_fonts.py
  run_logged accessories.log "$PET_PYTHON" Tools/validate_accessories.py
  run_logged gaits.log "$PET_PYTHON" Tools/validate_natural_gaits.py
  run_logged new-pets.log "$PET_PYTHON" Tools/validate_companion_assets.py
  run_logged release-metadata.log "$PET_PYTHON" Tools/validate_release_readiness.py
fi
if [[ "$PET_CHECK_MODE" == all || "$PET_CHECK_MODE" == unit || "$PET_CHECK_MODE" == ui ]]; then
  prepare_simulator
  if [[ "$PET_CHECK_MODE" == all ]]; then run_tests all; else run_tests "$PET_CHECK_MODE"; fi
fi
if [[ "$PET_CHECK_MODE" == all || "$PET_CHECK_MODE" == release ]]; then
  run_logged release.log xcodebuild build analyze -project PetIsland.xcodeproj -scheme PetIsland \
    -configuration Release -destination 'generic/platform=iOS' \
    -derivedDataPath "$PET_RELEASE_DERIVED_DATA" CODE_SIGNING_ALLOWED=NO SWIFT_EMIT_LOC_STRINGS=NO
  run_logged release-bundle.log "$PET_PYTHON" Tools/validate_release_readiness.py \
    --app "$PET_RELEASE_DERIVED_DATA/Build/Products/Release-iphoneos/PetIsland.app"
fi
printf 'Checks passed (%s). Reports: %s\n' "$PET_CHECK_MODE" "$PET_REPORT_DIR"
