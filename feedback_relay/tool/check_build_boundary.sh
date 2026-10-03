#!/usr/bin/env bash
# Build boundary check: test inclusion, production exclusion, conflict
# rejection, and detachment.
#
# Proofs, in order:
#   1. behaviour: the production entry runs with no feedback surface
#   2. behaviour: a production entry with feedback settings stops early
#   3. build: the test variant builds in release mode and holds the tool
#   4. build: the production variant builds and holds no feedback string
#   5. source: the production entry and the app file hold no package import
#   6. detachment: the example still builds when the tool is removed
#
# Run it from the package folder:
#
#   bash tool/check_build_boundary.sh
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
package_dir="$(cd "$here/.." && pwd)"
example_dir="$package_dir/example"
out="$package_dir/build/boundary"
rm -rf "$out"
mkdir -p "$out"

# Strings that exist only in the feedback tool. The build check looks for them
# in the compiled library.
sentinel_schema='avensora-report/1'
sentinel_button='feedback_entry_button'

step() { printf '\n== %s ==\n' "$1"; }

step "1. production entry behaviour"
(cd "$example_dir" && flutter test test_boundary/production_entry_test.dart --reporter=compact 2>&1 | tail -1)

step "2. conflicting production settings are rejected"
(cd "$example_dir" && flutter test test_boundary/production_conflict_test.dart \
  --dart-define=FEEDBACK_BUILD_MODE=test \
  --dart-define=FEEDBACK_BACKEND_URL=https://relay.example.test \
  --dart-define=FEEDBACK_PRODUCT_ID=local-product \
  --dart-define=FEEDBACK_TESTER_TOKEN=test-token \
  --reporter=compact 2>&1 | tail -1)

step "3. test variant build with the tool"
(cd "$example_dir" && flutter build apk --release -t lib/main_test.dart \
  --dart-define=FEEDBACK_BUILD_MODE=test \
  --dart-define=FEEDBACK_BACKEND_URL=https://relay.example.test \
  --dart-define=FEEDBACK_PRODUCT_ID=local-product \
  --dart-define=FEEDBACK_TESTER_TOKEN=test-token 2>&1 | tail -2)
cp "$example_dir/build/app/outputs/flutter-apk/app-release.apk" "$out/test-variant.apk"

step "4. production variant build without the tool"
(cd "$example_dir" && flutter build apk --release -t lib/main_production.dart 2>&1 | tail -2)
cp "$example_dir/build/app/outputs/flutter-apk/app-release.apk" "$out/production-variant.apk"

count() {
  local apk="$1" needle="$2" work
  work="$(mktemp -d)"
  unzip -o -q "$apk" 'lib/*/libapp.so' -d "$work" 2>/dev/null || true
  local hits=0
  while IFS= read -r so; do
    if grep -a -q -- "$needle" "$so"; then hits=$((hits + 1)); fi
  done < <(find "$work" -name 'libapp.so')
  rm -rf "$work"
  printf '%s' "$hits"
}

step "5. compiled library check"
test_hits_schema="$(count "$out/test-variant.apk" "$sentinel_schema")"
test_hits_button="$(count "$out/test-variant.apk" "$sentinel_button")"
prod_hits_schema="$(count "$out/production-variant.apk" "$sentinel_schema")"
prod_hits_button="$(count "$out/production-variant.apk" "$sentinel_button")"
printf 'test variant   : %s schema hits, %s button hits\n' "$test_hits_schema" "$test_hits_button"
printf 'production     : %s schema hits, %s button hits\n' "$prod_hits_schema" "$prod_hits_button"
if [ "$test_hits_schema" -lt 1 ]; then
  echo 'FAIL: the test variant does not hold the feedback tool.'
  exit 1
fi
if [ "$prod_hits_schema" -ne 0 ] || [ "$prod_hits_button" -ne 0 ]; then
  echo 'FAIL: the production variant holds feedback code.'
  exit 1
fi

step "6. source boundary"
if grep -q "feedback_relay" "$example_dir/lib/main_production.dart" "$example_dir/lib/app.dart"; then
  echo 'FAIL: the production entry or the app file imports the feedback package.'
  exit 1
fi
echo 'PASS: the production entry and the app file hold no feedback import.'
(cd "$example_dir" && flutter analyze lib/main_production.dart lib/app.dart 2>&1 | tail -1)

step "7. detachment: the example builds without the tool"
detach="$(mktemp -d)"
cp -r "$example_dir/." "$detach/example"
rm -rf "$detach/example/build" "$detach/example/.dart_tool" "$detach/example/test" "$detach/example/test_boundary" \
  "$detach/example/lib/main_test.dart" "$detach/example/lib/main_development.dart" "$detach/example/lib/host_setup.dart"
sed -i '/feedback_relay:/,+1d; /device_info_plus:/d; /path_provider:/d' "$detach/example/pubspec.yaml"
(cd "$detach/example" && flutter pub get >/dev/null && flutter build apk --release -t lib/main_production.dart 2>&1 | tail -2)
cp "$detach/example/build/app/outputs/flutter-apk/app-release.apk" "$out/detached-variant.apk"
rm -rf "$detach"

step "boundary check passed"
ls -l "$out"
